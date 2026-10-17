import Foundation

/// Guided dialog for "remind me to ...". Parses the time from what the user said, and if none is found,
/// asks for one up to two times before giving up and pointing to the Reminders screen.
@MainActor
final class ReminderFlow: DialogFlow {
    private let originalText: String
    private let store: ReminderStore
    private var failedAttempts = 0

    init(text: String, store: ReminderStore) {
        originalText = text
        self.store = store
    }

    func start() async -> DialogStep {
        if let parsed = store.parse(originalText) {
            return await save(parsed)
        }
        failedAttempts = 1
        return .ask("When should I remind you? For example, at 8 PM, or tomorrow at 9.")
    }

    func handle(_ reply: String) async -> DialogStep {
        let combined = originalText + " " + reply
        if let parsed = store.parse(combined) ?? store.parse(reply) {
            return await save(parsed)
        }
        failedAttempts += 1
        if failedAttempts >= 3 {
            return .finish("I could not understand the time. You can add it by hand on the Reminders screen.")
        }
        return .ask("Sorry, I did not catch the time. Say something like at 8 PM, or tomorrow at 9.")
    }

    private func save(_ parsed: ParsedReminder) async -> DialogStep {
        let allowed = await store.add(title: parsed.title, date: parsed.date, repeatsDaily: parsed.repeatsDaily)
        var sentence = "Okay. I will remind you to \(Self.spokenTitle(parsed.title)) \(Self.spokenWhen(parsed.date, repeatsDaily: parsed.repeatsDaily))."
        if !allowed {
            sentence += " Notifications are off for ECHO, so I will only show it in the app."
        }
        return .finish(sentence)
    }

    // MARK: - Spoken formatting

    /// Lowercases the first letter so the title reads naturally mid-sentence.
    private static func spokenTitle(_ title: String) -> String {
        guard let first = title.first else { return title }
        return first.lowercased() + title.dropFirst()
    }

    /// "at 8 PM every day", "today at 6:30 PM", "tomorrow at 9 AM", "on Thursday at 10 AM", or "on October 24 at 9 AM".
    static func spokenWhen(_ date: Date, repeatsDaily: Bool, now: Date = Date()) -> String {
        let time = spokenTime(date)
        if repeatsDaily {
            return "at \(time) every day"
        }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return "today at \(time)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow at \(time)"
        }
        if let weekAhead = calendar.date(byAdding: .day, value: 7, to: now), date < weekAhead {
            let weekday = date.formatted(Date.FormatStyle().weekday(.wide))
            return "on \(weekday) at \(time)"
        }
        let day = date.formatted(Date.FormatStyle().month(.wide).day())
        return "on \(day) at \(time)"
    }

    /// "8 PM" on the hour, otherwise "6:30 PM".
    static func spokenTime(_ date: Date) -> String {
        let minute = Calendar.current.component(.minute, from: date)
        if minute == 0 {
            return date.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)))
        }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened))
    }
}
