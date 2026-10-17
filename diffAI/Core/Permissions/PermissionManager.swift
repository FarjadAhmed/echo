import AVFoundation
import Combine
import Speech

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

/// Checks and requests permissions. Each request is made only after the user has heard an explanation.
@MainActor
final class PermissionManager: ObservableObject {
    var microphoneStatus: PermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    var speechStatus: PermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }

    var voicePermissionsGranted: Bool {
        microphoneStatus == .granted && speechStatus == .granted
    }

    /// Shows the system prompts for anything not yet decided. Returns true when both are allowed.
    func ensureVoicePermissions() async -> Bool {
        if microphoneStatus == .notDetermined {
            _ = await requestMicrophone()
        }
        guard microphoneStatus == .granted else { return false }
        if speechStatus == .notDetermined {
            _ = await requestSpeech()
        }
        return speechStatus == .granted
    }

    func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func requestSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
