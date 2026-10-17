import MessageUI
import SwiftUI
import UIKit

/// The system Mail compose sheet, pre-filled from a draft. Calls `onFinish` with a short spoken result.
struct MailComposeView: UIViewControllerRepresentable {
    let draft: ComposeDraft
    let onFinish: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        if let email = draft.recipient.email {
            controller.setToRecipients([email])
        }
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: (String) -> Void

        init(onFinish: @escaping (String) -> Void) {
            self.onFinish = onFinish
        }

        nonisolated func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            let spoken: String
            switch result {
            case .sent: spoken = "Email sent."
            case .saved: spoken = "Email saved as a draft."
            case .cancelled: spoken = "Email cancelled."
            case .failed: spoken = "The email could not be sent."
            @unknown default: spoken = "Email window closed."
            }
            Task { @MainActor in
                self.onFinish(spoken)
            }
        }
    }
}

/// The system Messages compose sheet, pre-filled from a draft. Calls `onFinish` with a short spoken result.
struct MessageComposeView: UIViewControllerRepresentable {
    let draft: ComposeDraft
    let onFinish: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        if let phone = draft.recipient.phone {
            controller.recipients = [phone]
        }
        controller.body = draft.body
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let onFinish: (String) -> Void

        init(onFinish: @escaping (String) -> Void) {
            self.onFinish = onFinish
        }

        nonisolated func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            let spoken: String
            switch result {
            case .sent: spoken = "Text sent."
            case .cancelled: spoken = "Text cancelled."
            case .failed: spoken = "The text could not be sent."
            @unknown default: spoken = "Message window closed."
            }
            Task { @MainActor in
                self.onFinish(spoken)
            }
        }
    }
}

/// Presents the right compose sheet whenever the coordinator has a draft, and clears it when done.
private struct ComposeSheetsModifier: ViewModifier {
    @ObservedObject var coordinator: ComposeCoordinator
    let onFinish: (String) -> Void
    @State private var reported = false

    func body(content: Content) -> some View {
        content.sheet(item: $coordinator.draft, onDismiss: handleDismiss) { draft in
            Group {
                switch draft.kind {
                case .email:
                    MailComposeView(draft: draft, onFinish: finish)
                case .text:
                    MessageComposeView(draft: draft, onFinish: finish)
                }
            }
            .ignoresSafeArea()
        }
    }

    private func finish(_ spoken: String) {
        reported = true
        coordinator.draft = nil
        onFinish(spoken)
    }

    /// Covers the sheet being swiped away without the delegate firing.
    private func handleDismiss() {
        if !reported {
            onFinish("Message window closed. Nothing was sent.")
        }
        reported = false
    }
}

extension View {
    /// Shows the Mail or Messages compose sheet for `coordinator.draft`.
    /// `onFinish` receives a short sentence to speak, such as "Text sent." or "Email cancelled."
    func composeSheets(_ coordinator: ComposeCoordinator, onFinish: @escaping (String) -> Void) -> some View {
        modifier(ComposeSheetsModifier(coordinator: coordinator, onFinish: onFinish))
    }
}
