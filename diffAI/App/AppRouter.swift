import Combine
import Foundation

/// Every destination the app can open. Add a case here and a branch in RootView.
enum AppScreen: Hashable {
    case camera
    case web
    case tools
    case history
    case messages
    case reminders
    case briefing
    case safety
    case caregiver
    case settings
    case accessibilityTips

    var title: String {
        switch self {
        case .camera: return "Camera"
        case .web: return "Web"
        case .tools: return "Tools"
        case .history: return "History"
        case .messages: return "Messages"
        case .reminders: return "Reminders"
        case .briefing: return "My Day"
        case .safety: return "Safety"
        case .caregiver: return "Caregiver"
        case .settings: return "Settings"
        case .accessibilityTips: return "Accessibility tips"
        }
    }

    /// Spoken when the screen opens.
    var announcement: String {
        switch self {
        case .camera:
            return "Camera. Say take photo, or tap the big button."
        case .web:
            return "Web. Say open news, pharmacy, appointment or bank, or type an address."
        case .tools:
            return "Tools. Read text, identify colors, describe a scene, or look at your history."
        case .history:
            return "History. Your last descriptions and readings are listed here."
        case .messages:
            return "Messages. Say read my messages to hear them one by one, or send a text or email."
        case .reminders:
            return "Reminders. Say remind me, then what and when."
        case .briefing:
            return "My Day. Say play my briefing to hear the weather, your reminders and your messages."
        case .safety:
            return "Safety. The big red button calls your emergency contact after you confirm."
        case .caregiver:
            return "Caregiver dashboard. This shows demo activity, medication and location for a caregiver."
        case .settings:
            return "Settings. Change speech, text size, contrast and other options here."
        case .accessibilityTips:
            return "Accessibility tips. How ECHO works with VoiceOver, Voice Control, Siri and Speak Screen."
        }
    }
}

/// The bottom tabs in screen-and-voice mode.
enum AppTab: Hashable {
    case home
    case history
    case settings
}

/// Owns the navigation stack so both taps and voice commands can open screens.
/// Voice navigation always pushes on the Home tab's stack, so "go back" means the same thing everywhere.
@MainActor
final class AppRouter: ObservableObject {
    @Published var path: [AppScreen] = []
    @Published var selectedTab: AppTab = .home

    var currentScreenName: String {
        path.last?.title ?? "Home"
    }

    func open(_ screen: AppScreen) {
        selectedTab = .home
        guard path.last != screen else { return }
        path.append(screen)
    }

    func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func goHome() {
        selectedTab = .home
        path.removeAll()
    }
}
