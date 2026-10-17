import Combine
import Foundation
import UserNotifications

/// One reminder. `date` is the next time it fires; daily reminders repeat at that hour and minute.
struct Reminder: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var date: Date
    var repeatsDaily: Bool
}

/// What `ReminderStore.parse` understood from a spoken sentence.
struct ParsedReminder: Equatable {
    let title: String
    let date: Date
    let repeatsDaily: Bool
}

/// Keeps the user's reminders as JSON in Application Support and schedules a local notification for each one.
/// Seeded from `DemoData.reminders` on first launch.
@MainActor
final class ReminderStore: ObservableObject {
    @Published private(set) var reminders: [Reminder] = []

    private let fileURL: URL
    private let center = UNUserNotificationCenter.current()

    init() {
        let folder = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        fileURL = folder.appendingPathComponent("sightassist-reminders.json")
        if !load() {
            reminders = Self.demoReminders()
            save()
        }
    }

    // MARK: - Adding and removing

    /// Saves the reminder and schedules its notification.
    /// Returns false when notifications are not allowed; the reminder is still kept and shown in the app.
    @discardableResult
    func add(title: String, date: Date, repeatsDaily: Bool) async -> Bool {
        let reminder = Reminder(
            id: UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            repeatsDaily: repeatsDaily
        )
        reminders.append(reminder)
        sortAndSave()

        let allowed = await ensureNotificationPermission()
        if allowed {
            await schedule(reminder)
        }
        return allowed
    }

    /// Deletes the reminder and cancels its pending notification.
    func remove(_ reminder: Reminder) {
        reminders.removeAll { $0.id == reminder.id }
        sortAndSave()
        center.removePendingNotificationRequests(withIdentifiers: [reminder.id.uuidString])
    }

    /// Reminders that fire today: daily ones always, one-off ones only when their date is today.
    func todayItems(now: Date = Date()) -> [Reminder] {
        let calendar = Calendar.current
        return reminders.filter { reminder in
            reminder.repeatsDaily || calendar.isDate(reminder.date, inSameDayAs: now)
        }
    }

    /// Replaces everything with the demo reminders, each at its next occurrence, and reschedules them.
    func resetDemoData() {
        center.removePendingNotificationRequests(withIdentifiers: reminders.map(\.id.uuidString))
        reminders = Self.demoReminders()
        save()
        Task { [weak self] in
            guard let self else { return }
            guard await self.ensureNotificationPermission() else { return }
            for reminder in self.reminders {
                await self.schedule(reminder)
            }
        }
    }

    // MARK: - Parsing spoken requests

    private static let repeatPhrases = ["every day", "everyday", "each day", "daily", "every morning", "every evening", "every night"]
    private static let leadInPhrases = [
        "please remind me to", "please remind me about", "please remind me",
        "remind me to", "remind me about", "remind me that", "remind me",
        "set a reminder to", "set a reminder for", "set a reminder", "set reminder",
        "add a reminder to", "add a reminder for", "add a reminder", "new reminder",
    ]

