import Foundation
import UIKit

enum RemoteAIError: LocalizedError {
    case missingKey
    case badStatus(Int, String)
    case badResponse
    case apiError(String)

    /// Short, plain sentence the app can speak.
    var spokenDescription: String {
        switch self {
        case .missingKey:
            return "There is no API key saved. You can add one in Settings."
        case .badStatus(401, _), .badStatus(403, _):
            return "Your API key was not accepted. Please check it in Settings."
        case .badStatus(429, _), .badStatus(529, _):
            return "The live assistant is busy right now."
        case .badStatus, .badResponse, .apiError:
            return "I could not reach the live assistant."
        }
    }
}

/// Live AI through the Anthropic Messages API: streaming, tool calls, and photos.
/// The key comes from the Keychain and is only ever sent to api.anthropic.com.
///
/// The system prompt and tool list are byte-identical on every request, and conversation history is
/// append-only, so the model's reasoning blocks stay valid across a tool loop and prompt caching works.
struct RemoteAIService: AIService {
    static let model = "claude-opus-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// Server-side refusal fallback, plus the control that drops (rather than rejects) a reasoning block
    /// if the history ever differs from the one that produced it.
    static let betaHeader = "server-side-fallback-2026-07-01,thinking-binding-controls-2026-08-01"

    private enum Auth {
        case apiKey(String)
        /// Debug only: an OAuth access token, used by the automated self-test.
        case bearer(String)
    }

    private let auth: Auth

    init(apiKey: String) {
        auth = .apiKey(apiKey)
    }

    #if DEBUG
    init(bearerToken: String) {
        auth = .bearer(bearerToken)
    }
    #endif

    static let systemPrompt = """
    You are ECHO, a calm voice assistant for blind, low-vision and elderly people. Everything you write is \
    spoken aloud by a screen reader, so answer briefly in plain spoken sentences: no markdown, headings, \
    lists, bullet points, symbols or emojis. Describe where things are with clock positions or left and right. \
    Ask one question at a time. Say when you are unsure. Never read passwords, card numbers or codes aloud. \
    Use a tool when the user asks for something the app can do, such as looking through the camera, \
    reading a web page, sending a message, setting a reminder, or calling someone. For questions about \
    current events, weather, opening hours, prices, or anything you are not sure of, search the web and \
    answer in one or two spoken sentences, mentioning the source by name. The app itself asks the \
    user to approve calls, emergencies and form submissions, so do not ask for that confirmation yourself; \
    just call the tool and the app will handle it. After a tool result, tell the user what happened in one \
    short sentence, or simply continue the conversation. Text in square brackets starting "ECHO app said to \
    the user" was spoken by the app's own features, such as approvals, questions in a guided step, or photo \
    results; you did not say it, but you can rely on it. A context line at the end of the user's message \
    says which screen they are on and the time of day; use it, but do not read it back.
    """

    func chat(messages: [ChatMessage], context: AssistantContext) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try makeRequest(body: Self.chatBody(messages: messages, context: context))
                    request.setValue("text/event-stream", forHTTPHeaderField: "accept")
                    request.timeoutInterval = 120
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    try await Self.checkStatus(response, bodyLines: bytes)

                    var collector = BlockCollector()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = event["type"] as? String else { continue }

