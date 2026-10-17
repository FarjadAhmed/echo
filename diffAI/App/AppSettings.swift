import Combine
import Foundation

/// How app speech is delivered. Automatic uses VoiceOver when it is running.
enum SpeechOutputMode: String, CaseIterable, Identifiable {
    case automatic
    case voiceOver
    case appVoice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic (recommended)"
        case .voiceOver: return "Always use VoiceOver"
        case .appVoice: return "Always use app voice"
        }
    }
}

/// How much is on screen. Voice-only keeps one big status and the microphone; everything is spoken.
enum InterfaceMode: String, CaseIterable, Identifiable {
    case full
    case voiceOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "Screen and voice"
        case .voiceOnly: return "Voice only"
        }
    }
}

/// User preferences, saved in UserDefaults. Every feature reads from here.
@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let interfaceMode = "interfaceMode"
        static let speechOutputMode = "speechOutputMode"
        static let speechRate = "speechRate"
        static let voiceIdentifier = "voiceIdentifier"
        static let hapticsEnabled = "hapticsEnabled"
        static let highContrast = "highContrast"
        static let largeText = "largeText"
        static let simpleMode = "simpleMode"
        static let detailedAnswers = "detailedAnswers"
        static let useLiveAI = "useLiveAI"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let hasHeardWelcome = "hasHeardWelcome"
    }

    private let defaults: UserDefaults

    @Published var interfaceMode: InterfaceMode {
        didSet { defaults.set(interfaceMode.rawValue, forKey: Key.interfaceMode) }
    }
    @Published var speechOutputMode: SpeechOutputMode {
        didSet { defaults.set(speechOutputMode.rawValue, forKey: Key.speechOutputMode) }
    }
    /// Speech rate in AVSpeechUtterance units. 0.5 is the system default.
    @Published var speechRate: Double {
        didSet { defaults.set(speechRate, forKey: Key.speechRate) }
    }
    @Published var voiceIdentifier: String? {
        didSet { defaults.set(voiceIdentifier, forKey: Key.voiceIdentifier) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }
    @Published var highContrast: Bool {
        didSet { defaults.set(highContrast, forKey: Key.highContrast) }
    }
    @Published var largeText: Bool {
        didSet { defaults.set(largeText, forKey: Key.largeText) }
    }
    @Published var simpleMode: Bool {
        didSet { defaults.set(simpleMode, forKey: Key.simpleMode) }
    }
    @Published var detailedAnswers: Bool {
        didSet { defaults.set(detailedAnswers, forKey: Key.detailedAnswers) }
    }
    @Published var useLiveAI: Bool {
        didSet { defaults.set(useLiveAI, forKey: Key.useLiveAI) }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }
    @Published var hasHeardWelcome: Bool {
        didSet { defaults.set(hasHeardWelcome, forKey: Key.hasHeardWelcome) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        interfaceMode = InterfaceMode(rawValue: defaults.string(forKey: Key.interfaceMode) ?? "") ?? .full
        speechOutputMode = SpeechOutputMode(rawValue: defaults.string(forKey: Key.speechOutputMode) ?? "") ?? .automatic
        let storedRate = defaults.double(forKey: Key.speechRate)
        speechRate = storedRate > 0 ? storedRate : 0.5
        voiceIdentifier = defaults.string(forKey: Key.voiceIdentifier)
        hapticsEnabled = AppSettings.flag(defaults, Key.hapticsEnabled, default: true)
        highContrast = AppSettings.flag(defaults, Key.highContrast, default: false)
        largeText = AppSettings.flag(defaults, Key.largeText, default: false)
        simpleMode = AppSettings.flag(defaults, Key.simpleMode, default: false)
        detailedAnswers = AppSettings.flag(defaults, Key.detailedAnswers, default: false)
        useLiveAI = AppSettings.flag(defaults, Key.useLiveAI, default: false)
        hasCompletedOnboarding = AppSettings.flag(defaults, Key.hasCompletedOnboarding, default: false)
        hasHeardWelcome = AppSettings.flag(defaults, Key.hasHeardWelcome, default: false)
    }

    /// Speech rate actually used. Simple mode speaks a little slower.
    var effectiveSpeechRate: Float {
        Float(simpleMode ? speechRate * 0.85 : speechRate)
    }

    /// Returns every preference to its default. Onboarding and welcome flags are kept.
    func resetToDefaults() {
        interfaceMode = .full
        speechOutputMode = .automatic
        speechRate = 0.5
        voiceIdentifier = nil
        hapticsEnabled = true
        highContrast = false
        largeText = false
        simpleMode = false
        detailedAnswers = false
        useLiveAI = false
    }

    private static func flag(_ defaults: UserDefaults, _ key: String, default fallback: Bool) -> Bool {
        (defaults.object(forKey: key) as? Bool) ?? fallback
    }
}
