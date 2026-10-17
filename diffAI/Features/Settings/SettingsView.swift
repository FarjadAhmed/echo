import AVFoundation
import SwiftUI

/// Native grouped settings. Every row has a hint, and every row is at least 64 pt tall.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var speechOutput: SpeechOutputCoordinator
    @EnvironmentObject private var conversation: ConversationEngine

    /// Loaded in `.task`, because the first call to the system voice list is slow.
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var apiKey = ""
    @State private var hasKey = KeychainStore.read(account: KeychainStore.anthropicKeyAccount) != nil
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Picker("Interface", selection: $settings.interfaceMode) {
                    ForEach(InterfaceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .accessibilityHint("Voice only keeps one calm screen with a single big button")

                Toggle(isOn: $settings.simpleMode) {
                    Label { Text("Simple mode") } icon: { IconTile(systemName: "square.grid.2x2.fill", color: Color(.systemBlue), size: 30) }
                }
                .accessibilityHint("Shows only four big buttons, speaks slower and keeps answers short")
                .settingsRow()
            } header: {
                sectionHeader("Interface")
            } footer: {
                Text("Voice only mode still shows an Emergency button and a Show screen button.")
            }

            Section {
                Picker(selection: $settings.speechOutputMode) {
                    ForEach(SpeechOutputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    Label { Text("Speech output") } icon: { IconTile(systemName: "speaker.wave.2.fill", color: Color(.systemBlue), size: 30) }
                }
                .pickerStyle(.navigationLink)
                .accessibilityHint("Automatic uses VoiceOver when it is on, otherwise the app voice")
                .settingsRow()

                Picker(selection: $settings.voiceIdentifier) {
                    Text("Default").tag(nil as String?)
                    ForEach(voices, id: \.identifier) { voice in
                        Text(voice.name).tag(voice.identifier as String?)
                    }
                } label: {
                    Label { Text("App voice") } icon: { IconTile(systemName: "person.wave.2.fill", color: Color(.systemIndigo), size: 30) }
                }
                .pickerStyle(.navigationLink)
                .accessibilityHint("Chooses the voice ECHO speaks with when VoiceOver is off")
                .settingsRow()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Speaking speed")
                    Slider(value: $settings.speechRate, in: 0.35...0.65, step: 0.05) {
                        Text("Speaking speed")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise.fill").accessibilityHidden(true)
                    } maximumValueLabel: {
                        Image(systemName: "hare.fill").accessibilityHidden(true)
                    }
                    .accessibilityLabel("Speaking speed")
                    .accessibilityValue("\(Int(settings.speechRate * 100)) percent")
                    .accessibilityHint("Swipe up or down to change how fast ECHO speaks")
                }
                .settingsRow()

                Button {
                    Task { await speechOutput.say("This is how ECHO will sound.") }
                } label: {
                    Label("Test the app voice", systemImage: "speaker.wave.2.fill")
                }
                .accessibilityHint("Speaks a short sentence with the current voice and speed")
                .settingsRow()
            } header: {
                sectionHeader("Speech")
            }

            Section {
                Toggle(isOn: $settings.largeText) {
                    Label { Text("Large text") } icon: { IconTile(systemName: "textformat.size", color: Color(.systemBlue), size: 30) }
                }
                .accessibilityHint("Uses the largest text size everywhere in ECHO")
                .settingsRow()
                Toggle(isOn: $settings.highContrast) {
                    Label { Text("High contrast") } icon: { IconTile(systemName: "circle.lefthalf.filled", color: Color(.systemGray), size: 30) }
                }
                .accessibilityHint("Makes colors stronger and borders sharper")
                .settingsRow()
                Toggle(isOn: $settings.hapticsEnabled) {
                    Label { Text("Haptic feedback") } icon: { IconTile(systemName: "hand.tap.fill", color: Color(.systemPink), size: 30) }
                }
                .accessibilityHint("Vibrates when listening starts and stops, and when a task finishes")
                .settingsRow()
                Toggle(isOn: $settings.detailedAnswers) {
                    Label { Text("Detailed answers") } icon: { IconTile(systemName: "text.alignleft", color: Color(.systemOrange), size: 30) }
                }
                .accessibilityHint("Longer descriptions and explanations")
                .settingsRow()
            } header: {
                sectionHeader("Display and feedback")
            }

            Section {
                Toggle(isOn: $settings.useLiveAI) {
                    Label { Text("Use live AI") } icon: { IconTile(systemName: "sparkles", color: Color(.systemPurple), size: 30) }
                }
                .accessibilityHint("Off uses the built-in demo answers")
                .settingsRow()
                SecureField("Anthropic API key", text: $apiKey)
                    .textContentType(.none)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Anthropic API key")
                    .accessibilityHint("Paste your key. It is stored in the Keychain on this device only")
                    .settingsRow()
                Button {
                    hasKey = KeychainStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                                account: KeychainStore.anthropicKeyAccount)
                    apiKey = ""
                } label: {
                    Label("Save key", systemImage: "key.fill")
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityHint("Saves the key you pasted to the Keychain")
                .settingsRow()
                if hasKey {
                    Label {
                        Text("A key is saved on this device.")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                            .accessibilityHidden(true)
                    }
                    .settingsRow()
                    Button(role: .destructive) {
                        KeychainStore.delete(account: KeychainStore.anthropicKeyAccount)
                        hasKey = false
                    } label: {
                        Label("Remove key", systemImage: "trash")
                    }
                    .accessibilityHint("Deletes the saved key from this device")
                    .settingsRow()
                }
            } header: {
                sectionHeader("Artificial intelligence")
            }

            Section {
                NavigationLink(value: AppScreen.accessibilityTips) {
                    Label { Text("Accessibility tips") } icon: { IconTile(systemName: "accessibility", color: Color(.systemBlue), size: 30) }
                }
                .accessibilityHint("How ECHO works with VoiceOver, Voice Control and Speak Screen")
                .settingsRow()
                Button {
                    settings.hasHeardWelcome = false
                    router.goHome()
                } label: {
                    Label("Hear the welcome again", systemImage: "hand.wave.fill")
                }
                .accessibilityHint("Goes to Home and plays the welcome message")
                .settingsRow()
            } header: {
                sectionHeader("Help")
            }

            Section {
                Button {
                    conversation.submitTyped("reset demo data")
                } label: {
                    Label("Reset demo data", systemImage: "arrow.counterclockwise")
                }
                .accessibilityHint("Restores the demo messages, reminders and caregiver data")
                .settingsRow()
                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    Label("Reset preferences", systemImage: "arrow.uturn.backward")
                }
                .accessibilityHint("Returns every setting on this screen to its default")
                .settingsRow()
            } header: {
                sectionHeader("Data")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .confirmationDialog("Reset preferences?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset preferences", role: .destructive) {
                settings.resetToDefaults()
                Task { await speechOutput.say("Preferences reset.") }
            }
            Button("Keep my settings", role: .cancel) {}
        } message: {
            Text("Speech, text size, contrast and interface choices go back to their defaults.")
        }
        .task {
            if voices.isEmpty {
                voices = SpeechService.availableVoices()
            }
        }
        .onAppear {
            Task { await speechOutput.announceScreen(AppScreen.settings.announcement) }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Makes a Form row at least 60 pt tall (Apple's rows are 44): 44 pt of content plus the row insets.
/// High contrast makes the row text semibold.
private struct SettingsRowModifier: ViewModifier {
    @Environment(\.echoHighContrast) private var highContrast

    func body(content: Content) -> some View {
        content
            .font(.body.weight(highContrast ? .semibold : .regular))
            .frame(minHeight: 44)
    }
}

private extension View {
    func settingsRow() -> some View {
        modifier(SettingsRowModifier())
    }
}
