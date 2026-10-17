import Foundation

/// Commands that control the conversation itself rather than the app.
enum ControlCommand: Equatable {
    case stop
    case repeatLast
    case sayShorter
    case saySlower
    case help
    case goHome
    case goBack
    case yes
    case no
    case pause
    case resume
    case skip
}

enum VoiceCommand: Equatable {
    case control(ControlCommand)
    case action(AssistantAction)
    case unknown
}

/// How much the router should decide on its own.
enum RoutingMode {
    /// A live AI is available: the router handles only control words and exact app commands;
    /// everything else goes to the model, which understands natural language far better than keywords.
    case liveAI
    /// No live AI: the router also matches natural-language keywords for every feature.
    case offline
}

/// Phrase matching. Plain rules, not machine learning: fast, predictable, easy to extend.
/// Control words match only short phrases or whole phrases, so "read the back of the box" is not "go back".
struct VoiceCommandRouter {
    static let helpText = """
    You can say: what is in front of me, read this, scan this document, open camera, open website and a name, \
    what can I do here, read the page, click and a label, send a text, send an email, read my messages, \
    remind me to do something, where am I, call and a name, help me for an emergency, \
    repeat that, say it shorter, say it slower, go home, go back, voice only, or stop. \
    You can also just ask me anything.
    """

