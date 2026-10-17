import Foundation

/// Chooses the AI for each turn. Live AI needs both "Use live AI" on and a key in the Keychain.
/// Otherwise the offline demo is used, so the app always works.
@MainActor
enum AIProvider {
    static func current(settings: AppSettings) -> any AIService {
        #if DEBUG
        // Automated live self-test only: a token passed in by the test runner.
        if let token = ProcessInfo.processInfo.environment["ECHO_TEST_TOKEN"], !token.isEmpty {
            return RemoteAIService(bearerToken: token)
        }
        #endif
        guard settings.useLiveAI,
              let key = KeychainStore.read(account: KeychainStore.anthropicKeyAccount),
              !key.isEmpty else {
            return MockAIService()
        }
        return RemoteAIService(apiKey: key)
    }
}
