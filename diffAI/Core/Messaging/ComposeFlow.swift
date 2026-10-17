import Foundation

/// How the user answered the "your message says ..." read-back. Shared by the compose and reply flows.
enum MessageReadBackReply {
    case confirm
    case polish
    case sayAgain
    case newBody

    /// Classifies a reply case-insensitively, ignoring punctuation.
    static func classify(_ reply: String) -> MessageReadBackReply {
        let words = ContactsDirectory.normalized(reply)
        let confirmWords: Set<String> = ["yes", "yeah", "yep", "sure", "continue", "send", "send it", "ok", "okay", "yes please", "go ahead", "sounds good", "correct", "that is right", "thats right"]
        let polishWords: Set<String> = ["polish", "polish it", "tidy", "tidy it up", "tidy up", "improve", "improve it", "make it nicer", "clean it up", "fix it"]
        let againWords: Set<String> = ["say it again", "again", "change", "change it", "redo", "start over", "no", "different", "something else", "let me say it again"]

        if confirmWords.contains(words) { return .confirm }
        if polishWords.contains(words) { return .polish }
        if againWords.contains(words) { return .sayAgain }
        return .newBody
    }

    /// The read-back question for a message body.
    static func readBack(_ body: String, noun: String = "message") -> String {
        "Your \(noun) says: \(Self.ensurePeriod(body)) Say yes to continue, polish to have ECHO tidy it up, or say it again to change it."
    }

    static func ensurePeriod(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return trimmed }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }
}

/// Guided dialog for writing a new text or email: who, what, read it back, then approve opening the system sheet.
@MainActor
final class ComposeFlow: DialogFlow {
    private enum Stage {
        case recipient
        case body
        case confirm
    }

    private let kind: ComposeKind
    private let contacts: ContactsDirectory
    private let compose: ComposeCoordinator
    private let ai: any AIService

    private var recipient: ContactCard?
    private var body = ""
    private var stage: Stage = .recipient
    private var recipientMisses = 0

    /// initialBody is a message the user already said ("text Anna saying I'll be late"). When it is
    /// given together with a recipient, the flow goes straight to reading it back.
    init(
        kind: ComposeKind,
        contacts: ContactsDirectory,
        compose: ComposeCoordinator,
        ai: any AIService,
        recipient: ContactCard? = nil,
        initialBody: String? = nil
    ) {
        self.kind = kind
        self.contacts = contacts
        self.compose = compose
        self.ai = ai
        self.recipient = recipient
        self.body = initialBody?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func start() async -> DialogStep {
        if recipient != nil {
            if !body.isEmpty {
                stage = .confirm
                return .ask(MessageReadBackReply.readBack(body))
            }
            stage = .body
            return .ask(askForBody())
        }
        stage = .recipient
        return .ask("Who do you want to send it to?")
    }

    func handle(_ reply: String) async -> DialogStep {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        switch stage {
        case .recipient:
            return handleRecipient(trimmed)
        case .body:
            guard !trimmed.isEmpty else { return .ask(askForBody()) }
            body = trimmed
            stage = .confirm
            return .ask(MessageReadBackReply.readBack(body))
        case .confirm:
            return await handleConfirm(trimmed)
        }
    }

    // MARK: - Steps

    private func handleRecipient(_ reply: String) -> DialogStep {
        guard let card = contacts.find(reply) else {
            recipientMisses += 1
            if recipientMisses >= 2 {
                return .finish("I could not find that person. Say send a \(kind.spokenWord) to try again.")
            }
            return .ask("I know \(contacts.spokenDemoNames). Who should it go to?")
        }
        recipient = card
        if !body.isEmpty {
            stage = .confirm
            return .ask(MessageReadBackReply.readBack(body))
        }
        stage = .body
        return .ask(askForBody())
    }

    private func handleConfirm(_ reply: String) async -> DialogStep {
        switch MessageReadBackReply.classify(reply) {
        case .confirm:
            return approvalStep()
        case .polish:
            if let polished = try? await ai.draftMessage(intent: body), !polished.isEmpty {
                body = polished.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return .ask(MessageReadBackReply.readBack(body))
        case .sayAgain:
            stage = .body
            return .ask("Okay. " + askForBody())
        case .newBody:
            body = reply
            return .ask(MessageReadBackReply.readBack(body))
        }
    }

    private func askForBody() -> String {
        if let name = recipient?.name {
            return "What do you want to say to \(name)?"
        }
        return "What do you want to say?"
    }

    private func approvalStep() -> DialogStep {
        let card = recipient ?? contacts.emergencyContact
        let kind = kind
        let compose = compose
        let body = body
        let request = ApprovalRequest(
            title: "Send \(kind.spokenWord) to \(card.name)",
            summary: "I will open \(kind.appName) with this \(kind.spokenWord) to \(card.name). You tap Send there.",
            rows: [
                ApprovalRequest.Row(label: "To", value: card.name),
                ApprovalRequest.Row(label: "Message", value: body),
            ],
            confirmLabel: "Open \(kind.appName)"
        )
        return .approve(request, run: { @MainActor in
            compose.present(kind, to: card, body: body)
        })
    }
}
