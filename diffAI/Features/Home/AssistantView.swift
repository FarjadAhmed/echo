import SwiftUI

/// The Assist screen: the conversation as bubbles, live partial text, the task-progress card,
/// and two actions. VoiceOver focus moves to the newest ECHO message only after speech has finished.
struct AssistantView: View {
    @EnvironmentObject private var conversation: ConversationEngine
    @EnvironmentObject private var settings: AppSettings

    @State private var showAll = false
    @State private var toggleCount = 0
    @AccessibilityFocusState private var focusedMessage: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Messages with words in them. Tool-result turns stay off the screen.
    private var transcript: [ChatMessage] { conversation.transcript.filter(\.isVisible) }

    /// The last two exchanges, or everything when "Show details" is on.
    private var visibleMessages: [ChatMessage] {
        showAll ? transcript : Array(transcript.suffix(2))
    }

    private var hiddenCount: Int { max(0, transcript.count - visibleMessages.count) }

    var body: some View {
        VStack(spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if hiddenCount > 0 {
                            Text("\(hiddenCount) earlier \(hiddenCount == 1 ? "message" : "messages") hidden")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .accessibilityHint("Use Show details to see them")
                        }
                        ForEach(visibleMessages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                                .accessibilityFocused($focusedMessage, equals: message.id)
                        }
                        if !conversation.partialText.isEmpty {
                            PartialBubble(text: conversation.partialText)
                        }
                        if !conversation.progressSteps.isEmpty {
                            TaskProgressCard(steps: conversation.progressSteps)
                                .id("progress")
                        }
                        if let error = conversation.errorMessage {
                            ErrorText(message: error)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: conversation.transcript.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: conversation.transcript.last?.text) { _, _ in scrollToBottom(proxy) }
                .onChange(of: conversation.progressSteps.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: showAll) { _, _ in scrollToBottom(proxy) }
                .onAppear { scrollToBottom(proxy) }
            }

            StatusLabel(state: conversation.state, font: .subheadline.weight(.semibold))

            actions
                .padding(.horizontal)
        }
        .onChange(of: conversation.state) { old, new in
            // Move focus after ECHO has finished speaking, never during.
            guard old == .speaking, new == .idle || new == .listening else { return }
            if let last = transcript.last(where: { $0.role == .assistant && !$0.text.isEmpty }) {
                focusedMessage = last.id
            }
        }
        .sensoryFeedback(.selection, trigger: toggleCount) { _, _ in settings.hapticsEnabled }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: continueByVoice) {
                Label(voiceTitle, systemImage: voiceSymbol)
                    .labelStyle(BigLabelStyle())
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityLabel(voiceTitle)
            .accessibilityHint(voiceHint)

            Button {
                toggleCount += 1
                showAll.toggle()
            } label: {
                Label(showAll ? "Hide details" : "Show details", systemImage: showAll ? "chevron.up" : "list.bullet")
                    .labelStyle(BigLabelStyle())
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel(showAll ? "Hide details" : "Show details")
            .accessibilityHint(showAll ? "Shows only the last two messages" : "Shows the whole conversation")
            .accessibilityAddTraits(showAll ? .isSelected : [])
        }
    }

    private var voiceTitle: String {
        switch conversation.state {
        case .idle: return "Continue by voice"
        case .listening: return "Stop listening"
        case .thinking, .speaking: return "Interrupt and talk"
        }
    }

    private var voiceSymbol: String {
        switch conversation.state {
        case .idle: return "mic.fill"
        case .listening: return "stop.fill"
        case .thinking, .speaking: return "hand.raised.fill"
        }
    }

    private var voiceHint: String {
        switch conversation.state {
        case .idle: return "Begins listening. Say stop at any time."
        case .listening: return "Stops listening"
        case .thinking, .speaking: return "Stops ECHO and listens to you"
        }
    }

    private func continueByVoice() {
        switch conversation.state {
        case .idle: conversation.beginListening()
        case .listening: conversation.stopEverything(announce: "Stopped listening.")
        case .thinking, .speaking: conversation.interrupt()
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo("bottom", anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}
