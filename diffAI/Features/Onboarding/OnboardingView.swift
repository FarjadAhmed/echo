import SwiftUI

/// Short spoken introduction. Permissions are requested one at a time, after an explanation,
/// and the user picks how they want to use ECHO before the first screen appears.
struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var speechOutput: SpeechOutputCoordinator
    @EnvironmentObject private var permissions: PermissionManager

    @State private var step = 0
    @State private var permissionMessage: String?
    @State private var selectionCount = 0
    @AccessibilityFocusState private var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Step {
        let symbol: String
        let title: String
        let body: String
    }

    private let steps: [Step] = [
        Step(
            symbol: "waveform.circle.fill",
            title: "Welcome to ECHO",
            body: "ECHO is a voice assistant. You talk, it listens, and it answers out loud. Everything also works with VoiceOver, Voice Control and Switch Control."
        ),
        Step(
            symbol: "mic.circle.fill",
            title: "Microphone and speech",
            body: "To hear you, ECHO needs the microphone and speech recognition. Tap the button below to allow them. You can still type if you say no."
        ),
        Step(
            symbol: "person.crop.circle.badge.checkmark",
            title: "How do you want to use ECHO?",
            body: "Screen and voice shows buttons and the conversation. Voice only keeps one calm screen with a single big button. You can change this any time in Settings."
        ),
        Step(
            symbol: "hand.tap.fill",
            title: "How to talk",
            body: "Tap Start talking or the microphone, or press and hold the screen. Say help to hear the commands. Say stop at any time, or shake the phone to stop speaking."
        ),
        Step(
            symbol: "checkmark.shield.fill",
            title: "You stay in control",
            body: "ECHO never sends, pays, or calls without asking. Before anything that matters, it reads the details and waits for your yes. Finish to start using ECHO."
        ),
    ]

    private var current: Step { steps[step] }
    private var isLast: Bool { step == steps.count - 1 }
    private var isModeStep: Bool { step == 2 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    ProgressView(value: Double(step + 1), total: Double(steps.count))
                        .accessibilityLabel("Step \(step + 1) of \(steps.count)")

                    VStack(spacing: 16) {
                        HeroSymbol(systemName: current.symbol)
                            .padding(.top, 24)

                        Text(current.title)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($titleFocused)

                        Text(current.body)
                            .font(.title3)
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)

                    if isModeStep {
                        modeCards
                    }

                    if let permissionMessage, step == 1 {
                        Text(permissionMessage)
                            .font(.title3)
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .card()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical)
            }
            .scrollBounceBehavior(.basedOnSize)
            .echoBackground()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if step == 1 {
                        Button {
                            requestPermissions()
                        } label: {
                            Label("Allow microphone and speech", systemImage: "mic")
                                .labelStyle(BigLabelStyle())
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityLabel("Allow microphone and speech")
                        .accessibilityHint("Shows the system permission prompts")
                    }

                    Button(action: next) {
                        Label(isLast ? "Finish" : "Next", systemImage: isLast ? "checkmark" : "arrow.right")
                            .labelStyle(BigLabelStyle())
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityLabel(isLast ? "Finish" : "Next")
                    .accessibilityHint(isLast ? "Starts ECHO" : "Goes to the next step")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(BarBackground().ignoresSafeArea(edges: .bottom))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip", action: finish)
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Skip")
                        .accessibilityHint("Skips the introduction and starts ECHO")
                }
            }
            .onAppear(perform: speakCurrent)
            .onChange(of: step) { _, _ in
                speakCurrent()
                titleFocused = true
            }
            .sensoryFeedback(.selection, trigger: selectionCount) { _, _ in settings.hapticsEnabled }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
        }
    }

    private var modeCards: some View {
        VStack(spacing: 12) {
            modeCard(.full, symbol: "iphone", detail: "Buttons, the conversation and the microphone on screen.")
            modeCard(.voiceOnly, symbol: "waveform", detail: "One big button and large status text. Everything is spoken.")
        }
        .padding(.top, 4)
    }

    private func modeCard(_ mode: InterfaceMode, symbol: String, detail: String) -> some View {
        let selected = settings.interfaceMode == mode
        return Button {
            selectionCount += 1
            settings.interfaceMode = mode
        } label: {
            HStack(alignment: .center, spacing: 14) {
                IconTile(systemName: symbol, color: mode == .full ? Color(.systemBlue) : Color(.systemIndigo), size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.title)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(selected ? Theme.accent : Color(.systemGray3))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(CardButtonStyle(isSelected: selected))
        .accessibilityLabel(mode.title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func speakCurrent() {
        let text = "\(current.title). \(current.body)"
        Task { await speechOutput.say(text) }
    }

    private func next() {
        if isLast {
            finish()
        } else {
            step += 1
        }
    }

    private func finish() {
        // Onboarding already welcomed the user; Home should not speak a second welcome on top.
        settings.hasHeardWelcome = true
        settings.hasCompletedOnboarding = true
    }

    private func requestPermissions() {
        Task {
            let microphoneOK = await permissions.requestMicrophone()
            var speechOK = false
            if microphoneOK {
                speechOK = await permissions.requestSpeech()
            }
            let message = (microphoneOK && speechOK)
                ? "Thank you. Microphone and speech are allowed."
                : "No problem. You can type instead, and turn these on later in Settings."
            permissionMessage = message
            await speechOutput.say(message)
        }
    }
}
