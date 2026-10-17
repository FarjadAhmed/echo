import Foundation
import LocalAuthentication

/// Face ID, Touch ID, or the device passcode, used before payments and sign-ins.
/// iOS has no speaker-voice verification API, so voice is never used as a factor.
enum BiometricGate {
    enum Outcome {
        case passed
        case failed
        /// No Face ID, Touch ID, or passcode is set up on this device.
        case unavailable
    }

    static func verify(reason: String) async -> Outcome {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return ok ? .passed : .failed
        } catch {
            return .failed
        }
    }
}
