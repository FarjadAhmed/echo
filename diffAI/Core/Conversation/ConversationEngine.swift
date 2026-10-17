import AVFoundation
import Combine
import Foundation
import UIKit

enum ConversationState: Equatable {
    case idle
    case listening
    case thinking
    case speaking

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .speaking: return "Speaking"
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "checkmark.circle"
        case .listening: return "ear"
        case .thinking: return "ellipsis.bubble"
        case .speaking: return "speaker.wave.2.fill"
        }
    }
}

/// One line in the "Task progress" card while ECHO works through a multi-step request.
struct ProgressStep: Identifiable, Equatable {
    let id = UUID()
    let title: String
    var done: Bool
}

/// The realtime conversation loop: listen, think, speak, listen again.
/// Answers are spoken sentence by sentence while they stream in.
/// Consequential actions stop at an ApprovalRequest; guided dialogs run through a DialogFlow;
/// with the live AI, tool calls are run and their results sent back so the model can finish the job.
@MainActor
final class ConversationEngine: ObservableObject {
    @Published private(set) var state: ConversationState = .idle {
        didSet { stateChanged(from: oldValue) }
    }
    @Published private(set) var transcript: [ChatMessage] = []
    @Published private(set) var partialText = ""
    @Published private(set) var errorMessage: String?
    /// Waiting for the user to confirm, change, or cancel. The approval screen binds to this.
    @Published private(set) var pendingApproval: ApprovalRequest?
    /// Steps of the current task, for the progress card. Empty when nothing multi-step is happening.
    @Published private(set) var progressSteps: [ProgressStep] = []

    /// Kept for views that only need the sentence.
    var pendingConfirmation: String? { pendingApproval?.summary }

    private let settings: AppSettings
    private let speechOutput: SpeechOutputCoordinator
    private let listener: ListenService
    private let haptics: HapticsService
    private let permissions: PermissionManager
    private let actions: ActionExecutor
    private let history: HistoryStore
    private let makeAIService: () -> any AIService
    private let commandRouter = VoiceCommandRouter()
    private let fallbackAI = MockAIService()

    /// Changes whenever the current answer is cancelled, so stale work does nothing.
    private var turn = UUID()
    private var streamTask: Task<Void, Never>?
    private var speechChain: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var approvedRun: (() async -> String)?
    private var approvalCancelled: (() -> Void)?
    private var activeFlow: (any DialogFlow)?
    private var toolLoop: ToolLoop?
    private var lastAnswer = ""
    /// What the last photo showed, so follow-up questions still know about it.
    private var imageNote: String?
    private var interruptionObserver: NSObjectProtocol?

    /// Tool calls from one model turn, run one after another; results go back to the model together.
    private struct ToolLoop {
        var remaining: [ToolCall]
        var results: [ToolResult]
        var depth: Int
        /// True when at least one result needs the model to tell the user what happened.
        var needsNarration = false
    }

    private static let maxToolDepth = 4