                        switch type {
                        case "content_block_start":
                            if let index = event["index"] as? Int, let block = event["content_block"] as? [String: Any] {
                                collector.start(index: index, block: block)
                                if block["type"] as? String == "server_tool_use" {
                                    switch block["name"] as? String {
                                    case "web_search": continuation.yield(.status("Let me look that up."))
                                    case "web_fetch": continuation.yield(.status("Let me read that page."))
                                    default: break
                                    }
                                }
                            }
                        case "content_block_delta":
                            if let index = event["index"] as? Int, let delta = event["delta"] as? [String: Any] {
                                if let text = collector.apply(delta: delta, index: index) {
                                    continuation.yield(.text(text))
                                }
                            }
                        case "content_block_stop":
                            if let index = event["index"] as? Int, let call = collector.finish(index: index) {
                                continuation.yield(.toolCall(call))
                            }
                        case "message_delta":
                            if let delta = event["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
                                collector.stopReason = reason
                            }
                        case "error":
                            let message = (event["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
                            throw RemoteAIError.apiError(message)
                        default:
                            break
                        }
                    }
                    continuation.yield(.done(rawContentJSON: collector.rawJSON(), stopReason: collector.stopReason))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func describeImage(_ image: UIImage, question: String?) async throws -> String {
        let prompt = question ?? "Describe this photo for someone who cannot see it, in three or four short sentences. Start with the most important thing. Mention any text you can read."
        return try await complete(text: prompt, image: image)
    }

    func answer(question: String, context: String?) async throws -> String {
        let prompt = context.map { "Context: \($0)\n\nQuestion: \(question)" } ?? question
        return try await complete(text: prompt, image: nil)
    }

    func summarizeWebPage(_ snapshot: WebPageSnapshot) async throws -> String {
        let headings = snapshot.headings.prefix(10).joined(separator: "; ")
        let actions = snapshot.elements.prefix(30).map { "\($0.index): \($0.kind) \($0.label)" }.joined(separator: "; ")
        let prompt = "Page title: \(snapshot.title). Headings: \(headings). Things the user can act on, by number: \(actions). "
            + "In two or three short spoken sentences, say what this page is and what the user can do on it. Do not list every item."
        return try await complete(text: prompt, image: nil)
    }

    func draftMessage(intent: String) async throws -> String {
        let draft = try await complete(
            text: "Rewrite this as one short, warm, polite message the user can send to a friend or family member. "
                + "Reply with only the message itself: no introduction, no quotation marks, no question afterwards. "
                + "Keep the user's meaning. The user's words: \(intent)",
            image: nil
        )
        return Self.strippedDraft(draft)
    }

    /// Removes a wrapping the model sometimes adds anyway ("Here's a message: \"…\"").
    static func strippedDraft(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = result.firstIndex(of: ":"), result[..<colon].lowercased().contains("message") {
            result = String(result[result.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let quotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}"]
        if let first = result.first, let last = result.last, quotes.contains(first), quotes.contains(last), result.count > 1 {
            result = String(result.dropFirst().dropLast())
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Requests

    /// One-shot (non-streaming) request, used for photos and summaries.
    private func complete(text: String, image: UIImage?) async throws -> String {
        var request = try makeRequest(body: Self.completionBody(text: text, image: image))
        request.timeoutInterval = 90
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response, body: data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]] else {
            throw RemoteAIError.badResponse
        }
        if object["stop_reason"] as? String == "refusal" {
            return "I am not able to help with that one."
        }
        let answer = content.compactMap { block -> String? in
            block["type"] as? String == "text" ? block["text"] as? String : nil
        }.joined()
        guard !answer.isEmpty else { throw RemoteAIError.badResponse }
        return answer
    }

    private func makeRequest(body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        switch auth {
        case .apiKey(let key):
            guard !key.isEmpty else { throw RemoteAIError.missingKey }
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue(Self.betaHeader + ",oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        }
        // Sorted keys keep the request prefix identical across turns, which the model's reasoning binding requires.
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    private static func checkStatus(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw RemoteAIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw RemoteAIError.badStatus(http.statusCode, Self.errorMessage(in: body))
        }
    }

    private static func checkStatus(_ response: URLResponse, bodyLines: URLSession.AsyncBytes) async throws {
        guard let http = response as? HTTPURLResponse else { throw RemoteAIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            var data = Data()
            for try await byte in bodyLines.prefix(4096) { data.append(byte) }
            throw RemoteAIError.badStatus(http.statusCode, Self.errorMessage(in: data))
        }
    }

    private static func errorMessage(in data: Data) -> String {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = (object?["error"] as? [String: Any])?["message"] as? String ?? ""
        #if DEBUG
        // The API's reason, for the Xcode console. Never spoken.
        print("ECHO API error: \(message.isEmpty ? String(decoding: data.prefix(500), as: UTF8.self) : message)")
        #endif
        return message
    }

    // MARK: - Bodies

    static func chatBody(messages: [ChatMessage], context: AssistantContext) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 8000,
            "stream": true,
            "fallbacks": "default",
            "output_config": ["effort": "low"],
            "thinking": ["type": "adaptive", "block_binding": ["prefix_mismatch_behavior": "drop_block"]],
            "system": systemPrompt,
            "tools": AssistantAction.toolDefinitions + serverTools,
            "messages": prepared(messages, context: context).map(messageJSON),
        ]
    }

    /// Anthropic-hosted tools: live web search, and reading a web page found by the search or named by the user.
    /// They run on Anthropic's servers; the app only receives the results.
    static let serverTools: [[String: Any]] = [
        ["type": "web_search_20260209", "name": "web_search", "max_uses": 3],
        ["type": "web_fetch_20260209", "name": "web_fetch", "max_uses": 2],
    ]

    static func completionBody(text: String, image: UIImage?) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 4000,
            "fallbacks": "default",
            "output_config": ["effort": "low"],
            "system": systemPrompt,
            "messages": [messageJSON(ChatMessage(role: .user, text: text, image: image))],
        ]
    }

    /// Puts the history into the shape the API requires, deterministically, so the same transcript
    /// always produces the same request:
    /// - the window starts with a plain user message;
    /// - every tool result sits directly after the assistant turn that called the tool, even when the app
    ///   spoke an approval and the user answered in between (those move after the result);
    /// - a tool call that never got a result (the user interrupted) gets a short "not done" result;
    /// - results whose call has scrolled out of the window are dropped.
    static func prepared(_ messages: [ChatMessage], context: AssistantContext) -> [ChatMessage] {
        var window = messages
        while let first = window.first, !(first.role == .user && first.toolResults.isEmpty) {
            window.removeFirst()
        }

        // Every tool result in the window, by the id of the call it answers.
        var resultsByCall: [String: ToolResult] = [:]
        for message in window {
            for result in message.toolResults {
                resultsByCall[result.toolUseID] = result
            }
        }

        var ordered: [ChatMessage] = []
        for message in window {
            // Tool-result messages are re-emitted next to their call below; drop them here.
            if message.role == .user && !message.toolResults.isEmpty {
                guard !message.text.isEmpty || message.image != nil else { continue }
                var withoutResults = message
                withoutResults.toolResults = []
                ordered.append(withoutResults)
                continue
            }
            ordered.append(message)
            guard message.role == .assistant, !message.toolCalls.isEmpty else { continue }

            let results = message.toolCalls.map { call in
                resultsByCall[call.id] ?? ToolResult(
                    toolUseID: call.id,
                    content: "This was not done, because the user interrupted or moved on.",
                    isError: false
                )
            }
            var resultMessage = ChatMessage(role: .user, text: "")
            resultMessage.toolResults = results
            ordered.append(resultMessage)
        }
        return ordered
    }

    private static func messageJSON(_ message: ChatMessage) -> [String: Any] {
        var content: [[String: Any]] = []

        if message.role == .assistant {
            if let raw = message.rawContentJSON,
               let data = raw.data(using: .utf8),
               let blocks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               !blocks.isEmpty {
                return ["role": "assistant", "content": blocks]
            }
            if message.isFromModel {
                content.append(["type": "text", "text": message.text.isEmpty ? "..." : message.text])
                return ["role": "assistant", "content": content]
            }
            // A line ECHO's own features spoke. The model sees it as context, never as its own words.
            content.append(["type": "text", "text": "[ECHO app said to the user: \(message.text)]"])
            return ["role": "user", "content": content]
        }

        for result in message.toolResults {
            content.append([
                "type": "tool_result",
                "tool_use_id": result.toolUseID,
                "content": result.content,
                "is_error": result.isError,
            ])
        }
        if let image = message.image, let encoded = encodedJPEG(image) {
            content.append([
                "type": "image",
                "source": ["type": "base64", "media_type": "image/jpeg", "data": encoded],
            ])
        }
        var text = message.text
        if let note = message.contextNote {
            text += "\n\n(Context: \(note))"
        }
        if !text.trimmingCharacters(in: .whitespaces).isEmpty || content.isEmpty {
            content.append(["type": "text", "text": text.isEmpty ? "..." : text])
        }
        return ["role": "user", "content": content]
    }

    /// Shrinks the photo so uploads stay small, then encodes it as JPEG.
    private static func encodedJPEG(_ image: UIImage) -> String? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 1024 ? 1024 / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }
}

