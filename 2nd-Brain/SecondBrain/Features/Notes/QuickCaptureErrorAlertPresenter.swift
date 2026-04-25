#if canImport(UIKit) && !os(watchOS)
import SwiftUI
import UIKit

internal struct QuickCaptureErrorAlertPresenter: UIViewControllerRepresentable {
    @Binding var message: String?
    let accessibilityIdentifier: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(message: $message)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        let coordinator = context.coordinator
        let presentingViewController = topPresentedController(
            from: viewController.view.window?.rootViewController ?? viewController
        )

        guard let message else {
            if let ownedAlert = coordinator.ownedAlert,
               presentingViewController === ownedAlert {
                ownedAlert.dismiss(animated: true)
                coordinator.ownedAlert = nil
            }

            return
        }

        if let ownedAlert = coordinator.ownedAlert,
           presentingViewController === ownedAlert {
            ownedAlert.message = message
            ownedAlert.view.accessibilityIdentifier = accessibilityIdentifier
            return
        }

        let alertController = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alertController.view.accessibilityIdentifier = accessibilityIdentifier
        alertController.addAction(
            UIAlertAction(title: "OK", style: .cancel) { [weak coordinator] _ in
                coordinator?.message.wrappedValue = nil
                coordinator?.ownedAlert = nil
            }
        )

        DispatchQueue.main.async {
            guard presentingViewController.presentedViewController == nil else {
                return
            }

            coordinator.ownedAlert = alertController
            presentingViewController.present(alertController, animated: true)
        }
    }

    private func topPresentedController(from rootViewController: UIViewController) -> UIViewController {
        var currentViewController = rootViewController

        while let presentedViewController = currentViewController.presentedViewController {
            currentViewController = presentedViewController
        }

        return currentViewController
    }

    final class Coordinator {
        let message: Binding<String?>
        weak var ownedAlert: UIAlertController?

        init(message: Binding<String?>) {
            self.message = message
        }
    }
}
#endif
