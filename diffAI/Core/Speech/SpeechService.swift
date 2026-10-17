import AVFoundation
import Foundation

/// Thin wrapper around AVSpeechSynthesizer. Features never call this directly;
/// they go through SpeechOutputCoordinator so VoiceOver and the app voice are never both used.
@MainActor
final class SpeechService: NSObject {
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    var voiceIdentifier: String?

    private struct Pending {
        let utterance: AVSpeechUtterance
        let continuation: CheckedContinuation<Void, Never>
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var pending: [UUID: Pending] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks one utterance. Returns when it finishes, is stopped, or a safety timeout passes.
    func speak(_ text: String) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.voice = resolvedVoice()
        let token = UUID()
        // Safety net: if the synthesizer never reports completion, the conversation must not stall.
        let timeout = Double(text.split(separator: " ").count) + 6

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pending[token] = Pending(utterance: utterance, continuation: continuation)
            synthesizer.speak(utterance)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish(token: token)
            }
        }
    }

    /// Stops speech immediately. Any waiting speak() calls return.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Voices that match the device language, best quality first, for the Settings picker.
    static func availableVoices() -> [AVSpeechSynthesisVoice] {
        let prefix = String(AVSpeechSynthesisVoice.currentLanguageCode().prefix(2))
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { lhs, rhs in
                lhs.quality.rawValue != rhs.quality.rawValue
                    ? lhs.quality.rawValue > rhs.quality.rawValue
                    : lhs.name < rhs.name
            }
    }

    /// The most natural voice installed for the device language: premium, then enhanced, then the default.
    /// Better voices can be downloaded in Settings > Accessibility > Spoken Content > Voices.
    static let bestVoice: AVSpeechSynthesisVoice? = {
        let code = AVSpeechSynthesisVoice.currentLanguageCode()
        let candidates = availableVoices()
        return candidates.first { $0.language == code } ?? candidates.first ?? AVSpeechSynthesisVoice(language: code)
    }()

    private func resolvedVoice() -> AVSpeechSynthesisVoice? {
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            return voice
        }
        return Self.bestVoice
    }

    private func finish(token: UUID) {
        pending.removeValue(forKey: token)?.continuation.resume()
    }

    private func finish(utteranceID: ObjectIdentifier) {
        guard let token = pending.first(where: { ObjectIdentifier($0.value.utterance) == utteranceID })?.key else {
            return
        }
        finish(token: token)
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(utteranceID: utteranceID) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(utteranceID: utteranceID) }
    }
}
