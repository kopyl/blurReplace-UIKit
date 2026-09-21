import UIKit

// MARK: - Reverse-engineered constants
//
// Extracted from SwiftUICore.framework (iOS 26.3 simulator runtime) by disassembling
// `BlurReplaceTransition.body(content:phase:)`:
//
//   $s7SwiftUI21BlurReplaceTransitionV4body7content5phaseQrAA22PlaceholderContentViewVyACG_AA0E5PhaseOtF
//
// The returned view tree is literally:
//   ModifiedContent<ModifiedContent<ModifiedContent<Content, OpacityRendererEffect>,
//                                   _BlurEffect>,
//                   _ScaleEffect>
//
// i.e. content.opacity(o).blur(radius: r, opaque: false).scaleEffect(s, anchor: .center)
//
// with the per-phase constants read out of __TEXT:
//
//   phase            opacity   blurRadius   scale
//   .identity          1.0        0.0        1.0
//   .willAppear        0.0        7.0        0.9
//   .didDisappear      0.0        7.0        0.9  (.downUp, the default)
//   .didDisappear      0.0        7.0        1.1  (.upUp)
//
//   anchor = (0.5, 0.5), _BlurEffect.isOpaque = false
//
// `Animation.default` on modern deployment targets resolves to
// `FluidSpringAnimation(duration: 0.5, dampingFraction: 1.0, blendDuration: 0.0)`
// (constants at __TEXT:0xb960d0), i.e. a critically damped spring with
// omega = 2 * pi / 0.5.

enum BlurReplace {
    static let blurRadius: CGFloat = 7.0
    static let insertionScale: CGFloat = 0.9

    /// SwiftUI's `Animation.default` on iOS 17+.
    static let springDuration: Double = 0.5
    static let springDampingRatio: Double = 1.0

    enum Configuration {
        case downUp
        case upUp

        var removalScale: CGFloat {
            switch self {
            case .downUp: return 0.9
            case .upUp: return 1.1
            }
        }
    }
}

// MARK: - SwiftUI's fluid spring, solved analytically

/// Critically damped (dampingRatio == 1) spring matching SwiftUI's
/// `Spring(duration:bounce:)` parameterisation, where `omega = 2 * pi / duration`.
///
/// Solved in closed form so the result is frame-rate independent and so that
/// retargeting mid-flight preserves velocity — which is what makes repeated taps
/// feel like SwiftUI rather than like a restarted `UIView.animate`.
struct FluidSpring {
    let omega: Double

    init(duration: Double = BlurReplace.springDuration) {
        omega = 2 * .pi / duration
    }

    struct State {
        var value: Double
        var velocity: Double
        var target: Double

        var isSettled: Bool {
            abs(value - target) < 0.0005 && abs(velocity) < 0.0005
        }
    }

    /// Advances `state` by `dt` seconds.
    func step(_ state: inout State, dt: Double) {
        guard dt > 0 else { return }

        // x(t) = (A + B t) e^(-omega t), where x is the displacement from target.
        let a = state.value - state.target
        let b = state.velocity + omega * a
        let decay = exp(-omega * dt)

        let x = (a + b * dt) * decay
        let v = (b - omega * (a + b * dt)) * decay

        state.value = state.target + x
        state.velocity = v

        if state.isSettled {
            state.value = state.target
            state.velocity = 0
        }
    }
}

// MARK: - Private CAFilter bridge

/// SwiftUI's `_BlurEffect` lowers to a CoreAnimation `gaussianBlur` filter on the
/// layer. `CAFilter` is SPI, so it is reached reflectively here. Radius is driven
/// through the layer key path so CoreAnimation observes the change.
enum GaussianBlurFilter {
    static let name = "blurReplaceGaussian"

    static func make() -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else {
            assertionFailure("CAFilter unavailable")
            return nil
        }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector),
              let filter = filterClass.perform(selector, with: "gaussianBlur")?
                  .takeUnretainedValue() as? NSObject
        else {
            return nil
        }
        filter.setValue(name, forKey: "name")
        // `_BlurEffect.isOpaque == false`, so edges sample transparency rather than
        // being clamped.
        filter.setValue(false, forKey: "inputNormalizeEdges")
        return filter
    }

    static func setRadius(_ radius: CGFloat, on layer: CALayer) {
        layer.setValue(radius, forKeyPath: "filters.\(name).inputRadius")
    }
}

// MARK: - The transition container

