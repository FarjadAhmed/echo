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

/// Continuous microphone recognition with pause detection.
/// Calls onPartial while the user speaks and onUtteranceEnd after a pause.
///
/// While ECHO itself is speaking the service is muted: it keeps the microphone open for barge-in
/// detection but never turns what it hears into a request, so the app cannot obey its own voice.
@MainActor
final class ListenService: ObservableObject {
    private(set) var isRunning = false
    private(set) var isMuted = false

    var onPartial: ((String) -> Void)?
    var onUtteranceEnd: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    /// Length of pause that ends an utterance.
    var silenceSeconds: Double = 1.0

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private let requestBox = RecognitionRequestBox()
    private var task: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var generation = 0
    private var transcript = ""
    private var consecutiveFailures = 0
    /// Results before this moment are leftovers from the app's own speech and are ignored.
    private var ignoreUntil = Date.distantPast
    private var routeObserver: NSObjectProtocol?
    private var configObserver: NSObjectProtocol?

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

        // Headphones plugged in or AirPods connected: the engine's input changes, so start over.
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restartAfterRouteChange() }
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restartAfterRouteChange() }
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
        // Echo cancellation, so the microphone hears less of the phone's own speaker. Best effort.
        if !input.isVoiceProcessingEnabled {
            try? input.setVoiceProcessingEnabled(true)
        }
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
        isMuted = false
        consecutiveFailures = 0
        ignoreUntil = Date().addingTimeInterval(0.3)
        startRecognitionTask()
    }

    /// Stops listening and releases the microphone.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        isMuted = false
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

    /// Called while ECHO speaks or thinks. Partial text still flows (for barge-in) but nothing is sent as a request.
    func mute() {
        guard isRunning, !isMuted else { return }
        isMuted = true
        silenceTask?.cancel()
        silenceTask = nil
        transcript = ""
    }

    /// Called when ECHO finishes speaking. Discards whatever the recognizer buffered meanwhile.
    func unmute() {
        guard isRunning, isMuted else { return }
        isMuted = false
        transcript = ""
        ignoreUntil = Date().addingTimeInterval(0.5)
        restartRecognitionTask()
    }

    private func restartAfterRouteChange() {
        guard isRunning else { return }
        let wasMuted = isMuted
        stop()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !self.isRunning else { return }
            try? AudioSession.activateConversation()
            self.start()
            if wasMuted { self.mute() }
        }
    }

    private func startRecognitionTask() {
        guard let recognizer, isRunning else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
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

        if failed && transcript.isEmpty {
            consecutiveFailures += 1
            if consecutiveFailures >= 4 {
                stop()
                onFailure?("I couldn't hear anything clearly. Tap the microphone to try again, or type instead.")
            } else {
                restartRecognitionTask()
            }
            return
        }

        if let text, !text.isEmpty {
            consecutiveFailures = 0
            if isMuted {
                // Only for barge-in detection; never becomes a request.
                onPartial?(text)
                return
            }
            guard Date() >= ignoreUntil else { return }
            transcript = text
            onPartial?(text)
            scheduleSilenceEnd()
        }

        if !isMuted, isFinal || failed {
            endUtterance()
        }
    }

    private func scheduleSilenceEnd() {
        silenceTask?.cancel()
        let seconds = silenceSeconds
        silenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, !self.isMuted, !self.transcript.isEmpty else { return }
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
