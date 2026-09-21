import UIKit

class MainView: UIView {
    let title = UILabel()
    
    init() {
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        title.text = "Hello, World!"
        
        addSubview(title)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        title.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    }
}

class MainViewController: UIViewController {
    override func loadView() {
        view = MainView()
    }
    
    override func viewDidLoad() {
    }
}
