import Combine
import Foundation
import UIKit

enum SpeechPriority {
    case normal
    /// Stops whatever is being spoken before this text starts.
    case urgent
}

/// The only place that speaks. Uses VoiceOver announcements when VoiceOver is on
/// (per the Speech output setting), otherwise the app voice. Never both for the same text.
@MainActor
final class SpeechOutputCoordinator: ObservableObject {
    @Published private(set) var voiceOverRunning = UIAccessibility.isVoiceOverRunning

    private let settings: AppSettings
    private let speech: SpeechService
    private var statusObserver: NSObjectProtocol?
    private var finishObserver: NSObjectProtocol?
    /// Waiting for VoiceOver to finish the announcement with this text.
    private var announcementWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    init(settings: AppSettings, speech: SpeechService) {
        self.settings = settings
        self.speech = speech
        statusObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.voiceOverRunning = UIAccessibility.isVoiceOverRunning
            }
        }
        finishObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.announcementDidFinishNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let text = (notification.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String)
                ?? (notification.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? NSAttributedString)?.string
            Task { @MainActor in
                self.announcementFinished(text)
            }
        }
    }

    /// True when text should go to VoiceOver instead of the app voice.
    /// "Always use VoiceOver" still falls back to the app voice when VoiceOver is off, so the app is never silent.
    var usesVoiceOver: Bool {
        switch settings.speechOutputMode {
        case .automatic, .voiceOver: return voiceOverRunning
        case .appVoice: return false
        }
    }

    /// Speaks text once. Returns when the speech is finished.
    func say(_ text: String, priority: SpeechPriority = .normal, rateScale: Float = 1) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        #if DEBUG
        if LiveSelfTest.isRunning {
            print("ECHOTEST SAY: \(clean)")
            return
        }
        #endif

        if priority == .urgent { stop() }

        if usesVoiceOver {
            await announce(clean)
        } else {
            speech.rate = settings.effectiveSpeechRate * rateScale
            speech.voiceIdentifier = settings.voiceIdentifier
            await speech.speak(clean)
        }
    }

    /// Announces a newly opened screen. Under VoiceOver this is a screen-changed notification,
    /// which also resets VoiceOver focus to the top of the new screen.
    func announceScreen(_ text: String) async {
        #if DEBUG
        if LiveSelfTest.isRunning {
            print("ECHOTEST SCREEN: \(text)")
            return
        }
        #endif
        if usesVoiceOver {
            UIAccessibility.post(notification: .screenChanged, argument: text)
        } else {
            await say(text)
        }
    }

    /// Stops app-voice speech. VoiceOver speech cannot be stopped by the app.
    func stop() {
        speech.stop()
    }

    /// Queues the text behind any announcement in progress and waits for VoiceOver to finish it.
    private func announce(_ text: String) async {
        let attributed = NSAttributedString(
            string: text,
            attributes: [.accessibilitySpeechQueueAnnouncement: true]
        )
        // VoiceOver reports completion by notification. If it never does (for example VoiceOver turned off
        // mid-sentence), a generous timeout keeps the conversation moving.
        let words = Double(text.split(separator: " ").count)
        let timeout = max(2.0, words / 1.5 + 2)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            announcementWaiters[text, default: []].append(continuation)
            UIAccessibility.post(notification: .announcement, argument: attributed)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.announcementFinished(text)
            }
        }
    }

    private func announcementFinished(_ text: String?) {
        guard let text, let waiters = announcementWaiters.removeValue(forKey: text) else { return }
        waiters.forEach { $0.resume() }
    }
}
