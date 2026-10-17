import Combine
import Foundation

struct HistoryItem: Codable, Identifiable {
    let id: UUID
    let date: Date
    let kind: String
    let summary: String
}

/// Keeps the last 20 descriptions and readings, saved as JSON in Application Support.
@MainActor
final class HistoryStore: ObservableObject {
    static let limit = 20

    @Published private(set) var items: [HistoryItem] = []
    private let fileURL: URL

    init() {
        let folder = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        fileURL = folder.appendingPathComponent("sightassist-history.json")
        load()
    }

    func add(kind: String, summary: String) {
        items.insert(HistoryItem(id: UUID(), date: Date(), kind: kind, summary: summary), at: 0)
        items = Array(items.prefix(Self.limit))
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
