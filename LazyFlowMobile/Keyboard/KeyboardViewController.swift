import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private var model: KeyboardModel?
    private var host: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()

        let model = KeyboardModel(
            hasFullAccess: hasFullAccess,
            insertText: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
            }
        )
        let root = KeyboardRootView(
            model: model,
            nextKeyboard: { [weak self] in
                self?.advanceToNextInputMode()
            },
            openLazyFlow: { [weak self, weak model] in
                model?.prepareAppHandoff()
                guard let url = URL(string: "lazyflow://start"),
                      let context = self?.extensionContext else {
                    model?.completeAppHandoff(opened: false)
                    return
                }
                context.open(url) { opened in
                    Task { @MainActor in
                        model?.completeAppHandoff(opened: opened)
                    }
                }
            }
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear

        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)

        let heightConstraint = view.heightAnchor.constraint(equalToConstant: 258)
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true

        self.model = model
        self.host = host
        self.heightConstraint = heightConstraint
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model?.updateFullAccess(hasFullAccess)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        heightConstraint?.constant = size.width > size.height ? 210 : 258
    }
}
