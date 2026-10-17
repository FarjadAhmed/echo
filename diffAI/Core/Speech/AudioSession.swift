import AVFoundation

/// Audio session setup for speaking and listening at the same time.
enum AudioSession {
    /// Plays speech and records the microphone. Safe to call repeatedly.
    static func activateConversation() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .duckOthers, .allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try session.setActive(true)
    }

    /// True when speech plays through headphones, AirPods or another private route.
    /// Only then can the microphone hear the user over the app's own voice without echo.
    static var hasPrivateOutputRoute: Bool {
        let privatePorts: [AVAudioSession.Port] = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio, .lineOut]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { privatePorts.contains($0.portType) }
    }
}