    func route(_ phrase: String, mode: RoutingMode = .offline) -> VoiceCommand {
        let words = normalize(phrase)
        guard !words.isEmpty else { return .unknown }
        let p = words.joined(separator: " ")
        let count = words.count

        // MARK: Control words (always)

        if exact(p, ["stop", "stop talking", "stop reading", "be quiet", "quiet", "silence", "shut up", "thats enough", "never mind", "nevermind", "stop it"]) {
            return .control(.stop)
        }
        if exact(p, ["pause", "pause reading", "pause that", "wait"]) { return .control(.pause) }
        if exact(p, ["resume", "continue", "keep reading", "continue reading", "keep going", "go on reading", "carry on"]) { return .control(.resume) }
        if exact(p, ["skip", "skip this", "skip ahead", "skip that", "next"]) { return .control(.skip) }
        if exact(p, ["repeat", "repeat that", "say that again", "say it again", "what did you say", "pardon", "again", "come again", "repeat please"]) {
            return .control(.repeatLast)
        }
        if count <= 5, containsAny(p, ["shorter", "too long", "briefly", "short version", "in short"]) { return .control(.sayShorter) }
        if count <= 5, containsAny(p, ["slower", "too fast", "slow down", "speak slower"]) { return .control(.saySlower) }
        if isAffirmation(words) { return .control(.yes) }
        if isNegation(words) { return .control(.no) }
        if exact(p, ["help", "help please", "what can you do", "what can i say", "commands", "list commands", "what are the commands", "how does this work"]) {
            return .control(.help)
        }
        if exact(p, ["go home", "home", "home screen", "main menu", "go to home", "go to the home screen", "take me home"]) { return .control(.goHome) }
        if exact(p, ["go back", "back", "previous screen", "return", "go back please"]) { return .control(.goBack) }

        // MARK: App commands (always). Exact phrases only, so they never fire inside a sentence.

        if exact(p, ["help me", "help me please", "i need help", "emergency", "sos", "call for help", "this is an emergency", "i need help now"]) {
            return .action(.emergency)
        }
        if exact(p, ["call emergency services", "call 911", "call 112", "call 999", "call 000", "call the police", "call an ambulance", "call the ambulance", "emergency services"]) {
            return .action(.callEmergencyServices)
        }
        if exact(p, ["play my briefing", "play briefing", "play the briefing", "play morning briefing", "my briefing", "hear my briefing", "read my briefing"]) {
            return .action(.dailyBriefing)
        }
        if exact(p, ["voice only", "voice only mode", "switch to voice only", "switch to voice only mode", "hide the screen", "voice mode"]) {
            return .action(.switchInterface(.voiceOnly))
        }
        if exact(p, ["show the screen", "show screen", "screen mode", "screen and voice", "switch to screen mode", "full mode", "show me the screen"]) {
            return .action(.switchInterface(.full))
        }
        if exact(p, ["reset demo data", "reset the demo data", "reset demo"]) { return .action(.resetDemoData) }
        if exact(p, ["send a check in", "send check in", "check in", "send a checkin", "send my caregiver a check in"]) { return .action(.sendCheckIn) }
        if let screen = screenCommand(words) { return .action(.openScreen(screen)) }
        if exact(p, ["what can i do here", "what can i do on this page", "what can i do on this site", "what is on this page", "whats on this page", "describe this page", "describe the page"]) {
            return .action(.describeWebPage)
        }

        guard mode == .offline else { return .unknown }

        // MARK: Natural-language keywords (offline only)

        if startsWithAny(p, ["take a photo", "take a picture", "take photo", "take picture", "capture", "snap a photo", "shutter", "take the photo"]) {
            return .action(.takePhoto)
        }
        if containsAny(p, ["what is this", "whats this", "what is in front of me", "whats in front of me", "what do you see", "describe this", "describe the scene", "describe what", "what am i looking at", "whats around me", "what is around me", "look around", "whats in front", "what is in front"]) {
            return .action(.describeScene)
        }
        if containsAny(p, ["read the page", "read this page", "read the main text", "reader mode", "read page", "read it all", "read the whole page", "read the article"]) {
            return .action(.readWebPage)
        }
        if containsAny(p, ["scan", "this document", "the document", "this letter", "the letter", "prescription", "this form", "this paper"]) {
            return .action(.scanDocument)
        }
        if containsAny(p, ["read this", "read the text", "read text", "what does this say", "what does it say", "read the label", "read the sign", "read it", "read that", "read what"]) {
            return .action(.readText)
        }
        if containsAny(p, ["what color", "what colour", "which color", "which colour", "identify color", "identify colour", "what colors", "what colours"]) {
            return .action(.identifyColor)
        }
        if let target = remainder(words, after: ["where is my", "where is the", "where are my", "find my", "find the", "look for my", "look for the"]) {
            return .action(.findObject(target))
        }
        if containsAny(p, ["where am i", "where are we", "my location", "my address", "what is my address", "whats my address", "what street"]) {
            return .action(.whereAmI)
        }
        if containsAny(p, ["good morning", "daily briefing", "briefing", "my day", "whats happening today", "what is happening today", "whats today"]) {
            return .action(.dailyBriefing)
        }
        if let rest = remainder(words, after: ["remind me to", "remind me about", "set a reminder to", "set a reminder for", "set a reminder", "set reminder", "remind me", "new reminder"], allowEmpty: true) {
            return .action(.setReminder(rest))
        }
        if containsAny(p, ["read my messages", "read messages", "my messages", "my inbox", "read my email", "read my emails", "read my texts", "unread messages", "any messages", "new messages", "any new messages", "check my messages", "check messages"]) {
            return .action(.readMessages)
        }
        if let name = remainder(words, after: ["reply to"]) {
            return .action(.composeText(to: name))
        }
        if containsAny(p, ["send an email", "send email", "write an email", "write email", "new email", "compose email", "compose an email", "email to"]) {
            return .action(.composeEmail(to: remainder(words, after: ["email to", "an email to"])))
        }
        if containsAny(p, ["send a text", "send text", "text message", "send a message", "send message", "write a text", "new text", "new message", "text to", "message to", "send a text to"]) {
            return .action(.composeText(to: remainder(words, after: ["text to", "message to", "a text to", "a message to"])))
        }
        if let name = remainder(words, after: ["call", "phone", "ring", "dial", "make a call to", "give a call to"], allowEmpty: true), startsWithAny(p, ["call", "phone", "ring", "dial", "make a call", "give a call"]) {
            return .action(.callContact(name))
        }
        if let typed = typingCommand(words) {
            return .action(typed)
        }
        if let site = remainder(words, after: ["open website", "go to website", "open the website", "open site", "visit", "browse to", "open", "go to", "load"]), !site.isEmpty {
            return .action(.openWebsite(site))
        }
        if let target = remainder(words, after: ["click on", "click", "press", "tap", "select", "choose", "push"]) {
            return .action(.clickElement(target))
        }
        if containsAny(p, ["scroll down", "page down", "go down"]) { return .action(.scrollPage(down: true)) }
        if containsAny(p, ["scroll up", "page up", "go up"]) { return .action(.scrollPage(down: false)) }
        if exact(p, ["submit", "submit the form", "submit form", "send the form", "submit it", "send it off"]) { return .action(.submitForm) }
        if containsAny(p, ["next heading", "go to the next heading", "next section"]) { return .action(.nextHeading) }
        if let number = remainder(words, after: ["read link number", "read link", "link number", "open link number"]).flatMap({ Int($0) }) {
            return .action(.readLink(number))
        }

        return .unknown
    }

    // MARK: - Matching helpers

    private func exact(_ p: String, _ phrases: [String]) -> Bool {
        phrases.contains(p)
    }

    private func containsAny(_ p: String, _ phrases: [String]) -> Bool {
        let padded = " \(p) "
        return phrases.contains { padded.contains(" \($0) ") }
    }

    private func startsWithAny(_ p: String, _ phrases: [String]) -> Bool {
        phrases.contains { p == $0 || p.hasPrefix("\($0) ") }
    }

