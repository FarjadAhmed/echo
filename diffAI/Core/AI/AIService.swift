import Foundation
import UIKit

enum ChatRole: String {
    case user
    case assistant
}

/// A tool the model asked the app to run.
struct ToolCall: Equatable {
    let id: String
    let name: String
    /// The model's input, kept as JSON so it can be replayed exactly.
    let inputJSON: String
    /// The app action this maps to, or nil for a tool the app does not know.
    let action: AssistantAction?
}

/// What happened when the app ran a tool, sent back to the model.
struct ToolResult: Equatable {
    let toolUseID: String
    let content: String
    let isError: Bool
}

/// One turn in the conversation. Images are kept in memory only.
/// Messages are append-only: the live AI binds its reasoning to the exact history that produced it.
struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    var text: String
    var image: UIImage?
    /// Where the user was and what time it was, attached when the message was created so it never changes.
    var contextNote: String?
    /// Tools the assistant asked for in this turn.
    var toolCalls: [ToolCall] = []
    /// Results the app is sending back for the previous turn's tools.
    var toolResults: [ToolResult] = []
    /// The assistant turn's content blocks exactly as the API returned them (thinking, text, tool_use),
    /// replayed verbatim so the model keeps its reasoning across a tool loop.
    var rawContentJSON: String?
    /// True for replies the AI model wrote. False for lines ECHO's own features spoke (approvals,
    /// dialog questions, photo results). The live model is told which lines were the app's,
    /// so it never takes ownership of something it did not say.
    var isFromModel = false

    init(role: ChatRole, text: String, image: UIImage? = nil, contextNote: String? = nil) {
        self.role = role
        self.text = text
        self.image = image
        self.contextNote = contextNote
    }

    /// Tool-result messages and tool-only assistant turns carry no words and stay out of the transcript on screen.
    var isVisible: Bool {
        !text.isEmpty
    }
}

/// What the AI should know about the moment. Built fresh for every turn.
struct AssistantContext {
    var screenName: String = "Home"
    var timeOfDay: String = "day"
    var simpleMode: Bool = false
    var detailedAnswers: Bool = false
    var location: String? = nil
    /// Description of the last photo, so follow-up questions still know what it showed.
    var imageNote: String? = nil
    /// The web page currently analysed, if any.
    var webPage: WebPageSnapshot? = nil

    /// One line attached to the user's message.
    var note: String {
        var parts = ["Screen: \(screenName). Time: \(timeOfDay)."]
        if simpleMode { parts.append("The user prefers very short answers.") }
        if detailedAnswers { parts.append("The user asked for more detail.") }
        if let location { parts.append("Location: \(location).") }
        if let page = webPage { parts.append("Web page open: \(page.title).") }
        return parts.joined(separator: " ")
    }
}

/// One piece of a streamed reply.
enum AIEvent {
    case text(String)
    case toolCall(ToolCall)
    /// The model started something slow on the server, such as a web search. Spoken once so the user
    /// is never left in silence.
    case status(String)
    /// The turn finished. rawContentJSON holds the content blocks to replay; stopReason is the API's reason.
    case done(rawContentJSON: String?, stopReason: String?)
}

/// Implemented by MockAIService (offline demo) and RemoteAIService (live API).
protocol AIService {
    /// Realtime conversation: yields pieces as they are generated, so speech can start early.
    func chat(messages: [ChatMessage], context: AssistantContext) -> AsyncThrowingStream<AIEvent, Error>
    func describeImage(_ image: UIImage, question: String?) async throws -> String
    func answer(question: String, context: String?) async throws -> String
    func summarizeWebPage(_ snapshot: WebPageSnapshot) async throws -> String
    func draftMessage(intent: String) async throws -> String
}
