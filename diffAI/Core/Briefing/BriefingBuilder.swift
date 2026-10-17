import Foundation

/// Builds the spoken daily briefing: greeting, day and time, weather, today's reminders, unread messages.
/// Plain sentences only, so it reads well through VoiceOver or the app voice.
enum BriefingBuilder {
    static func build(
        timeOfDay: String,
        reminders: [Reminder],
        unreadCount: Int,
        weather: String,
        now: Date = Date()
    ) -> String {
        var sentences: [String] = []

        sentences.append(greeting(for: timeOfDay))

        let weekday = now.formatted(Date.FormatStyle().weekday(.wide))
        let time = now.formatted(Date.FormatStyle(date: .omitted, time: .shortened))
        sentences.append("It is \(weekday), \(time).")

        let weatherText = weather.trimmingCharacters(in: .whitespacesAndNewlines)
        if !weatherText.isEmpty {
            sentences.append("The weather is \(stripTrailingPeriod(weatherText)).")
        }

        sentences.append(reminderSentence(reminders, now: now))
        sentences.append(contentsOf: messageSentences(unreadCount))

        return sentences.joined(separator: " ")
    }

    // MARK: - Pieces

    private static func greeting(for timeOfDay: String) -> String {
        switch timeOfDay.lowercased() {
        case "morning": return "Good morning."
        case "afternoon": return "Good afternoon."
        case "evening": return "Good evening."
        case "night": return "Hello. It is late."
        default: return "Hello."
        }
    }

    private static func reminderSentence(_ reminders: [Reminder], now: Date) -> String {
        let items = reminders.sorted { timeOfDayMinutes($0.date) < timeOfDayMinutes($1.date) }
        switch items.count {
        case 0:
            return "You have no reminders today."
        case 1:
            return "You have one reminder today: \(describe(items[0]))."
        default:
            let described = items.map { describe($0) }
            let list = described.dropLast().joined(separator: ", ") + ", and " + (described.last ?? "")
            return "You have \(numberWord(items.count)) reminders today: \(list)."
        }
    }

    private static func messageSentences(_ unreadCount: Int) -> [String] {
        switch unreadCount {
        case ..<1:
            return ["You have no unread messages."]
        case 1:
            return ["You have one unread message. Say read my messages to hear it."]
        default:
            return ["You have \(unreadCount) unread messages. Say read my messages to hear them."]
        }
    }

    /// "take your pills at 8 PM"
    private static func describe(_ reminder: Reminder) -> String {
        var title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = title.first {
            title = first.lowercased() + title.dropFirst()
        }
        return "\(title) at \(ReminderFlow.spokenTime(reminder.date))"
    }

    private static func timeOfDayMinutes(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func numberWord(_ count: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return count >= 0 && count < words.count ? words[count] : String(count)
    }

    private static func stripTrailingPeriod(_ text: String) -> String {
        text.hasSuffix(".") ? String(text.dropLast()) : text
    }
}
