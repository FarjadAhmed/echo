import SwiftUI

/// Home in screen-and-voice mode. Before the first exchange it is the welcome screen from the mockup:
/// avatar, "Start talking", a typed field and quick actions. Once there is a conversation, the chat
/// takes over the top and the typed field and navigation chips stay reachable below.
/// Simple mode shows only four big buttons.
struct HomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var conversation: ConversationEngine
    @EnvironmentObject private var speechOutput: SpeechOutputCoordinator

    @State private var typed = ""
    @State private var tapCount = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if settings.simpleMode {
                simpleHome
            } else if !conversation.transcript.contains(where: \.isVisible) {
                welcomeHome
            } else {
                conversationHome
            }
        }
        .echoBackground()
        .navigationTitle("ECHO")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.open(.settings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Settings")
                .accessibilityHint("Speech, text size, contrast and other options")
            }
        }
        // Press and hold anywhere to talk. An extra: every action is also a button.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.8).onEnded { _ in
                conversation.beginListening()
            }
        )
        .sensoryFeedback(.selection, trigger: tapCount) { _, _ in settings.hapticsEnabled }
        .onAppear(perform: welcomeOrAnnounce)
    }

    // MARK: - Welcome (empty transcript)

    private var welcomeHome: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    EchoAvatar(state: conversation.state, size: 120)

                    Text("What do you need help with?")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    StatusLabel(state: conversation.state, font: .subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    startTalkingButton
                    TypedRequestField(text: $typed, onSend: send)
                    if let error = conversation.errorMessage {
                        ErrorText(message: error)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(text: "Try one of these")
                    quickActions
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(text: "More")
                    moreList
                }

                SOSButton(style: .row)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Conversation (transcript present)

    private var conversationHome: some View {
        VStack(spacing: 12) {
            AssistantView()
                .frame(maxHeight: .infinity)

            VStack(spacing: 10) {
                TypedRequestField(text: $typed, onSend: send)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chipButtons
                    }
                    .padding(.horizontal, 2)
                }
                .accessibilityLabel("Quick navigation")
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Simple mode

    private var simpleHome: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    EchoAvatar(state: conversation.state, size: 120)
                    StatusLabel(state: conversation.state, font: .title2.weight(.semibold))
                }
                .padding(.bottom, 8)

                startTalkingButton
                Button {
                    router.open(.camera)
                } label: {
                    Label("Camera", systemImage: "camera.fill")
                        .labelStyle(BigLabelStyle())
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Camera")
                .accessibilityHint("Take a photo and hear what is in it")

                Button {
                    conversation.submitTyped("call")
                } label: {
                    Label("Call someone", systemImage: "phone.fill")
                        .labelStyle(BigLabelStyle())
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Call someone")
                .accessibilityHint("ECHO asks who to call, then confirms with you")

                SOSButton()
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical)
        }
        .dynamicTypeSize(DynamicTypeSize.xxLarge...)
    }

    // MARK: - Pieces

    private var startTalkingButton: some View {
        Button {
            tapCount += 1
            conversation.beginListening()
        } label: {
            Label("Start talking", systemImage: "mic.fill")
                .labelStyle(BigLabelStyle())
                .frame(minHeight: 48)
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityLabel("Start talking")
        .accessibilityHint("Begins listening. Say stop at any time.")
    }

    @ViewBuilder
    private var quickActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                readLabelCard
                websiteCard
                aroundMeCard
                callCard
            }
        } else {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    readLabelCard
                    websiteCard
                }
                GridRow {
                    aroundMeCard
                    callCard
                }
            }
        }
    }

    private var readLabelCard: some View {
        QuickActionCard(title: "Read this label", systemImage: "doc.text.viewfinder", hint: "Opens the camera and reads the text aloud", color: Color(.systemOrange)) {
            tapCount += 1
            conversation.submitTyped("read this")
        }
    }

    private var websiteCard: some View {
        QuickActionCard(title: "Help with a website", systemImage: "globe", hint: "Opens the web assistant", color: Color(.systemBlue)) {
            tapCount += 1
            router.open(.web)
        }
    }

    private var aroundMeCard: some View {
        QuickActionCard(title: "What's around me", systemImage: "camera.viewfinder", hint: "Takes a photo and describes what is in front of you", color: Color(.systemIndigo)) {
            tapCount += 1
            conversation.submitTyped("what is in front of me")
        }
    }

    private var callCard: some View {
        QuickActionCard(title: "Call someone", systemImage: "phone.fill", hint: "ECHO asks who to call, then confirms with you", color: Color(.systemGreen)) {
            tapCount += 1
            conversation.submitTyped("call")
        }
    }

    /// Every other screen, as a Settings-style list with colored icon tiles.
    private var moreList: some View {
        RowGroup {
            FeatureRow(title: "Camera", systemImage: "camera.fill", color: Color(.systemGray), hint: "Take a photo and ask what is in it") { router.open(.camera) }
            RowDivider()
            FeatureRow(title: "Web", systemImage: "globe", color: Color(.systemBlue), hint: "Open websites and hear what you can do on them") { router.open(.web) }
            RowDivider()
            FeatureRow(title: "Messages", systemImage: "message.fill", color: Color(.systemGreen), hint: "Hear and send texts and emails") { router.open(.messages) }
            RowDivider()
            FeatureRow(title: "Reminders", systemImage: "bell.fill", color: Color(.systemOrange), hint: "Set and hear reminders") { router.open(.reminders) }
            RowDivider()
            FeatureRow(title: "My Day", systemImage: "sun.max.fill", color: Color(.systemTeal), hint: "Weather, reminders and messages in one briefing") { router.open(.briefing) }
            RowDivider()
            FeatureRow(title: "Safety", systemImage: "shield.lefthalf.filled", color: Color(.systemRed), hint: "Emergency call, your location and emergency services") { router.open(.safety) }
            RowDivider()
            FeatureRow(title: "Tools", systemImage: "wrench.and.screwdriver.fill", color: Color(.systemPurple), hint: "Read text, identify colors, scan documents") { router.open(.tools) }
            RowDivider()
            FeatureRow(title: "Caregiver", systemImage: "person.2.fill", color: Color(.systemPink), hint: "Demo dashboard for a caregiver") { router.open(.caregiver) }
        }
    }

    @ViewBuilder
    private var chipButtons: some View {
        NavChip(title: "Camera", systemImage: "camera", hint: "Take a photo and ask what is in it") { router.open(.camera) }
        NavChip(title: "Web", systemImage: "globe", hint: "Open websites and hear what you can do on them") { router.open(.web) }
        NavChip(title: "Messages", systemImage: "message", hint: "Hear and send texts and emails") { router.open(.messages) }
        NavChip(title: "Reminders", systemImage: "bell", hint: "Set and hear reminders") { router.open(.reminders) }
        NavChip(title: "My Day", systemImage: "sun.max", hint: "Weather, reminders and messages in one briefing") { router.open(.briefing) }
        NavChip(title: "Safety", systemImage: "sos", hint: "Emergency call, your location and emergency services") { router.open(.safety) }
        NavChip(title: "Tools", systemImage: "wrench.and.screwdriver", hint: "Read text, identify colors, scan documents") { router.open(.tools) }
        NavChip(title: "Caregiver", systemImage: "person.2", hint: "Demo dashboard for a caregiver") { router.open(.caregiver) }
    }

    private func send() {
        let text = typed
        typed = ""
        conversation.submitTyped(text)
    }

    private func welcomeOrAnnounce() {
        if settings.hasHeardWelcome {
            Task { await speechOutput.announceScreen("Home. Say help to hear what I can do.") }
        } else {
            settings.hasHeardWelcome = true
            Task {
                await speechOutput.say("Welcome to ECHO. Tap Start talking, or the microphone at the bottom, and ask me anything. Say help to hear what I can do.")
            }
        }
    }
}
