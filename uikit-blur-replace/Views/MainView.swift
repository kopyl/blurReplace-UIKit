import UIKit

/// UIKit equivalent of:
///
///     VStack {
///         Button {
///             isHello.toggle()
///         } label: {
///             Text(isHello ? "Hello" : "World")
///                 .transition(.blurReplace)
///                 .id(isHello)
///         }
///     }
final class BlurReplaceButton: UIControl {
    let stage = BlurReplaceView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        stage.isUserInteractionEnabled = false
        stage.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stage)
        NSLayoutConstraint.activate([
            stage.leadingAnchor.constraint(equalTo: leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: trailingAnchor),
            stage.topAnchor.constraint(equalTo: topAnchor),
            stage.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            // Matches the press feedback of SwiftUI's default button style.
            UIView.animate(withDuration: 0.12) {
                self.alpha = self.isHighlighted ? 0.35 : 1
            }
        }
    }
}

class MainView: UIView {
    let button = BlurReplaceButton()

    init() {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}

class MainViewController: UIViewController {
    private var isHello = true

    private var mainView: MainView { view as! MainView }

    override func loadView() {
        view = MainView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // The app background asset is dark in both appearances.
        overrideUserInterfaceStyle = .dark

        mainView.button.stage.setContent(makeLabel(), animated: false)
        mainView.button.addTarget(self, action: #selector(toggle), for: .touchUpInside)
    }

    private func makeLabel() -> UILabel {
        let label = UILabel()
        label.text = isHello ? "Hello" : "World"
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = view.tintColor
        return label
    }

    @objc private func toggle() {
        isHello.toggle()
        mainView.button.stage.setContent(makeLabel())
    }
}
