import Combine
import Foundation
import MessageUI
import UIKit

enum ComposeKind {
    case email
    case text

    /// "email" or "text", for spoken sentences.
    var spokenWord: String {
        switch self {
        case .email: return "email"
        case .text: return "text"
        }
    }

    /// The system app that actually sends it.
    var appName: String {
        switch self {
        case .email: return "Mail"
        case .text: return "Messages"
        }
    }
}

/// A message ready to hand to the system compose sheet.
struct ComposeDraft: Identifiable {
    let id = UUID()
    let kind: ComposeKind
    let recipient: ContactCard
    let subject: String
    let body: String
}

/// Opens the system Mail or Messages compose sheet with the message already filled in.
///
/// iOS does not let third-party apps send email or SMS silently: the user must tap Send in the
/// system sheet (MFMailComposeViewController / MFMessageComposeViewController). Sending without that
/// tap would need our own backend (an email or SMS gateway), which is out of scope for this app.
@MainActor
final class ComposeCoordinator: ObservableObject {
    /// Set when a sheet should be shown. `composeSheets(_:onFinish:)` presents it and clears it afterwards.
    @Published var draft: ComposeDraft?

    /// Prepares the message and returns the sentence to speak.
    /// Prefers the in-app sheet; falls back to a mailto: or sms: link; otherwise explains why it cannot.
    func present(_ kind: ComposeKind, to card: ContactCard, body: String, subject: String = "") -> String {
        let canUseSheet: Bool
        switch kind {
        case .email: canUseSheet = MFMailComposeViewController.canSendMail()
        case .text: canUseSheet = MFMessageComposeViewController.canSendText()
        }

        if canUseSheet {
            draft = ComposeDraft(kind: kind, recipient: card, subject: subject, body: body)
            return "Your \(kind.spokenWord) to \(card.name) is ready. Tap Send in the message window to send it."
        }

        if let url = fallbackURL(kind, to: card, body: body, subject: subject), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return "I opened \(kind.appName) with your \(kind.spokenWord) to \(card.name). Tap Send there to send it."
        }

        let missing = kind == .email ? "an email address" : "a phone number"
        let reason = (kind == .email ? card.email : card.phone) == nil
            ? "I do not have \(missing) for \(card.name)."
            : "This device cannot send \(kind.spokenWord)s."
        return "\(reason) Your message was: \(body)"
    }

    // MARK: - Private

    private func fallbackURL(_ kind: ComposeKind, to card: ContactCard, body: String, subject: String) -> URL? {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?+"))
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        switch kind {
        case .email:
            guard let email = card.email else { return nil }
            let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return URL(string: "mailto:\(email)?subject=\(encodedSubject)&body=\(encodedBody)")
        case .text:
            guard let phone = card.phone else { return nil }
            return URL(string: "sms:\(phone)&body=\(encodedBody)")
        }
    }
}
