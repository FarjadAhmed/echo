import SwiftUI

/// The Messages screen: unread count, three big actions, and the demo inbox.
/// Every action goes through the conversation engine, so voice and touch share one path.
struct MessagesView: View {
    @EnvironmentObject private var inbox: InboxStore
    @EnvironmentObject private var conversation: ConversationEngine
    @EnvironmentObject private var speechOutput: SpeechOutputCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                header
                actions
                messageList
            }
            .padding(.horizontal, 20)
            .padding(.vertical)
        }
        .echoBackground()
        .navigationTitle("Messages")
        .onAppear {
            Task { await speechOutput.announceScreen(AppScreen.messages.announcement) }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 16) {
            IconTile(systemName: inbox.unreadCount == 0 ? "envelope.open.fill" : "envelope.badge.fill", color: Color(.systemBlue), size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(unreadHeadline)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.text)
                Text("\(inbox.items.count) messages in your inbox")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.minTapHeight, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }

    private var unreadHeadline: String {
        switch inbox.unreadCount {
        case 0: return "No unread messages"
        case 1: return "1 unread message"
        default: return "\(inbox.unreadCount) unread messages"
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                conversation.submitTyped("read my messages")
            } label: {
                Label("Read unread aloud", systemImage: "speaker.wave.2.fill")
                    .labelStyle(BigLabelStyle())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityLabel("Read unread aloud")
            .accessibilityHint("Reads your unread messages one at a time. You can say next, reply, or stop.")

            Button {
                conversation.submitTyped("send a text")
            } label: {
                Label("New text", systemImage: "message.fill")
                    .labelStyle(BigLabelStyle())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel("New text")
            .accessibilityHint("Starts a text message. ECHO asks who it is for and what to say.")

            Button {
                conversation.submitTyped("send an email")
            } label: {
                Label("New email", systemImage: "envelope.fill")
                    .labelStyle(BigLabelStyle())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel("New email")
            .accessibilityHint("Starts an email. ECHO asks who it is for and what to say.")
        }
    }

    private var messageList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(text: "Inbox")

            if inbox.items.isEmpty {
                Text("No messages yet.")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(inbox.items) { item in
                MessageRowView(
                    item: item,
                    readAloud: { readAloud(item) },
                    reply: { conversation.submitTyped("reply to \(item.sender)") }
                )
            }
        }
    }

    // MARK: - Actions

    private func readAloud(_ item: InboxItem) {
        inbox.markRead(item)
        Task { await speechOutput.say(item.spokenText, priority: .urgent) }
    }
}

/// One inbox row. A single accessibility element with Read aloud and Reply actions.
private struct MessageRowView: View {
    let item: InboxItem
    let readAloud: () -> Void
    let reply: () -> Void

    var body: some View {
        Button(action: readAloud) {
            HStack(alignment: .top, spacing: 14) {
                IconTile(systemName: symbolName, color: item.kind == .email ? Color(.systemBlue) : Color(.systemGreen), size: 36)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if !item.isRead {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                        }
                        Text(item.isRead ? item.title : "Unread: \(item.title)")
                            .font(item.isRead ? .headline.weight(.regular) : .headline)
                            .foregroundStyle(Theme.text)
                    }
                    if !item.subject.isEmpty {
                        Text(item.subject)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.text)
                    }
                    Text(item.body)
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to read aloud. Use the actions to reply.")
        .accessibilityAction(named: "Read aloud", readAloud)
        .accessibilityAction(named: "Reply", reply)
    }

    private var symbolName: String {
        switch (item.kind, item.isRead) {
        case (.email, false): return "envelope.badge.fill"
        case (.email, true): return "envelope.open.fill"
        case (.text, false): return "message.badge.fill"
        case (.text, true): return "message.fill"
        }
    }

    private var accessibilityLabel: String {
        var label = item.isRead ? item.title : "Unread \(item.title.lowercased())"
        if !item.subject.isEmpty {
            label += ", \(item.subject)"
        }
        return "\(label): \(item.body)"
    }
}
