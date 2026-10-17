import SwiftUI

/// Chooses between onboarding, the voice-only screen and the tabbed interface, and hosts the pieces
/// that must exist in every mode: the shake detector, magic tap, and the approval sheet.
/// RootView never speaks.
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var conversation: ConversationEngine
    @EnvironmentObject private var compose: ComposeCoordinator
    @Environment(\.colorSchemeContrast) private var systemContrast

    /// The app's High contrast switch or the system Increase Contrast setting.
    private var highContrast: Bool { settings.highContrast || systemContrast == .increased }

    var body: some View {
        Group {
            if !settings.hasCompletedOnboarding {
                OnboardingView()
            } else if settings.interfaceMode == .voiceOnly {
                VoiceOnlyView()
            } else {
                tabs
            }
        }
        .modifier(LargeTextModifier(enabled: settings.largeText))
        .environment(\.echoHighContrast, highContrast)
        .preferredColorScheme(nil)
        .background(ShakeDetector { conversation.shakeDetected() })
        // The app's High contrast switch turns on the system's high-contrast color variants for the window.
        .background(ContrastOverride(enabled: settings.highContrast))
        .accessibilityAction(.magicTap) { conversation.toggleListening() }
        // System Messages / Mail sheets, in screen and voice-only mode alike.
        .composeSheets(compose) { spoken in conversation.announce(spoken) }
        .sheet(item: approvalBinding) { request in
            ApprovalView(request: request)
                .interactiveDismissDisabled()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .modifier(LargeTextModifier(enabled: settings.largeText))
                .environment(\.echoHighContrast, highContrast)
        }
    }

    /// The approval screen is driven by the engine. Dismissing it any other way counts as cancel.
    private var approvalBinding: Binding<ApprovalRequest?> {
        Binding(
            get: { conversation.pendingApproval },
            set: { if $0 == nil { conversation.cancelApproval() } }
        )
    }

    private var tabs: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.path) {
                HomeView()
                    .navigationDestination(for: AppScreen.self) { screen in
                        destination(for: screen)
                    }
            }
            .modifier(TabChrome())
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(AppTab.home)
            .accessibilityHint("The conversation and quick actions")

            NavigationStack {
                HistoryView()
                    .navigationDestination(for: AppScreen.self) { screen in
                        destination(for: screen)
                    }
            }
            .modifier(TabChrome())
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            .tag(AppTab.history)
            .accessibilityHint("Your recent descriptions and readings")

            NavigationStack {
                SettingsView()
                    .navigationDestination(for: AppScreen.self) { screen in
                        destination(for: screen)
                    }
            }
            .modifier(TabChrome())
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(AppTab.settings)
            .accessibilityHint("Speech, text size, contrast and other options")
        }
    }

    @ViewBuilder
    private func destination(for screen: AppScreen) -> some View {
        switch screen {
        case .camera:
            CameraView()
        case .web:
            WebAssistantView()
        case .tools:
            ToolsView()
        case .history:
            HistoryView()
        case .messages:
            MessagesView()
        case .reminders:
            RemindersView()
        case .briefing:
            BriefingView()
        case .safety:
            SafetyView()
        case .caregiver:
            CaregiverView()
        case .settings:
            SettingsView()
        case .accessibilityTips:
            AccessibilityTipsView()
        }
    }
}

/// The persistent microphone bar above the tab bar, plus the tab bar's solid surface.
private struct TabChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MicBar()
            }
            .toolbarBackground(.visible, for: .tabBar)
    }
}

/// Bottom bar with the microphone on every main screen. Shows Stop while the assistant is busy.
struct MicBar: View {
    @EnvironmentObject private var conversation: ConversationEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isBusy: Bool { conversation.state == .thinking || conversation.state == .speaking }

    var body: some View {
        HStack(spacing: 20) {
            if isBusy {
                StopButton { conversation.interrupt() }
                    .transition(reduceMotion ? .identity : .move(edge: .leading).combined(with: .opacity))
            }
            MicButton(state: conversation.state) {
                conversation.toggleListening()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(BarBackground().ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isBusy)
    }
}
