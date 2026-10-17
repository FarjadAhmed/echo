import Combine
import Foundation

/// One received message in the demo inbox.
struct InboxItem: Identifiable, Equatable {
    let id: UUID
    let kind: ComposeKind
    let sender: String
    let subject: String
    let body: String
    var isRead: Bool

    init(id: UUID = UUID(), kind: ComposeKind, sender: String, subject: String, body: String, isRead: Bool = false) {
        self.id = id
        self.kind = kind
        self.sender = sender
        self.subject = subject
        self.body = body
        self.isRead = isRead
    }

    /// "Text from Anna" or "Email from Mom", for headings and labels.
    var title: String {
        "\(kind == .email ? "Email" : "Text") from \(sender)"
    }

    /// What ECHO reads aloud for this message.
    var spokenText: String {
        var parts = ["\(title)."]
        if !subject.isEmpty {
            parts.append("Subject: \(subject).")
        }
        parts.append(body)
        return parts.joined(separator: " ")
    }
}

/// Demo inbox seeded from DemoData. Nothing here is real mail; it exists so the read-aloud
/// and reply flows can be shown without accounts.
@MainActor
final class InboxStore: ObservableObject {
    @Published private(set) var items: [InboxItem] = []

    init() {
        resetDemoData()
    }

    var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }

    /// The first unread message in inbox order, or nil when everything has been read.
    func nextUnread() -> InboxItem? {
        items.first { !$0.isRead }
    }

    func markRead(_ item: InboxItem) {
        markRead(id: item.id)
    }

    func markRead(id: InboxItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }), !items[index].isRead else { return }
        items[index].isRead = true
    }

    /// Puts the sample messages back and marks them all unread.
    func resetDemoData() {
        items = DemoData.inbox.map { seed in
            InboxItem(
                kind: seed.kind == "email" ? .email : .text,
                sender: seed.sender,
                subject: seed.subject,
                body: seed.body
            )
        }
    }
}
