import Foundation
import UIKit

/// Offline stand-in for a live AI. Gives realistic canned answers, streamed word by word
/// so the demo feels like a real conversation. Needs no key and no network.
struct MockAIService: AIService {
    /// Delay between words, about the pace of live generation.
    private let wordDelay: UInt64 = 45_000_000

    func chat(messages: [ChatMessage], context: AssistantContext) -> AsyncThrowingStream<AIEvent, Error> {
        let question = messages.last(where: { $0.role == .user && !$0.text.isEmpty })?.text ?? ""
        let previousAnswer = messages.last(where: { $0.role == .assistant })?.text ?? ""
        return stream(Self.reply(to: question, previousAnswer: previousAnswer, context: context))
    }

    func describeImage(_ image: UIImage, question: String?) async throws -> String {
        if let question, question.lowercased().contains("where") {
            return "In demo mode I would say it is left of centre, about halfway up the photo. Live answers need an API key in Settings."
        }
        return "This is a demo description, because live image analysis needs an API key in Settings. The picture shows a bright indoor scene. Ask me a question about it."
    }

    func answer(question: String, context: String?) async throws -> String {
        if let context, question.lowercased().contains("summarize") {
            let firstSentence = context.split(separator: ".").first.map(String.init) ?? context
            return "In demo mode, here is the start of the document: \(firstSentence.trimmingCharacters(in: .whitespaces))."
        }
        return Self.reply(to: question, previousAnswer: "", context: AssistantContext())
    }

    func summarizeWebPage(_ snapshot: WebPageSnapshot) async throws -> String {
        Self.summary(of: snapshot)
    }

    func draftMessage(intent: String) async throws -> String {
        "Hello, I wanted to let you know that \(intent). Thank you."
    }

    /// Plain-language summary of a page, built from what was actually found on it.
    static func summary(of snapshot: WebPageSnapshot) -> String {
        let buttons = snapshot.elements.filter { $0.kind == "button" }.count
        let fields = snapshot.elements.filter { $0.kind == "field" }.count
        var parts = ["This page is \(snapshot.title.isEmpty ? "untitled" : snapshot.title)."]
        if let heading = snapshot.headings.first {
            parts.append("The main heading is \(heading).")
        }
        parts.append("There are \(snapshot.links.count) links, \(buttons) buttons, and \(fields) form fields.")
        if snapshot.hasPasswordField {
            parts.append("It has a password box. I will never read passwords aloud.")
        }
        parts.append("Say read the page to hear the text, or say click and the name of something.")
        return parts.joined(separator: " ")
    }

    /// Picks a canned reply from simple keywords.
    static func reply(to question: String, previousAnswer: String, context: AssistantContext) -> String {
        let words = Set(question.lowercased().split { !$0.isLetter }.map(String.init))

        if words.contains("shorter") || words.contains("briefly") {
            guard !previousAnswer.isEmpty else { return "There is nothing to shorten yet." }
            let firstSentence = previousAnswer.split(separator: ".").first.map { String($0) } ?? previousAnswer
            return firstSentence.hasSuffix(".") ? firstSentence : firstSentence + "."
        }
        if words.contains("time") {
            return "It is about \(Date().formatted(date: .omitted, time: .shortened)) right now."
        }
        if words.contains("weather") {
            return "This is demo data, so I cannot check the real weather. In demo mode it would be mild and partly cloudy, around 18 degrees."
        }
        if words.contains("joke") {
            return "Why did the tomato turn red? Because it saw the salad dressing."
        }
        if words.contains("hello") || words.contains("hi") || words.contains("hey") {
            return "Hello. I am here whenever you need me. You can ask me anything, or say help to hear what I can do."
        }
        if words.contains("who") && (words.contains("you") || words.contains("are")) {
            return "I am ECHO, a calm voice assistant. I can help you look at things with the camera, read websites, write messages, and set reminders."
        }
        if let note = context.imageNote {
            return "Looking at the photo again: \(note) I am in demo mode, so I can only repeat what the sample shows."
        }
        return "That is a good question. I am running in demo mode, so this is a sample answer. Add an API key in Settings to get live answers."
    }

    /// Splits the reply on spaces and yields each word with a short pause.
    private func stream(_ text: String) -> AsyncThrowingStream<AIEvent, Error> {
        let delay = wordDelay
        let words = text.components(separatedBy: " ")
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for (index, word) in words.enumerated() {
                        try Task.checkCancellation()
                        continuation.yield(.text(index == 0 ? word : " " + word))
                        try await Task.sleep(nanoseconds: delay)
                    }
                    continuation.yield(.done(rawContentJSON: nil, stopReason: "end_turn"))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
