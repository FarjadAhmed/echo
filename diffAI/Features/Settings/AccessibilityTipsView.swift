import SwiftUI

struct AccessibilityTipsView: View {
    @EnvironmentObject private var speechOutput: SpeechOutputCoordinator

    private struct Tip: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let body: String
    }

    private let tips: [Tip] = [
        Tip(
            id: "voiceover",
            symbol: "speaker.wave.3.fill",
            title: "VoiceOver",
            body: "Swipe right and left to move between items, and double tap to press a button. When VoiceOver is on, ECHO sends its speech to VoiceOver, so you hear your own voice and speed. Two-finger double tap starts or stops listening. On the approval screen, two-finger double tap confirms and the two-finger scrub cancels."
        ),
        Tip(
            id: "voiceonly",
            symbol: "waveform",
            title: "Voice only mode",
            body: "In Settings, choose Voice only to keep one calm screen. The big ECHO face is the microphone: double tap it, press and hold anywhere, or use the two-finger double tap. Say show screen, or tap the Show screen button, to come back to the full interface."
        ),
        Tip(
            id: "voicecontrol",
            symbol: "mic.badge.plus",
            title: "Voice Control",
            body: "Say Tap Start talking, Tap Microphone, Tap Settings, or any button name on the screen. Every button has a short, speakable name."
        ),
        Tip(
            id: "switch",
            symbol: "keyboard",
            title: "Switch Control and keyboards",
            body: "Every action is a button, toggle or text field, so it works with Switch Control and Full Keyboard Access. Press and hold to talk is an extra, never the only way."
        ),
        Tip(
            id: "siri",
            symbol: "sparkles",
            title: "Siri",
            body: "Siri shortcuts for Start talking, Read this and Emergency are coming in a later update. You can already talk to ECHO hands-free with the microphone."
        ),
        Tip(
            id: "speakscreen",
            symbol: "text.bubble.fill",
            title: "Speak Screen",
            body: "Speak Screen reads the whole screen when you swipe down from the top with two fingers. It works on every ECHO screen."
        ),
        Tip(
            id: "tips",
            symbol: "lightbulb.fill",
            title: "Tips",
            body: "Use headphones for the best hands-free experience. Say stop at any time, or shake the phone to stop speaking. Before anything that matters, ECHO reads the details and waits for your yes."
        ),
    ]

    var body: some View {
        List {
            ForEach(tips) { tip in
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        IconTile(systemName: tip.symbol, color: Color(.systemBlue), size: 30)
                        Text(tip.body)
                            .font(.body)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text(tip.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .textCase(nil)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Accessibility tips")
        .onAppear {
            Task { await speechOutput.announceScreen(AppScreen.accessibilityTips.announcement) }
        }
    }
}
