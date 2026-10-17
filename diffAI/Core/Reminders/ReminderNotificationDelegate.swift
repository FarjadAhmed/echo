import Foundation
import UserNotifications

/// Receives reminder notifications while ECHO is open (so they can be spoken) and when the user taps one.
/// Install with `UNUserNotificationCenter.current().delegate = delegate` and keep a strong reference;
/// the notification center only holds it weakly.
final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let onForeground: @MainActor (String) -> Void

    init(onForeground: @escaping @MainActor (String) -> Void) {
        self.onForeground = onForeground
        super.init()
    }

    /// The app is in the foreground: speak the reminder and still show the banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let body = notification.request.content.body
        Task { @MainActor in
            self.deliver(body)
        }
        completionHandler([.banner, .sound, .list])
    }

    /// The user tapped the notification.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let body = response.notification.request.content.body
        Task { @MainActor in
            self.deliver(body)
        }
        completionHandler()
    }

    private func deliver(_ body: String) {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        onForeground("Reminder: \(text.isEmpty ? "it is time" : text)")
    }
}
