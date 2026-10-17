import AVFoundation
import Combine
import Speech

/// Passes microphone buffers from the audio thread to the active recognition request.
final class RecognitionRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ newRequest: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        defer { lock.unlock() }
        request = newRequest
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = request
        lock.unlock()
        current?.append(buffer)
    }
}

/// Microphone recognition with pause detection. Calls onPartial while the user speaks and
/// onUtteranceEnd after a pause.
///
/// The conversation engine runs this only while it is listening: it is stopped completely while
/// ECHO thinks or speaks, so the microphone can never hear ECHO's own voice.
@MainActor
final class ListenService: ObservableObject {
    private(set) var isRunning = false

    var onPartial: ((String) -> Void)?
    var onUtteranceEnd: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    /// Length of pause that ends an utterance. Generous, because people pause mid-sentence.
    var silenceSeconds: Double = 1.3

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private let requestBox = RecognitionRequestBox()
    private var task: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var generation = 0
    private var transcript = ""
    private var routeObserver: NSObjectProtocol?

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

        // Only a real device change (headphones in or out, AirPods connecting) needs a restart.
        // Category and option changes also post this notification, and restarting on those causes a loop.
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
            guard reason == .newDeviceAvailable || reason == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.restartForNewRoute() }
        }
    }

    /// Starts listening. Reports problems through onFailure instead of throwing.
    func start() {
        guard !isRunning else { return }
        guard let recognizer, recognizer.isAvailable else {
            onFailure?("Speech recognition is not available right now. You can type instead.")
            return
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioApplication.shared.recordPermission == .granted else {
            onFailure?("I need permission to use the microphone and speech recognition. You can turn these on in Settings, or type instead.")
            return
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            onFailure?("The microphone is not available right now. You can type instead.")
            return
        }

        let box = requestBox
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            box.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            onFailure?("I couldn't start listening. You can type instead.")
            return
        }

        isRunning = true
        transcript = ""
        startRecognitionTask()
    }

    /// Stops listening and releases the microphone.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        silenceTask?.cancel()
        silenceTask = nil
        generation += 1
        task?.cancel()
        task = nil
        requestBox.set(nil)
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        transcript = ""
    }

    private func restartForNewRoute() {
        guard isRunning else { return }
        stop()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.start()
        }
    }

    private func startRecognitionTask() {
        guard let recognizer, isRunning else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }
        requestBox.set(request)
        let current = generation
        task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                self?.handle(text: text, isFinal: isFinal, failed: failed, generation: current)
            }
        }
    }

    private func restartRecognitionTask() {
        task?.cancel()
        task = nil
        generation += 1
        startRecognitionTask()
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool, generation current: Int) {
        guard isRunning, current == generation else { return }

        if let text, !text.isEmpty {
            transcript = text
            onPartial?(text)
            scheduleSilenceEnd()
        }

        if isFinal || failed {
            if transcript.isEmpty {
                // "No speech detected" and request time limits are normal while waiting; just keep listening.
                restartRecognitionTask()
            } else {
                endUtterance()
            }
        }
    }

    private func scheduleSilenceEnd() {
        silenceTask?.cancel()
        let seconds = silenceSeconds
        silenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, !self.transcript.isEmpty else { return }
            self.endUtterance()
        }
    }

    private func endUtterance() {
        silenceTask?.cancel()
        silenceTask = nil
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = ""
        restartRecognitionTask()
        if !text.isEmpty {
            onUtteranceEnd?(text)
        }
    }
}