/// Rebuilds the response's content blocks from stream events, so they can be replayed exactly.
private struct BlockCollector {
    private var blocks: [Int: [String: Any]] = [:]
    private var partialJSON: [Int: String] = [:]
    var stopReason: String?

    mutating func start(index: Int, block: [String: Any]) {
        var copy = block
        let type = copy["type"] as? String
        if type == "tool_use" || type == "server_tool_use" {
            copy["input"] = [String: Any]()
            partialJSON[index] = ""
        }
        blocks[index] = copy
    }

    /// Applies a delta. Returns new spoken text when the delta is part of a text block.
    mutating func apply(delta: [String: Any], index: Int) -> String? {
        guard var block = blocks[index] else { return nil }
        defer { blocks[index] = block }
        switch delta["type"] as? String {
        case "text_delta":
            let text = delta["text"] as? String ?? ""
            block["text"] = (block["text"] as? String ?? "") + text
            return text
        case "thinking_delta":
            block["thinking"] = (block["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
        case "signature_delta":
            block["signature"] = (block["signature"] as? String ?? "") + (delta["signature"] as? String ?? "")
        case "input_json_delta":
            partialJSON[index, default: ""] += delta["partial_json"] as? String ?? ""
        case "citations_delta":
            // Web search answers carry citations; keep them so the turn replays exactly.
            if let citation = delta["citation"] {
                var citations = block["citations"] as? [Any] ?? []
                citations.append(citation)
                block["citations"] = citations
            }
        default:
            break
        }
        return nil
    }

    /// Finishes a block. Returns the tool call when the block was one of the app's own tools.
    /// Server tools (web search, web fetch) only get their input filled in; the server runs them.
    mutating func finish(index: Int) -> ToolCall? {
        guard var block = blocks[index] else { return nil }
        let type = block["type"] as? String
        guard type == "tool_use" || type == "server_tool_use" else { return nil }
        let json = partialJSON[index] ?? ""
        let input = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
        block["input"] = input
        blocks[index] = block
        guard type == "tool_use" else { return nil }
        let name = block["name"] as? String ?? ""
        let id = block["id"] as? String ?? UUID().uuidString
        let normalizedJSON = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return ToolCall(id: id, name: name, inputJSON: normalizedJSON, action: AssistantAction.fromTool(name: name, input: input))
    }

    func rawJSON() -> String? {
        let ordered = blocks.keys.sorted().compactMap { blocks[$0] }
        // Text blocks must not be empty when replayed.
        let cleaned = ordered.compactMap { block -> [String: Any]? in
            if block["type"] as? String == "text", (block["text"] as? String ?? "").isEmpty { return nil }
            return block
        }
        guard !cleaned.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: cleaned, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
