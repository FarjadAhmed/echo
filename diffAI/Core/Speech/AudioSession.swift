import AVFoundation

/// One audio session for the whole app, set up once and left alone.
/// Changing the category or options mid-conversation is what makes speech cut out, so this never does.
enum AudioSession {
    private static var isConfigured = false

    /// Plays speech loudly through the speaker (or headphones) and allows recording.
    /// Not silenced by the ring/silent switch, because blind users depend on hearing ECHO.
    static func activateConversation() throws {
        let session = AVAudioSession.sharedInstance()
        if !isConfigured {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
            isConfigured = true
        }
        try session.setActive(true)
    }

    /// True when speech plays through headphones, AirPods or another private route.
    static var hasPrivateOutputRoute: Bool {
        let privatePorts: [AVAudioSession.Port] = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio, .lineOut]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { privatePorts.contains($0.portType) }
    }
}
