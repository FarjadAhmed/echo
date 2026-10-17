#if DEBUG
import Foundation
import UIKit

/// Debug-only end-to-end test of the live AI. Runs when the app is launched with the
/// `-ECHOSelfTest` argument and an `ECHO_TEST_TOKEN` environment variable. It drives the real
/// ConversationEngine with typed requests, mutes speech, and prints every step to the console:
///   xcrun simctl launch --console-pty <device> <bundle id> -ECHOSelfTest
/// Never compiled into release builds.
@MainActor
enum LiveSelfTest {
    static var isRunning: Bool {
        ProcessInfo.processInfo.arguments.contains("-ECHOSelfTest")
    }

    private enum Step {
        case say(String)
        case photo(UIImage, CapturePurpose)
        case interrupt(afterSeconds: Double)
        case pause(Double)
    }

    static func runIfRequested(_ env: AppEnvironment) async {
        guard isRunning else { return }
        env.settings.hasCompletedOnboarding = true
        env.settings.interfaceMode = .full
        env.inbox.resetDemoData()
        log("START live=\(!(AIProvider.current(settings: env.settings) is MockAIService))")
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let scenarios: [(String, [Step])] = [
            ("conversation", [.say("Hi, what can you help me with?")]),
            ("follow-up memory", [.say("Can you say that in one short sentence?")]),
            ("web search", [.say("What is the weather in Berlin today?")]),
            ("call with approval", [.say("Please call Mom."), .say("yes")]),
            ("call declined", [.say("Call Dr. Meyer for me."), .say("no")]),
            ("text with message", [.say("Text Neighbor Anna saying I will be ten minutes late."), .say("polish"), .say("yes"), .say("yes")]),
            ("text asking for details", [.say("I want to send an email."), .say("Mom"), .say("Lunch on Sunday sounds lovely."), .say("yes"), .say("yes")]),
            ("reminder", [.say("Remind me to take my pills at 8 pm every day.")]),
            ("reminder needing a time", [.say("Remind me to water the plants."), .say("tomorrow at 9 in the morning")]),
            ("inbox", [.say("Do I have any new messages?"), .say("next"), .say("stop")]),
            ("briefing", [.say("Good morning, what does my day look like?")]),
            ("where am I", [.say("Where am I right now?")]),
            ("website", [.say("Open the pharmacy website."), .pause(2), .say("What can I do on this page?"), .say("Type vitamin C into the search box.")]),
            ("photo describe", [.photo(SamplePhotos.medicineBox.image, .describe), .say("How many tablets can I take in one day?")]),
            ("photo read text", [.photo(SamplePhotos.medicineBox.image, .readText)]),
            ("emergency declined", [.say("help me"), .say("no")]),
            ("interrupt then continue", [.say("Tell me a long story about the sea."), .interrupt(afterSeconds: 3), .say("What did I just ask you for?")]),
            ("voice only switch", [.say("voice only"), .say("show the screen")]),
        ]

        var failures = 0
        for (name, steps) in scenarios {
            log("")
            log("=== \(name)")
            for step in steps {
                let before = env.conversation.transcript.count
                switch step {
                case .say(let text):
                    log("USER: \(text)")
                    env.conversation.submitTyped(text)
                    await waitUntilSettled(env)
                case .photo(let image, let purpose):
                    log("PHOTO: \(purpose.prompt)")
                    env.conversation.analyze(image, purpose: purpose)
                    await waitUntilSettled(env)
                case .interrupt(let seconds):
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    log("INTERRUPT")
                    env.conversation.interrupt()
                    await waitUntilSettled(env)
                case .pause(let seconds):
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                }
                failures += report(env, since: before)
            }
            // Leave nothing pending between scenarios.
            if env.conversation.pendingApproval != nil { env.conversation.cancelApproval(); await waitUntilSettled(env) }
        }
        log("")
        log("DONE failures=\(failures)")
    }

    /// Waits until the engine has been idle (not thinking or speaking, no approval being presented) for a moment.
    private static func waitUntilSettled(_ env: AppEnvironment) async {
        let deadline = Date().addingTimeInterval(120)
        var idleSince: Date?
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 250_000_000)
            let state = env.conversation.state
            if state == .idle || state == .listening {
                if idleSince == nil { idleSince = Date() }
                if Date().timeIntervalSince(idleSince!) > 1.5 { return }
            } else {
                idleSince = nil
            }
        }
        log("TIMEOUT waiting for the engine (state \(env.conversation.state.label))")
    }

    /// Prints what happened and returns 1 when something looks broken.
    private static func report(_ env: AppEnvironment, since index: Int) -> Int {
        var failed = 0
        let new = env.conversation.transcript.dropFirst(min(index, env.conversation.transcript.count))
        for message in new {
            if message.role == .user && message.text.isEmpty {
                let results = message.toolResults.map { "\($0.toolUseID.suffix(6)): \($0.content)" }
                log("  TOOL RESULTS: \(results)")
                continue
            }
            if message.role == .user { continue }
            let calls = message.toolCalls.map { "\($0.name)(\($0.inputJSON))" }
            let who = message.isFromModel ? "MODEL" : "APP"
            if !message.text.isEmpty { log("  \(who): \(message.text)") }
            if !calls.isEmpty { log("  \(who) TOOLS: \(calls.joined(separator: ", "))") }
            if message.text.contains("could not reach") || message.text.contains("not accepted") || message.text.contains("demo answer") {
                failed = 1
            }
        }
        if let approval = env.conversation.pendingApproval {
            log("  APPROVAL: \(approval.title) | \(approval.rows.map { "\($0.label)=\($0.value)" }) | confirm=\(approval.confirmLabel)")
        }
        if !env.conversation.progressSteps.isEmpty {
            log("  PROGRESS: \(env.conversation.progressSteps.map { "\($0.done ? "x" : " ") \($0.title)" })")
        }
        if let error = env.conversation.errorMessage {
            log("  ERROR: \(error)")
            failed = 1
        }
        log("  STATE: \(env.conversation.state.label) | screen: \(env.router.currentScreenName) | mode: \(env.settings.interfaceMode.rawValue)")
        return failed
    }

    private static func log(_ line: String) {
        print("ECHOTEST \(line)")
    }
}
#endif
