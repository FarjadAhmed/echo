import Foundation

/// Chooses the AI for each turn. Live AI needs "Use live AI" on and a key, either saved in Settings
/// (Keychain) or bundled in a local Secrets.plist. Otherwise the offline demo is used, so the app always works.
@MainActor
enum AIProvider {
    static func current(settings: AppSettings) -> any AIService {
        #if DEBUG
        // Automated live self-test only: a token passed in by the test runner.
        if let token = ProcessInfo.processInfo.environment["ECHO_TEST_TOKEN"], !token.isEmpty {
            return RemoteAIService(bearerToken: token)
        }
        #endif
        guard settings.useLiveAI, let key = activeKey else {
            return MockAIService()
        }
        return RemoteAIService(apiKey: key)
    }

    /// The key in use: one saved in Settings wins over the bundled one.
    static var activeKey: String? {
        if let saved = KeychainStore.read(account: KeychainStore.anthropicKeyAccount), !saved.isEmpty {
            return saved
        }
        return bundledKey
    }

    /// A key built into this copy of the app from `Resources/Secrets.plist` (key `AnthropicKey`).
    /// That file is listed in .gitignore and never committed, because the repository is public.
    static let bundledKey: String? = secret("AnthropicKey")

    /// The workspace to bill when the key is a login token that is not tied to one workspace
    /// (`AnthropicWorkspaceID` in Secrets.plist).
    static let bundledWorkspaceID: String? = secret("AnthropicWorkspaceID")

    private static func secret(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let values = NSDictionary(contentsOf: url) as? [String: Any],
              let value = values[name] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
