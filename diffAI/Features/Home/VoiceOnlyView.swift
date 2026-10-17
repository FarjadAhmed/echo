import SwiftUI

/// Voice-only mode: one calm screen. The avatar is the microphone button, the status is large,
/// the last thing ECHO said is shown in big text, and two buttons remain: Emergency and Show screen.
struct VoiceOnlyView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var conversation: ConversationEngine
    @EnvironmentObject private var speechOutput: SpeechOutputCoordinator

    private var lastEchoSentence: String? {
        conversation.transcript.last(where: { $0.isVisible && $0.role == .assistant && !$0.text.isEmpty })?.text
    }

    var body: some View {
        VStack(spacing: Theme.spacing) {
            StatusLabel(state: conversation.state, font: .largeTitle.weight(.bold))
                .padding(.top, 24)

            Spacer(minLength: 0)

            Button {
                conversation.toggleListening()
            } label: {
                EchoAvatar(state: conversation.state, size: 220)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ECHO")
            .accessibilityValue(conversation.state.label)
            .accessibilityHint("Double tap to start or stop listening")
            .accessibilityAddTraits(conversation.state == .listening ? .isSelected : [])

            VStack(spacing: 12) {
                if let sentence = lastEchoSentence {
                    Text(sentence)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(6)
                        .accessibilityLabel("ECHO said: \(sentence)")
                } else {
                    Text("Tap ECHO and ask me anything.")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !conversation.partialText.isEmpty {
                    Text(conversation.partialText)
                        .font(.title3.italic())
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                        .accessibilityHidden(true)
                }
                if let error = conversation.errorMessage {
                    ErrorText(message: error)
                }
            }
            .padding(.horizontal)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                SOSButton()
                Button {
                    settings.interfaceMode = .full
                } label: {
                    Label("Show screen", systemImage: "rectangle.on.rectangle")
                        .labelStyle(BigLabelStyle())
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Show screen")
                .accessibilityHint("Switches to screen and voice mode")
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .echoBackground()
        .statusBarHidden(false)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.8).onEnded { _ in
                conversation.beginListening()
            }
        )
        .accessibilityAction(.magicTap) { conversation.toggleListening() }
        // Shake-to-stop comes from RootView's ShakeDetector, which wraps this screen too.
        .onAppear {
            Task { await speechOutput.announceScreen("Voice only. Tap the middle of the screen, or say help to hear what I can do.") }
        }
    }
}
