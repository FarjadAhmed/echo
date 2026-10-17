import Foundation

/// Reads unread messages aloud one at a time. After each one the user can say next, reply, or stop.
/// Replying asks for the text, reads it back, then asks approval to open the system compose sheet.
@MainActor
final class ReadInboxFlow: DialogFlow {
    private enum Stage {
        case listening
        case replyBody
        case replyConfirm
    }

    private let inbox: InboxStore
    private let contacts: ContactsDirectory
    private let compose: ComposeCoordinator
    private let ai: any AIService

    private var current: InboxItem?
    private var replyBody = ""
    private var stage: Stage = .listening
    private var repeatedOptions = false

    init(inbox: InboxStore, contacts: ContactsDirectory, compose: ComposeCoordinator, ai: any AIService) {
        self.inbox = inbox
        self.contacts = contacts
        self.compose = compose
        self.ai = ai
    }

    func start() async -> DialogStep {
        guard let item = inbox.nextUnread() else {
            return .finish("You have no unread messages.")
        }
        return readAloud(item)
    }

    func handle(_ reply: String) async -> DialogStep {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        switch stage {
        case .listening:
            return handleListening(trimmed)
        case .replyBody:
            guard let item = current else { return .finish("There is no message to reply to.") }
            guard !trimmed.isEmpty else { return .ask("What do you want to say to \(item.sender)?") }
            replyBody = trimmed
            stage = .replyConfirm
            return .ask(MessageReadBackReply.readBack(replyBody, noun: "reply"))
        case .replyConfirm:
            return await handleReplyConfirm(trimmed)
        }
    }

    // MARK: - Steps

    private func readAloud(_ item: InboxItem) -> DialogStep {
        inbox.markRead(item)
        current = item
        stage = .listening
        repeatedOptions = false
        return .ask("\(MessageReadBackReply.ensurePeriod(item.spokenText)) Say next, reply, or stop.")
    }

    private func handleListening(_ reply: String) -> DialogStep {
        let words = ContactsDirectory.normalized(reply)
        let nextWords: Set<String> = ["next", "next one", "next message", "skip", "continue", "go on"]
        let replyWords: Set<String> = ["reply", "answer", "respond", "reply to it", "write back", "reply to this"]
        let againWords: Set<String> = ["again", "repeat", "say that again", "read it again", "repeat that"]

        if nextWords.contains(words) {
            guard let item = inbox.nextUnread() else {
                return .finish("That was the last one.")
            }
            return readAloud(item)
        }
        if replyWords.contains(words) {
            guard let item = current else { return .finish("There is no message to reply to.") }
            stage = .replyBody
            return .ask("What do you want to say to \(item.sender)?")
        }
        if againWords.contains(words), let item = current {
            return .ask("\(MessageReadBackReply.ensurePeriod(item.spokenText)) Say next, reply, or stop.")
        }
        if !repeatedOptions {
            repeatedOptions = true
            return .ask("You can say next to hear the next message, reply to answer this one, or stop.")
        }
        return .finish("Okay. Say read my messages when you want to continue.")
    }

    private func handleReplyConfirm(_ reply: String) async -> DialogStep {
        guard let item = current else { return .finish("There is no message to reply to.") }
        switch MessageReadBackReply.classify(reply) {
        case .confirm:
            return approvalStep(for: item)
        case .polish:
            if let polished = try? await ai.draftMessage(intent: replyBody), !polished.isEmpty {
                replyBody = polished.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return .ask(MessageReadBackReply.readBack(replyBody, noun: "reply"))
        case .sayAgain:
            stage = .replyBody
            return .ask("Okay. What do you want to say to \(item.sender)?")
        case .newBody:
            replyBody = reply
            return .ask(MessageReadBackReply.readBack(replyBody, noun: "reply"))
        }
    }

    private func approvalStep(for item: InboxItem) -> DialogStep {
        let card = contacts.find(item.sender) ?? ContactCard(name: item.sender, phone: nil, email: nil)
        let kind = item.kind
        let compose = compose
        let body = replyBody
        let subject = item.subject.isEmpty ? "" : "Re: \(item.subject)"
        let request = ApprovalRequest(
            title: "Reply to \(card.name)",
            summary: "I will open \(kind.appName) with this \(kind.spokenWord) to \(card.name). You tap Send there.",
            rows: [
                ApprovalRequest.Row(label: "To", value: card.name),
                ApprovalRequest.Row(label: "Message", value: body),
            ],
            confirmLabel: "Open \(kind.appName)"
        )
        return .approve(request, run: { @MainActor in
            compose.present(kind, to: card, body: body, subject: subject)
        })
    }
}
