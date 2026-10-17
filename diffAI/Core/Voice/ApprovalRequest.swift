import Foundation

/// Something ECHO wants to do that has consequences. Shown on the approval screen and spoken aloud.
/// Nothing in here runs until the user says yes, taps Confirm, or (for sensitive steps) passes Face ID.
struct ApprovalRequest: Identifiable, Equatable {
    struct Row: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let value: String
    }

    let id = UUID()
    /// Short heading, e.g. "Call Mom" or "Submit the appointment form".
    let title: String
    /// One or two spoken sentences that say exactly what will happen.
    let summary: String
    /// Details shown as label/value rows and read aloud one by one.
    let rows: [Row]
    /// Extra warning for payments, sign-ins, or anything hard to undo.
    let caution: String?
    /// Requires Face ID or passcode before running. Used for payments and sign-ins.
    let requiresBiometric: Bool
    /// Label of the confirm button, e.g. "Confirm and submit".
    let confirmLabel: String

    init(
        title: String,
        summary: String,
        rows: [Row] = [],
        caution: String? = nil,
        requiresBiometric: Bool = false,
        confirmLabel: String = "Confirm"
    ) {
        self.title = title
        self.summary = summary
        self.rows = rows
        self.caution = caution
        self.requiresBiometric = requiresBiometric
        self.confirmLabel = confirmLabel
    }

    /// Everything spoken when the request appears.
    var spokenText: String {
        var parts = [summary]
        for row in rows {
            let value = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let ends = value.last.map { ".!?".contains($0) } ?? false
            parts.append("\(row.label): \(value)\(ends ? "" : ".")")
        }
        if let caution {
            parts.append(caution)
        }
        parts.append("Say yes to confirm, or no to cancel.")
        return parts.joined(separator: " ")
    }
}

/// What a multi-step dialog wants next.
enum DialogStep {
    /// Ask the user something and wait for their spoken or typed reply.
    case ask(String)
    /// Show an approval request. `run` executes after the user confirms and returns the sentence to speak.
    case approve(ApprovalRequest, run: () async -> String)
    /// The dialog is over. Speak this and go back to normal conversation.
    case finish(String)
}

/// A short guided dialog, such as composing a message or setting a reminder that needs a time.
/// The conversation engine routes the user's replies here until the flow finishes.
/// Saying "stop", "cancel", or "never mind" always ends the flow.
@MainActor
protocol DialogFlow: AnyObject {
    /// Called once when the flow begins.
    func start() async -> DialogStep
    /// Called with each reply from the user.
    func handle(_ reply: String) async -> DialogStep
}