    /// Finds the time in a sentence such as "remind me to take my pills at 8 PM every day".
    /// Returns nil when no date or time was found.
    func parse(_ text: String, now: Date = Date()) -> ParsedReminder? {
        let trimmed = Self.normalizeBareHours(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        let repeatsDaily = Self.repeatPhrases.contains { lower.contains($0) }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let whole = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = detector.firstMatch(in: trimmed, options: [], range: whole),
              var date = match.date,
              let matchRange = Range(match.range, in: trimmed) else {
            return nil
        }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        if !Self.mentionsTime(lower) {
            // A date without a time. Use nine in the morning.
            components.hour = 9
            components.minute = 0
        }
        components.second = 0
        date = calendar.date(from: components) ?? date

        if date <= now {
            date = Self.nextOccurrence(of: date, after: now)
        }

        var titleSource = trimmed
        titleSource.removeSubrange(matchRange)
        let title = Self.cleanTitle(titleSource)
        let finalTitle = title.isEmpty ? "Reminder" : title

        return ParsedReminder(title: finalTitle, date: date, repeatsDaily: repeatsDaily)
    }

    /// Turns "at 8" into "at 8 PM" and "at 9 in the morning" into "at 9 AM", so the detector finds the time.
    /// Without a qualifier, 1 to 7 are taken as evening, 8 to 11 as morning, 12 as noon.
    static func normalizeBareHours(_ text: String) -> String {
        let pattern = #"(?i)\bat\s+(\d{1,2})(?::(\d{2}))?(?!\s*(?::|\d|am|pm|a\.m|p\.m|o'clock|oclock))\b(\s+(?:in\s+the\s+morning|in\s+the\s+afternoon|in\s+the\s+evening|at\s+night|tonight))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        var result = text
        // Replace from the end so earlier ranges stay valid.
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).reversed() {
            guard let hour = Int(nsText.substring(with: match.range(at: 1))), (1...12).contains(hour) else { continue }
            let minute = match.range(at: 2).location == NSNotFound ? "00" : nsText.substring(with: match.range(at: 2))
            let qualifier = match.range(at: 3).location == NSNotFound ? "" : nsText.substring(with: match.range(at: 3)).lowercased()
            let isMorning: Bool
            if qualifier.contains("morning") {
                isMorning = true
            } else if !qualifier.isEmpty {
                isMorning = false
            } else {
                isMorning = (8...11).contains(hour)
            }
            let replacement = "at \(hour):\(minute) \(isMorning ? "AM" : "PM")"
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }

    /// True when the sentence contains an explicit clock time or part of day.
    private static func mentionsTime(_ lower: String) -> Bool {
        let pattern = #"(\d{1,2}:\d{2})|(\b\d{1,2}\s*(am|pm|a\.m\.|p\.m\.|o'clock|oclock)\b)|\b(noon|midnight|morning|afternoon|evening|night|tonight)\b|\bat\s+\d{1,2}\b"#
        return lower.range(of: pattern, options: .regularExpression) != nil
    }

    /// Moves a past date forward one day at a time until it is in the future.
    private static func nextOccurrence(of date: Date, after now: Date) -> Date {
        let calendar = Calendar.current
        var candidate = date
        var guardCount = 0
        while candidate <= now, guardCount < 400 {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate.addingTimeInterval(86_400)
            guardCount += 1
        }
        return candidate
    }

    /// Removes lead-ins ("remind me to"), repeat phrases, and stray connecting words.
    private static func cleanTitle(_ source: String) -> String {
        var result = source
        for phrase in leadInPhrases + repeatPhrases {
            result = result.replacingOccurrences(of: phrase, with: " ", options: [.caseInsensitive])
        }
        result = result.replacingOccurrences(of: "[,.;!?]", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let strayWords: Set<String> = ["at", "on", "to", "for", "in", "the", "and", "then", "that", "about", "by"]
        var words = result.split(separator: " ").map(String.init)
        while let last = words.last, strayWords.contains(last.lowercased()) {
            words.removeLast()
        }
        while let first = words.first, strayWords.contains(first.lowercased()), first.lowercased() != "the" {
            words.removeFirst()
        }
        var title = words.joined(separator: " ")
        if let first = title.first {
            title = first.uppercased() + title.dropFirst()
        }
        return title
    }

    // MARK: - Notifications

    private func ensureNotificationPermission() async -> Bool {
        #if DEBUG
        // The automated live self-test cannot tap the system permission alert.
        if LiveSelfTest.isRunning { return false }
        #endif
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    private func schedule(_ reminder: Reminder) async {
        let content = UNMutableNotificationContent()
        content.title = "ECHO reminder"
        content.body = reminder.title
        content.sound = .default

        let calendar = Calendar.current
        let components: DateComponents
        if reminder.repeatsDaily {
            components = calendar.dateComponents([.hour, .minute], from: reminder.date)
        } else {
            components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
        }
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: reminder.repeatsDaily)
        let request = UNNotificationRequest(identifier: reminder.id.uuidString, content: content, trigger: trigger)
        try? await center.add(request)
    }

    // MARK: - Persistence

    private static func demoReminders(now: Date = Date()) -> [Reminder] {
        let calendar = Calendar.current
        return DemoData.reminders.compactMap { seed in
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = seed.hour
            components.minute = seed.minute
            components.second = 0
            guard var date = calendar.date(from: components) else { return nil }
            if date <= now {
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            }
            return Reminder(id: UUID(), title: seed.title, date: date, repeatsDaily: seed.repeatsDaily)
        }
        .sorted { $0.date < $1.date }
    }

    /// Returns false when there is no saved file yet.
    private func load() -> Bool {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Reminder].self, from: data) else { return false }
        reminders = decoded.sorted { $0.date < $1.date }
        return true
    }

    private func sortAndSave() {
        reminders.sort { $0.date < $1.date }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