    /// Words after the first matching phrase, e.g. "call mom" gives "mom". Nil when the phrase is absent,
    /// or (unless allowEmpty) when nothing follows it.
    private func remainder(_ words: [String], after phrases: [String], allowEmpty: Bool = false) -> String? {
        let p = " \(words.joined(separator: " ")) "
        for phrase in phrases {
            guard let range = p.range(of: " \(phrase) ") else { continue }
            let rest = p[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return rest }
            if allowEmpty { return "" }
        }
        return nil
    }

    private static let affirmatives: Set<String> = ["yes", "yeah", "yep", "yup", "okay", "ok", "sure", "confirm", "correct", "alright", "absolutely", "certainly", "affirmative", "right", "fine", "please"]
    private static let affirmativePhrases: Set<String> = ["go ahead", "do it", "thats right", "that is right", "go on", "yes please", "please do", "sounds good", "lets do it", "lets go", "send it", "send", "proceed", "continue"]
    private static let negatives: Set<String> = ["no", "nope", "nah", "cancel", "dont", "negative"]
    private static let negativePhrases: Set<String> = ["do not", "not now", "no thanks", "no thank you", "forget it", "dont do it", "dont do that", "leave it", "thats wrong", "that is wrong", "cancel that", "cancel it"]

    /// Short phrases made of yes-words, e.g. "yes", "okay sure", "yes please".
    private func isAffirmation(_ words: [String]) -> Bool {
        let p = words.joined(separator: " ")
        if Self.affirmativePhrases.contains(p) { return true }
        guard words.count <= 3, let first = words.first, Self.affirmatives.contains(first), first != "please", first != "right", first != "fine" || words.count == 1 else {
            return words.count == 1 && (words[0] == "right" || words[0] == "fine")
        }
        return words.allSatisfy { Self.affirmatives.contains($0) || $0 == "thanks" || $0 == "thank" || $0 == "you" }
    }

    private func isNegation(_ words: [String]) -> Bool {
        let p = words.joined(separator: " ")
        if Self.negativePhrases.contains(p) { return true }
        guard words.count <= 3, let first = words.first, Self.negatives.contains(first) else { return false }
        return words.allSatisfy { Self.negatives.contains($0) || $0 == "thanks" || $0 == "thank" || $0 == "you" || $0 == "please" }
    }

    /// "open camera", "show settings", "messages" and the like. Exact forms only.
    private func screenCommand(_ words: [String]) -> AppScreen? {
        let names: [(String, AppScreen)] = [
            ("camera", .camera), ("the camera", .camera),
            ("web", .web), ("websites", .web), ("browser", .web), ("web assistant", .web), ("the web", .web),
            ("tools", .tools),
            ("history", .history), ("my history", .history),
            ("messages", .messages), ("my messages", .messages), ("inbox", .messages), ("notifications", .messages), ("notification center", .messages),
            ("reminders", .reminders), ("my reminders", .reminders),
            ("my day", .briefing), ("briefing", .briefing), ("daily briefing", .briefing), ("the briefing", .briefing),
            ("safety", .safety), ("the safety screen", .safety), ("safety screen", .safety), ("emergency screen", .safety),
            ("caregiver", .caregiver), ("caregiver dashboard", .caregiver), ("the caregiver dashboard", .caregiver),
            ("settings", .settings), ("the settings", .settings),
            ("tips", .accessibilityTips), ("accessibility tips", .accessibilityTips), ("accessibility", .accessibilityTips),
        ]
        let p = words.joined(separator: " ")
        for (name, screen) in names {
            if p == name || p == "open \(name)" || p == "show \(name)" || p == "go to \(name)" || p == "show me \(name)" || p == "open the \(name)" {
                return screen
            }
        }
        return nil
    }

    /// "type Anna in the first box", "enter 42 into phone number", "fill name with Anna".
    private func typingCommand(_ words: [String]) -> AssistantAction? {
        guard let first = words.first else { return nil }
        let p = words.joined(separator: " ")
        if ["type", "enter", "put", "write"].contains(first) {
            for separator in [" into ", " in the ", " in "] {
                if let range = p.range(of: separator) {
                    let value = String(p[p.index(p.startIndex, offsetBy: first.count)..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let target = String(p[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty, !target.isEmpty {
                        return .typeInField(target: target, value: value)
                    }
                }
            }
        }
        if first == "fill", let range = p.range(of: " with ") {
            let target = String(p[p.index(p.startIndex, offsetBy: 4)..<range.lowerBound])
                .replacingOccurrences(of: "in ", with: "")
                .trimmingCharacters(in: .whitespaces)
            let value = String(p[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty, !target.isEmpty {
                return .typeInField(target: target, value: value)
            }
        }
        return nil
    }

    /// Lowercases, drops apostrophes, and splits into words.
    private func normalize(_ phrase: String) -> [String] {
        let lowered = phrase.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        let cleaned = lowered.map { $0.isLetter || $0.isNumber ? String($0) : " " }.joined()
        return cleaned.split(separator: " ").map(String.init)
    }
}
