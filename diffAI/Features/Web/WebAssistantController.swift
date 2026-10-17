import Combine
import Foundation

enum ReaderStatus: Equatable {
    case none
    case reading
    case paused
}

/// A bundled demo page the user can open by name.
struct WebFavorite: Identifiable {
    /// Name of the bundled HTML file.
    let id: String
    let title: String
    let spokenName: String
}

/// Opens pages, analyses them, runs page actions, and reads the main text aloud in chunks.
@MainActor
final class WebAssistantController: ObservableObject {
    static let favorites: [WebFavorite] = [
        WebFavorite(id: "demo_news", title: "News (demo)", spokenName: "news"),
        WebFavorite(id: "demo_shop", title: "Pharmacy (demo)", spokenName: "pharmacy"),
        WebFavorite(id: "demo_appointment", title: "Appointment form (demo)", spokenName: "appointment"),
        WebFavorite(id: "demo_bank", title: "Bank (demo)", spokenName: "bank"),
    ]

    let store = WebViewStore()
    @Published private(set) var readerStatus: ReaderStatus = .none
    /// The most recent analysis, used by "what can I do here" and follow-up questions.
    private(set) var lastSnapshot: WebPageSnapshot?

    private let speechOutput: SpeechOutputCoordinator
    private var readerChunks: [String] = []
    private var readerIndex = 0
    private var readerID = UUID()

    init(speechOutput: SpeechOutputCoordinator) {
        self.speechOutput = speechOutput
    }

    /// Opens a demo page by name, or a web address. Returns the sentence to speak.
    func open(_ target: String) -> String {
        let clean = target.lowercased().trimmingCharacters(in: .whitespaces)
        if let favorite = Self.favorites.first(where: { clean.contains($0.spokenName) || clean.contains($0.id) }) {
            store.loadLocal(favorite.id)
            return "Opening \(favorite.spokenName)."
        }
        if clean.contains(".") {
            let withoutSpaces = clean.replacingOccurrences(of: " ", with: "")
            let address = withoutSpaces.hasPrefix("http") ? withoutSpaces : "https://" + withoutSpaces
            if let url = URL(string: address) {
                store.load(url)
                return "Opening \(withoutSpaces)."
            }
        }
        return "I do not know a website called \(target). Try news, pharmacy, appointment, or bank, or type a web address."
    }

    /// Analyses the current page. Returns nil if no page is loaded.
    func snapshot() async -> WebPageSnapshot? {
        await store.waitUntilLoaded()
        guard let raw = await store.evaluate(WebPageAnalyzer.script) as? String,
              let data = raw.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(WebPageSnapshot.self, from: data) else {
            return nil
        }
        lastSnapshot = snapshot
        return snapshot
    }

    func click(index: Int) async -> Bool {
        await WebActionRunner(store: store).click(index: index)
    }

    func scroll(down: Bool) async {
        await WebActionRunner(store: store).scroll(down: down)
    }

    func nextHeading() async -> String? {
        await WebActionRunner(store: store).nextHeading()
    }

    func submitForm() async -> Bool {
        await WebActionRunner(store: store).submitForm()
    }

    /// Types dictated text into a field found by label or number. Password fields are refused.
    func type(_ value: String, into target: String) async -> String {
        guard let snapshot = await snapshot() else {
            return "This page is not ready yet. Try again in a moment."
        }
        let fields = snapshot.elements.filter { $0.kind == "field" }
        let clean = target.lowercased()
        let match: WebPageSnapshot.Element?
        if clean.contains("first"), let first = fields.first {
            match = first
        } else {
            match = snapshot.element(matching: target).flatMap { $0.kind == "field" ? $0 : nil }
                ?? fields.first { $0.label.lowercased().contains(clean) }
        }
        guard let field = match else {
            return "I could not find a box called \(target). Say what can I do here to hear the fields."
        }
        if field.type == "password" {
            return "That is a password box. For your safety I will not type passwords. Please type it yourself."
        }
        let typed = await WebActionRunner(store: store).type(value, index: field.index)
        return typed ? "Typed \(value) into \(field.label)." : "I could not type into \(field.label)."
    }

    // MARK: - Reader mode

    /// Reads the text aloud in small chunks that can be paused, resumed, skipped, or stopped.
    func startReading(_ text: String) {
        let body = Self.chunks(from: text)
        guard !body.isEmpty else {
            readerStatus = .none
            Task { await speechOutput.say("There is no text to read on this page.") }
            return
        }
        readerChunks = ["Reading the page. Say pause, resume, skip, or stop."] + body
        readerIndex = 0
        readerStatus = .reading
        playReader()
    }

    func pauseReading() {
        guard readerStatus == .reading else { return }
        readerStatus = .paused
        readerID = UUID() // Stops the loop.
        speechOutput.stop()
        // The interrupted chunk is read again on resume.
        readerIndex = max(0, readerIndex - 1)
    }

    func resumeReading() {
        guard readerStatus == .paused, readerIndex < readerChunks.count else { return }
        readerStatus = .reading
        playReader()
    }

    func skipChunk() {
        guard readerStatus == .reading else { return }
        speechOutput.stop() // The loop moves on to the next chunk.
    }

    func stopReading() {
        guard readerStatus != .none || !readerChunks.isEmpty else { return }
        readerID = UUID()
        readerStatus = .none
        readerChunks = []
        readerIndex = 0
        speechOutput.stop()
    }

    private func playReader() {
        let id = UUID()
        readerID = id
        Task { [weak self] in
            while true {
                guard let self, self.readerID == id, self.readerIndex < self.readerChunks.count else { break }
                let chunk = self.readerChunks[self.readerIndex]
                self.readerIndex += 1
                await self.speechOutput.say(chunk)
            }
            guard let self, self.readerID == id else { return }
            self.readerStatus = .none
        }
    }

    /// Groups the page's sentences into chunks of about three sentences.
    static func chunks(from text: String) -> [String] {
        var chunker = SentenceChunker()
        let sentences = chunker.append(text) + chunker.finish()
        var groups: [String] = []
        var index = 0
        while index < sentences.count {
            let end = min(index + 3, sentences.count)
            groups.append(sentences[index..<end].joined(separator: " "))
            index = end
        }
        return groups
    }
}
