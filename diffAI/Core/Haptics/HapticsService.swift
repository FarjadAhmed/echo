import AudioToolbox
import UIKit

/// Haptics and short system sounds for state changes. Haptics respect the Haptic feedback setting.
@MainActor
final class HapticsService {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func listeningStarted() {
        playEarcon(1113)
        impact(.medium)
    }

    func listeningStopped() {
        playEarcon(1114)
        impact(.light)
    }

    func thinking() {
        impact(.soft)
    }

    func success() {
        notify(.success)
    }

    func error() {
        notify(.error)
    }

    private func playEarcon(_ soundID: SystemSoundID) {
        AudioServicesPlaySystemSound(soundID)
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard settings.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard settings.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