/// Drop-in container that reproduces `.transition(.blurReplace)` for arbitrary
/// UIKit subviews. Call `setContent(_:animated:)` to swap; the outgoing and
/// incoming views animate simultaneously, each with its own spring state.
final class BlurReplaceView: UIView {

    var configuration: BlurReplace.Configuration = .downUp

    private final class Child {
        let view: UIView
        var state: FluidSpring.State
        /// The scale this child rests at when `presence == 0`.
        var restScale: CGFloat
        var hasFilter = false

        init(view: UIView, presence: Double, restScale: CGFloat) {
            self.view = view
            self.state = .init(value: presence, velocity: 0, target: presence)
            self.restScale = restScale
        }
    }

    private var children: [Child] = []
    private let spring = FluidSpring()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    // The container resizes to the incoming content on the same spring, so the
    // surrounding layout eases instead of snapping when the text changes width.
    private var widthState = FluidSpring.State(value: 0, velocity: 0, target: 0)
    private var heightState = FluidSpring.State(value: 0, velocity: 0, target: 0)
    private var hasContent = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        guard hasContent else { return super.intrinsicContentSize }
        return CGSize(width: max(0, widthState.value), height: max(0, heightState.value))
    }

    // MARK: Content

    func setContent(_ newView: UIView, animated: Bool = true) {
        let shouldAnimate = animated && hasContent

        for child in children {
            child.state.target = 0
            child.restScale = configuration.removalScale
        }

        let child = Child(
            view: newView,
            presence: shouldAnimate ? 0 : 1,
            restScale: BlurReplace.insertionScale
        )
        child.state.target = 1
        children.append(child)

        newView.translatesAutoresizingMaskIntoConstraints = false
        newView.layer.allowsEdgeAntialiasing = true
        addSubview(newView)
        NSLayoutConstraint.activate([
            newView.centerXAnchor.constraint(equalTo: centerXAnchor),
            newView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let fitting = newView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        widthState.target = fitting.width
        heightState.target = fitting.height

        if shouldAnimate {
            hasContent = true
            invalidateIntrinsicContentSize()
            apply()
            startDisplayLink()
        } else {
            for stale in children where stale !== child {
                stale.view.removeFromSuperview()
            }
            children = [child]
            child.state.value = 1
            child.state.velocity = 0
            widthState.value = fitting.width
            widthState.velocity = 0
            heightState.value = fitting.height
            heightState.velocity = 0
            hasContent = true
            invalidateIntrinsicContentSize()
            apply()
        }
    }

    // MARK: Driving

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        // `targetTimestamp` is when this frame will actually be on screen, which is
        // the value SwiftUI integrates against.
        let now = link.targetTimestamp
        if lastTimestamp == 0 {
            lastTimestamp = now
            return
        }
        let dt = min(now - lastTimestamp, 1.0 / 20.0)
        lastTimestamp = now

        for child in children {
            spring.step(&child.state, dt: dt)
        }
        spring.step(&widthState, dt: dt)
        spring.step(&heightState, dt: dt)

        // Retire fully faded-out children.
        let finished = children.filter { $0.state.target == 0 && $0.state.isSettled }
        for child in finished {
            child.view.removeFromSuperview()
        }
        children.removeAll { child in finished.contains { $0 === child } }

        invalidateIntrinsicContentSize()
        apply()

        if children.allSatisfy({ $0.state.isSettled }),
           widthState.isSettled, heightState.isSettled {
            stopDisplayLink()
        }
    }

    // MARK: Effect application

    private func apply() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for child in children {
            let presence = CGFloat(max(0, min(1, child.state.value)))
            let layer = child.view.layer

            // opacity: 0 -> 1
            layer.opacity = Float(presence)

            // scale: restScale -> 1, anchored at the centre
            let scale = child.restScale + (1 - child.restScale) * presence
            layer.transform = CATransform3DMakeScale(scale, scale, 1)

            // blur radius: 7 -> 0
            let radius = BlurReplace.blurRadius * (1 - presence)
            setBlur(radius, on: child)
        }
    }

    private func setBlur(_ radius: CGFloat, on child: Child) {
        let layer = child.view.layer

        // Drop the filter entirely at rest: an installed filter forces an offscreen
        // pass, which very slightly changes text rasterisation.
        if radius <= 0.01 {
            if child.hasFilter {
                layer.filters = nil
                child.hasFilter = false
            }
            return
        }

        if !child.hasFilter {
            guard let filter = GaussianBlurFilter.make() else { return }
            layer.filters = [filter]
            child.hasFilter = true
        }
        GaussianBlurFilter.setRadius(radius, on: layer)
    }
}
