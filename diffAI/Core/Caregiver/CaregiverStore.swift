import Combine
import Foundation
import UIKit

/// One line on the caregiver dashboard, e.g. "Morning medication confirmed".
struct CaregiverEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let event: String
}

/// Demo caregiver dashboard data, saved as JSON in Application Support.
/// Everything here is sample content; the banner on the screen says so.
@MainActor
final class CaregiverStore: ObservableObject {
    static let limit = 50

    /// Newest first.
    @Published private(set) var activity: [CaregiverEntry] = []
    private let fileURL: URL

    var adherenceText: String { DemoData.caregiverAdherence }
    var lastLocationText: String { DemoData.caregiverLastLocation }

    init() {
        let folder = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        fileURL = folder.appendingPathComponent("echo-caregiver.json")
        if !load() {
            seed()
        }
    }

    /// Adds an event at the top of the list.
    func log(_ event: String) {
        activity.insert(CaregiverEntry(id: UUID(), date: Date(), event: event), at: 0)
        activity = Array(activity.prefix(Self.limit))
        save()
    }

    /// Logs the check-in and opens Messages with the text filled in. The user must tap Send.
    /// Returns the sentence to speak. On the Simulator `sms:` cannot be opened; we say so instead of crashing.
    func sendCheckIn(to phone: String) -> String {
        log("Check-in sent")
        let name = DemoData.emergencyContact?.name ?? "your caregiver"
        guard let url = EmergencyService.smsURL(phone: phone, body: "Checking in from ECHO: I'm okay."),
              UIApplication.shared.canOpenURL(url) else {
            return "I noted your check-in, but texts are not available on this device."
        }
        ExternalApp.open(url)
        return "Messages is opening with a check-in to \(name). Tap Send there to send it."
    }

    /// Throws away saved activity and puts the demo entries back.
    func resetDemoData() {
        seed()
    }

    // MARK: - Seeding

    private func seed() {
        let calendar = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"

        let entries: [CaregiverEntry] = DemoData.caregiverActivity.map { seed in
            var date = today
            if let parsed = formatter.date(from: seed.time) {
                let parts = calendar.dateComponents([.hour, .minute], from: parsed)
                date = calendar.date(
                    bySettingHour: parts.hour ?? 0,
                    minute: parts.minute ?? 0,
                    second: 0,
                    of: today
                ) ?? today
            }
            return CaregiverEntry(id: UUID(), date: date, event: seed.event)
        }
        activity = entries.sorted { $0.date > $1.date }
        save()
    }

    // MARK: - Persistence

    /// Returns false when nothing was saved yet, so the caller can seed.
    private func load() -> Bool {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CaregiverEntry].self, from: data) else { return false }
        activity = decoded
        return true
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(activity) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