    init(
        settings: AppSettings,
        speechOutput: SpeechOutputCoordinator,
        listener: ListenService,
        haptics: HapticsService,
        permissions: PermissionManager,
        actions: ActionExecutor,
        history: HistoryStore,
        makeAIService: @escaping () -> any AIService
    ) {
        self.settings = settings
        self.speechOutput = speechOutput
        self.listener = listener
        self.haptics = haptics
        self.permissions = permissions
        self.actions = actions
        self.history = history
        self.makeAIService = makeAIService

        // Voice-only mode: photos are taken without a screen.
        actions.onBackgroundPhotoStarted = { [weak self] in
            guard let self else { return }
            Task { await self.speechOutput.say("Hold the phone up and keep it still.") }
        }
        actions.onBackgroundPhoto = { [weak self] image, purpose in
            guard let self else { return }
            if let image {
                self.analyze(image, purpose: purpose)
            } else {
                self.announce("I could not use the camera. Check that ECHO is allowed to use it in Settings, or switch to screen mode to choose a photo.")
            }
        }

        listener.onPartial = { [weak self] text in self?.handlePartial(text) }
        listener.onUtteranceEnd = { [weak self] text in self?.handleUtterance(text) }
        listener.onFailure = { [weak self] message in self?.fail(message) }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // 1 is AVAudioSession.InterruptionType.began (the enum itself is deprecated in the newest SDK).
            guard let self, let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, raw == 1 else { return }
            Task { @MainActor in self.stopEverything(announce: nil) }
        }
    }

    // MARK: - Controls (mic button, big stop button, magic tap, shake, typed input)

    /// Mic button: starts listening, stops listening, or interrupts a reply.
    func toggleListening() {
        switch state {
        case .idle: beginListening()
        case .listening: stopEverything(announce: "Stopped listening.")
        case .thinking, .speaking: interrupt()
        }
    }

    /// Starts the microphone, asking for permission first if it has never been asked.
    func beginListening() {
        guard state == .idle else { return }
        errorMessage = nil
        if permissions.voicePermissionsGranted {
            startListeningNow()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.permissions.ensureVoicePermissions()
            guard self.state == .idle else { return }
            if granted {
                self.startListeningNow()
            } else {
                self.fail("ECHO cannot hear you without the microphone and speech recognition. You can turn them on in Settings, or type instead.")
            }
        }
    }

    private func startListeningNow() {
        do {
            try AudioSession.activateConversation()
        } catch {
            fail("I couldn't use the microphone. You can type instead.")
            return
        }
        listener.start()
        guard listener.isRunning else { return }
        state = .listening
        resetIdleTimer()
    }

    /// Big stop button and shake: cancel speech and any answer in progress. Listens again if the mic was on.
    func interrupt() {
        cancelCurrentTurn()
        toolLoop = nil
        if listener.isRunning {
            state = .listening
            resetIdleTimer()
        } else {
            state = .idle
        }
    }

    func shakeDetected() {
        if state != .idle { interrupt() }
    }

    /// Stops speech, cancels answers and reading, and stops listening. Approval and dialogs stay.
    func stopEverything(announce: String?) {
        cancelCurrentTurn()
        toolLoop = nil
        actions.stopReading()
        idleTask?.cancel()
        listener.stop()
        partialText = ""
        state = .idle
        if let announce {
            Task { await speechOutput.say(announce) }
        }
    }

    /// Typed fallback for when the microphone or speech recognition is unavailable.
    func submitTyped(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        errorMessage = nil
        cancelCurrentTurn()
        process(clean)
    }

    /// Speaks text that did not come from the conversation, such as a reminder firing or a sent message.
    func announce(_ text: String) {
        reply(text)
    }

    // MARK: - Approval (buttons on the approval screen; voice yes/no goes through process)

    func approve() {
        guard let request = pendingApproval, let run = approvedRun else { return }
        clearApproval()
        runApproved(request, run)
    }

    func cancelApproval() {
        guard pendingApproval != nil else { return }
        let onCancel = approvalCancelled
        clearApproval()
        activeFlow = nil
        progressSteps = []
        onCancel?()
        if toolLoop != nil {
            resumeToolLoop()
        } else {
            reply("Cancelled. Nothing was done.")
        }
    }

    /// "Change details": drops the request and asks what to change. The next reply starts over.
    func changeApproval() {
        guard pendingApproval != nil else { return }
        let onCancel = approvalCancelled
        clearApproval()
        activeFlow = nil
        toolLoop = nil
        progressSteps = []
        onCancel?()
        reply("Okay. Tell me what you want to change, and we will start again.")
    }

    // MARK: - Guided dialogs

    /// Starts a multi-step dialog. Replies go to the flow until it finishes or the user cancels.
    func startFlow(_ flow: any DialogFlow, steps: [String] = []) {
        activeFlow = flow
        toolLoop = nil
        progressSteps = steps.map { ProgressStep(title: $0, done: false) }
        cancelCurrentTurn()
        let id = turn
        state = .thinking
        streamTask = Task { [weak self] in
            guard let self else { return }
            let step = await flow.start()
            guard id == self.turn else { return }
            self.apply(step)
        }
    }

    /// Marks the next unfinished progress step as done.
    func completeNextStep() {
        guard let index = progressSteps.firstIndex(where: { !$0.done }) else { return }
        progressSteps[index].done = true
    }

    private func apply(_ step: DialogStep) {
        switch step {
        case .ask(let question):
            completeNextStep()
            reply(question)
        case .approve(let request, let run):
            activeFlow = nil
            completeNextStep()
            present(request, run: run)
        case .finish(let text):
            activeFlow = nil
            progressSteps = []
            reply(text)
        }
    }

    // MARK: - Photos

    /// Runs a photo through the chosen mode, speaks the result, and keeps the photo in the conversation.
    /// sampleDescription is the canned description for the bundled sample photos.
    func analyze(_ image: UIImage, purpose: CapturePurpose, sampleDescription: String? = nil) {
        cancelCurrentTurn()
        let id = turn
        appendMessage(.user, purpose.prompt, image: image, contextNote: makeContext().note)
        state = .thinking
        let ai = makeAIService()
        streamTask = Task { [weak self] in
            guard let self else { return }
            let answer = await self.answerPhoto(image, purpose: purpose, sampleDescription: sampleDescription, ai: ai)
            guard id == self.turn else { return }
            self.imageNote = sampleDescription ?? answer
            self.history.add(kind: purpose.historyKind, summary: answer)
            self.reply(answer)
        }
    }

    private func answerPhoto(_ image: UIImage, purpose: CapturePurpose, sampleDescription: String?, ai: any AIService) async -> String {
        switch purpose {
        case .describe:
            if let sampleDescription { return sampleDescription }
            return (try? await ai.describeImage(image, question: nil)) ?? "I could not describe that photo. Please try again."
        case .readText:
            let text = await TextReader.read(image)
            return text.isEmpty
                ? "I cannot see any text. Try moving closer and holding the camera still."
                : "The text says: \(text)"
        case .scanDocument:
            let text = await TextReader.read(image)
            guard !text.isEmpty else {
                return "I cannot see any text on this document. Try more light and hold the camera flat above the page."
            }
            let summary = try? await ai.answer(
                question: "Summarize this document in two or three short spoken sentences. Say what it is, who it is from if known, and what the reader needs to do, including any dates or amounts.",
                context: text
            )
            return (summary ?? "Here is what it says: \(text)") + " Say read it all to hear every word."
        case .identifyColor:
            return ColorIdentifier.describe(image)
        case .findObject(let target):
            return (try? await ai.describeImage(image, question: "Where is \(target)? Answer with left, right, centre, and near or far.")) ?? "I could not look for that. Please try again."
        }
    }

    // MARK: - Listening callbacks

    private func handlePartial(_ text: String) {
        partialText = text
        guard state != .idle else { return }
        idleTask?.cancel()
        // Barge-in while ECHO speaks, only on headphones or AirPods: on the phone's speaker the
        // microphone would hear ECHO's own voice. Tapping, Stop, and shaking always work.
        guard state == .speaking, AudioSession.hasPrivateOutputRoute else { return }
        if text.split(separator: " ").count >= 2 {
            interrupt()
        }
    }

    private func handleUtterance(_ text: String) {
        partialText = ""
        switch state {
        case .listening:
            process(text)
        case .thinking:
            // The user added something while ECHO was still working: start over with the new request.
            cancelCurrentTurn()
            process(text)
        case .speaking, .idle:
            break
        }
    }

    // MARK: - Turn handling

    private func process(_ text: String) {
        appendMessage(.user, text, contextNote: makeContext().note)
        let mode: RoutingMode = makeAIService() is MockAIService ? .offline : .liveAI
        let command = commandRouter.route(text, mode: mode)

        if !isReaderCommand(command) {
            actions.stopReading()
        }

        // 1. An approval is waiting: yes runs it, no cancels, "change" starts over, anything else is a new request.
        if pendingApproval != nil {
            switch command {
            case .control(.yes):
                approve()
                return
            case .control(.no), .control(.stop):
                cancelApproval()
                return
            default:
                if Self.isChangeRequest(text) {
                    changeApproval()
                    return
                }
                let onCancel = approvalCancelled
                clearApproval()
                activeFlow = nil
                toolLoop = nil
                progressSteps = []
                onCancel?()
            }
        }

        // 2. A guided dialog is running: it gets the reply, unless the user is backing out.
        if let flow = activeFlow {
            if command == .control(.stop) || command == .control(.no) {
                activeFlow = nil
                progressSteps = []
                reply("Okay, cancelled.")
                return
            }
            cancelCurrentTurn()
            let id = turn
            state = .thinking
            streamTask = Task { [weak self] in
                guard let self else { return }
                let step = await flow.handle(text)
                guard id == self.turn else { return }
                self.apply(step)
            }
            return
        }

        // 3. Normal conversation.
        switch command {
        case .control(let control):
            handle(control)
        case .action(let action):
            request(action)
        case .unknown:
            askAI(depth: 0)
        }
    }

    private static func isChangeRequest(_ text: String) -> Bool {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return ["change", "change details", "change that", "change it", "edit", "edit that", "thats wrong", "that's wrong"].contains(lowered)
    }

    private func isReaderCommand(_ command: VoiceCommand) -> Bool {
        switch command {
        case .control(.pause), .control(.resume), .control(.skip): return true
        default: return false
        }
    }

    private func handle(_ command: ControlCommand) {
        switch command {
        case .stop:
            stopEverything(announce: "Stopped.")
        case .repeatLast:
            reply(lastAnswer.isEmpty ? "There is nothing to repeat yet." : lastAnswer)
        case .saySlower:
            reply(lastAnswer.isEmpty ? "There is nothing to repeat yet." : lastAnswer, rateScale: 0.8)
        case .sayShorter:
            askAI(depth: 0)
        case .help:
            reply(VoiceCommandRouter.helpText)
        case .goHome:
            actions.goHome()
            // The Home screen announces itself when it appears; in voice-only mode nothing appears.
            if settings.interfaceMode == .voiceOnly { reply("Home.") } else { finishSilently() }
        case .goBack:
            actions.goBack()
            if settings.interfaceMode == .voiceOnly { reply("Going back.") } else { finishSilently() }
        case .pause:
            if actions.readerStatus == .reading {
                actions.pauseReading()
                reply("Paused. Say resume to continue.")
            } else {
                reply("Nothing is being read right now.")
            }
        case .resume:
            if actions.readerStatus == .paused {
                actions.resumeReading()
                finishSilently()
            } else {
                reply("There is nothing paused to resume.")
            }
        case .skip:
            if actions.readerStatus == .reading {
                actions.skipChunk()
                finishSilently()
            } else {
                reply("Nothing is being read right now.")
            }
        case .yes, .no:
            askAI(depth: 0)
        }
    }

    /// Runs an action, or stops at an approval request first when it has consequences.
    private func request(_ action: AssistantAction) {
        guard action.needsApproval else {
            run(action)
            return
        }
        cancelCurrentTurn()
        let id = turn
        state = .thinking
        streamTask = Task { [weak self] in
            guard let self else { return }
            let approval = await self.actions.approvalRequest(for: action)
            guard id == self.turn else { return }
            self.present(approval) { [weak self] in
                await self?.actions.perform(action) ?? ""
            }
        }
    }

    private func run(_ action: AssistantAction) {
        if let flow = actions.flow(for: action) {
            startFlow(flow.flow, steps: flow.steps)
            return
        }
        cancelCurrentTurn()
        let id = turn
        state = .thinking
        streamTask = Task { [weak self] in
            guard let self else { return }
            let text = await self.actions.perform(action)
            guard id == self.turn else { return }
            if text.isEmpty {
                self.finishTurn(id)
            } else {
                self.reply(text)
            }
        }
    }

    private func present(_ request: ApprovalRequest, run: @escaping () async -> String, onCancel: (() -> Void)? = nil) {
        pendingApproval = request
        approvedRun = run
        approvalCancelled = onCancel
        haptics.success()
        reply(request.spokenText)
    }

    private func clearApproval() {
        pendingApproval = nil
        approvedRun = nil
        approvalCancelled = nil
    }

    private func runApproved(_ request: ApprovalRequest, _ run: @escaping () async -> String) {
        cancelCurrentTurn()
        let id = turn
        state = .thinking
        streamTask = Task { [weak self] in
            guard let self else { return }
            if request.requiresBiometric {
                let outcome = await BiometricGate.verify(reason: request.title)
                guard id == self.turn else { return }
                switch outcome {
                case .passed:
                    break
                case .failed:
                    self.haptics.error()
                    self.toolLoop = nil
                    self.reply("Face ID did not pass, so I did not continue.")
                    return
                case .unavailable:
                    self.haptics.error()
                    self.toolLoop = nil
                    self.reply("This step needs Face ID or a passcode, and none is set up on this phone, so I did not continue.")
                    return
                }
            }
            let text = await run()
            guard id == self.turn else { return }
            self.progressSteps = []
            self.haptics.success()
            self.afterApprovedAction(spoken: text)
        }
    }

    /// After an approved action: offer the emergency follow-up text, continue a tool loop, or just speak.
    private func afterApprovedAction(spoken text: String) {
        if let followUp = actions.emergencyFollowUp {
            let speakFirst = text
            present(followUp, run: { [weak self] in
                self?.actions.runEmergencyFollowUp() ?? ""
            }, onCancel: { [weak self] in
                self?.actions.cancelEmergencyFollowUp()
            })
            if !speakFirst.isEmpty {
                // Say what happened before reading the follow-up request.
                let request = followUp
                reply("\(speakFirst) \(request.spokenText)")
            }
            return
        }
        if toolLoop != nil {
            resumeToolLoop()
            return
        }
        if text.isEmpty {
            finishSilently()
        } else {
            reply(text)
        }
    }

    /// Speaks a fixed reply without calling the AI.
    private func reply(_ text: String, rateScale: Float = 1) {
        cancelCurrentTurn()
        let id = turn
        appendMessage(.assistant, text)
        lastAnswer = text
        state = .speaking
        speechChain = Task { [weak self] in
            await self?.speechOutput.say(text, rateScale: rateScale)
            self?.finishTurn(id)
        }
    }

    // MARK: - The AI turn

    private func askAI(depth: Int) {
        cancelCurrentTurn()
        let id = turn
        let history = apiHistory()
        let context = makeContext()
        let ai = makeAIService()
        state = .thinking
        streamTask = Task { [weak self] in
            await self?.streamAnswer(id: id, ai: ai, messages: history, context: context, depth: depth)
        }
    }

    private func streamAnswer(id: UUID, ai: any AIService, messages: [ChatMessage], context: AssistantContext, depth: Int) async {
        let replyID = appendMessage(.assistant, "")
        // Demo answers are not the live model's words, so only live replies are marked as the model's.
        if !(ai is MockAIService), let index = transcript.firstIndex(where: { $0.id == replyID }) {
            transcript[index].isFromModel = true
        }
        var answer = ""
        var chunker = SentenceChunker()
        var toolCalls: [ToolCall] = []
        var rawContent: String?
        var stopReason: String?
        var spokenStatuses: Set<String> = []

        do {
            for try await event in ai.chat(messages: messages, context: context) {
                guard id == turn else { return }
                switch event {
                case .text(let piece):
                    answer += piece
                    updateMessage(replyID, text: answer)
                    for sentence in chunker.append(piece) {
                        speakSentence(sentence, turn: id)
                    }
                case .toolCall(let call):
                    toolCalls.append(call)
                case .status(let status):
                    // Said once per turn, so a long web search is never silent.
                    if !spokenStatuses.contains(status) {
                        spokenStatuses.insert(status)
                        speakSentence(status, turn: id)
                    }
                case .done(let raw, let reason):
                    rawContent = raw
                    stopReason = reason
                }
            }
            guard id == turn else { return }
            for sentence in chunker.finish() {
                speakSentence(sentence, turn: id)
            }
        } catch {
            guard id == turn else { return }
            removeMessage(replyID)
            if ai is MockAIService {
                speakSentence("Sorry, I could not finish that answer. Please try again.", turn: id)
            } else {
                // Live AI failed: say why in one short sentence, then answer from the offline demo for this turn.
                let reason = (error as? RemoteAIError)?.spokenDescription ?? "I could not reach the live assistant."
                speakSentence("\(reason) Here is a demo answer instead.", turn: id)
                await streamAnswer(id: id, ai: fallbackAI, messages: messages, context: context, depth: Self.maxToolDepth)
                return
            }
        }

        guard id == turn else { return }
        setMessageMeta(replyID, toolCalls: toolCalls, rawContentJSON: rawContent)
        if answer.isEmpty && toolCalls.isEmpty && rawContent == nil {
            removeMessage(replyID)
        }
        if !answer.isEmpty {
            lastAnswer = answer
        }
        if stopReason == "refusal" && answer.isEmpty {
            speakSentence("I am not able to help with that one.", turn: id)
        } else if stopReason == "max_tokens" {
            speakSentence("I had to stop there. Ask me to continue if you want more.", turn: id)
        }

        let chain = speechChain
        await chain?.value
        guard id == turn else { return }

        if !toolCalls.isEmpty && depth < Self.maxToolDepth {
            toolLoop = ToolLoop(remaining: toolCalls, results: [], depth: depth)
            resumeToolLoop()
        } else if stopReason == "pause_turn" && depth < Self.maxToolDepth {
            // A long web search paused on the server: send the turn back as it is and let it continue.
            askAI(depth: depth + 1)
        } else {
            finishTurn(id)
        }
    }

    /// Runs the next tool calls. Stops to wait at approvals and hands over to guided dialogs.
    private func resumeToolLoop() {
        guard toolLoop != nil else { return }
        cancelCurrentTurn()
        let id = turn
        state = .thinking
        streamTask = Task { [weak self] in
            await self?.runToolLoop(id)
        }
    }

    private func runToolLoop(_ id: UUID) async {
        while var loop = toolLoop, let call = loop.remaining.first {
            loop.remaining.removeFirst()
            toolLoop = loop

            guard let action = call.action else {
                toolLoop?.needsNarration = true
                record(ToolResult(toolUseID: call.id, content: "That tool is not available in this app.", isError: true))
                continue
            }

            if action.needsApproval {
                let approval = await actions.approvalRequest(for: action)
                guard id == turn else { return }
                present(approval, run: { [weak self] in
                    guard let self else { return "" }
                    let text = await self.actions.perform(action)
                    self.toolLoop?.needsNarration = true
                    self.record(ToolResult(toolUseID: call.id, content: text.isEmpty ? "Done." : text, isError: false))
                    return ""
                }, onCancel: { [weak self] in
                    self?.toolLoop?.needsNarration = true
                    self?.record(ToolResult(toolUseID: call.id, content: "The user declined, so nothing was done. Acknowledge briefly and do not try again.", isError: false))
                })
                return // Waiting for the user; the loop resumes after they decide.
            }

            if let flow = actions.flow(for: action) {
                record(ToolResult(toolUseID: call.id, content: "The app started a guided dialog with the user and will finish it. Do not say anything more.", isError: false))
                if let finished = toolLoop {
                    appendToolResults(finished.results)
                }
                toolLoop = nil
                startFlow(flow.flow, steps: flow.steps)
                return
            }

            let text = await actions.perform(action)
            guard id == turn else { return }
            if text.isEmpty {
                // The feature speaks for itself (camera, a screen opening, reading a page): no narration on top.
                record(ToolResult(toolUseID: call.id, content: "Done. The app is handling this and speaks to the user itself.", isError: false))
            } else {
                toolLoop?.needsNarration = true
                record(ToolResult(toolUseID: call.id, content: text, isError: false))
            }
        }

        guard id == turn, let finished = toolLoop else { return }
        toolLoop = nil
        appendToolResults(finished.results)
        if finished.needsNarration {
            askAI(depth: finished.depth + 1)
        } else {
            finishTurn(id)
        }
    }

    private func record(_ result: ToolResult) {
        toolLoop?.results.append(result)
    }

    /// Adds the tool results as a hidden user message, so the model sees what happened.
    private func appendToolResults(_ results: [ToolResult]) {
        guard !results.isEmpty else { return }
        var message = ChatMessage(role: .user, text: "")
        message.toolResults = results
        transcript.append(message)
    }

    private func speakSentence(_ sentence: String, turn id: UUID) {
        guard id == turn else { return }
        state = .speaking
        let previous = speechChain
        speechChain = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, id == self.turn else { return }
            await self.speechOutput.say(sentence)
        }
    }

    private func finishTurn(_ id: UUID) {
        guard id == turn else { return }
        if listener.isRunning {
            state = .listening
            resetIdleTimer()
        } else {
            state = .idle
        }
    }

    /// Ends a turn that produced no speech of its own (for example, resume or skip).
    private func finishSilently() {
        finishTurn(turn)
    }

    /// Cancels the reply in progress: stops the stream, the queued speech, and the voice.
    private func cancelCurrentTurn() {
        turn = UUID()
        streamTask?.cancel()
        streamTask = nil
        speechChain?.cancel()
        speechChain = nil
        speechOutput.stop()
        partialText = ""
    }

    private func resetIdleTimer() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard !Task.isCancelled, let self, self.state == .listening else { return }
            self.stopEverything(announce: "I have stopped listening. Tap the microphone to talk again.")
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        haptics.error()
        listener.stop()
        state = .idle
        Task { await speechOutput.say(message) }
    }

    // MARK: - Transcript and context

    @discardableResult
    private func appendMessage(_ role: ChatRole, _ text: String, image: UIImage? = nil, contextNote: String? = nil) -> UUID {
        let message = ChatMessage(role: role, text: text, image: image, contextNote: contextNote)
        transcript.append(message)
        if transcript.count > 200 {
            transcript.removeFirst(transcript.count - 200)
        }
        return message.id
    }

    private func updateMessage(_ id: UUID, text: String) {
        guard let index = transcript.firstIndex(where: { $0.id == id }) else { return }
        transcript[index].text = text
    }

    private func setMessageMeta(_ id: UUID, toolCalls: [ToolCall], rawContentJSON: String?) {
        guard let index = transcript.firstIndex(where: { $0.id == id }) else { return }
        transcript[index].toolCalls = toolCalls
        transcript[index].rawContentJSON = rawContentJSON
    }

    private func removeMessage(_ id: UUID) {
        transcript.removeAll { $0.id == id }
    }

    /// The last 20 messages that carry something for the model: words, tool calls, or tool results.
    private func apiHistory() -> [ChatMessage] {
        let meaningful = transcript.filter { !$0.text.isEmpty || !$0.toolResults.isEmpty || $0.rawContentJSON != nil }
        return Array(meaningful.suffix(20))
    }

    private func makeContext() -> AssistantContext {
        AssistantContext(
            screenName: actions.currentScreenName,
            timeOfDay: Self.timeOfDay(),
            simpleMode: settings.simpleMode,
            detailedAnswers: settings.detailedAnswers,
            location: actions.lastKnownLocation,
            imageNote: imageNote,
            webPage: actions.lastWebSnapshot
        )
    }

    private func stateChanged(from old: ConversationState) {
        guard state != old else { return }
        switch state {
        case .listening:
            listener.unmute()
            if old == .idle { haptics.listeningStarted() }
        case .thinking:
            haptics.thinking()
        case .speaking:
            // The microphone stays open for barge-in, but nothing it hears becomes a request.
            listener.mute()
        case .idle:
            if old != .idle { haptics.listeningStopped() }
        }
    }

    private static func timeOfDay() -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<22: return "evening"
        default: return "night"
        }
    }
}
