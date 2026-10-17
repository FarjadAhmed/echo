import SwiftUI

/// "My Day": a greeting, one button that plays the whole briefing, and a card for each part
/// (weather, reminders, messages, location) that can be heard on its own.
/// Every spoken action goes through the conversation engine, so voice and touch share one path.
struct BriefingView: View {
    @EnvironmentObject private var reminders: ReminderStore
    @EnvironmentObject private var inbox: InboxStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var conversation: ConversationEngine
    @EnvironmentObject private var speechOutput: SpeechOutputCoordinator
    @EnvironmentObject private var settings: AppSettings

    private var today: [Reminder] { reminders.todayItems() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                hero
                playButton
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(text: "Today")
                    weatherCard
                    remindersCard
                    messagesCard
                    locationCard
                }
                Text("Weather is demo data until a weather service is connected.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical)
        }
        .echoBackground()
        .navigationTitle("My Day")
        .onAppear {
            Task { await speechOutput.announceScreen(AppScreen.briefing.announcement) }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playButton: some View {
        Button {
            conversation.submitTyped("play my briefing")
        } label: {
            Label("Play my briefing", systemImage: "play.fill")
                .labelStyle(BigLabelStyle())
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityLabel("Play my briefing")
        .accessibilityHint("Hears the weather, today's reminders and your unread messages")
    }

    // MARK: - Cards

    private var weatherCard: some View {
        BriefingCard(
            title: "Weather",
            detail: "Demo: \(DemoData.weather).",
            systemImage: "cloud.sun.fill",
            tint: Color(.systemBlue),
            playHint: "Hears the weather"
        ) {
            Task { await speechOutput.say("The weather is \(DemoData.weather). This is demo data.", priority: .urgent) }
        }
    }

    private var remindersCard: some View {
        let detail = today.isEmpty
            ? "Nothing scheduled today."
            : today.map { "\($0.title), \(ReminderFlow.spokenWhen($0.date, repeatsDaily: $0.repeatsDaily))" }.joined(separator: ". ")
        return BriefingCard(
            title: today.isEmpty ? "Reminders" : "Reminders, \(today.count) today",
            detail: detail,
            systemImage: "bell.fill",
            tint: Color(.systemOrange),
            playHint: "Hears today's reminders"
        ) {
            let text = today.isEmpty ? "You have no reminders today." : "Today: \(detail)."
            Task { await speechOutput.say(text, priority: .urgent) }
        }
    }

    private var messagesCard: some View {
        let unread = inbox.items.filter { !$0.isRead }
        let detail = unread.isEmpty
            ? "No unread messages."
            : "From " + unread.map(\.sender).joined(separator: ", ") + "."
        return BriefingCard(
            title: unread.isEmpty ? "Messages" : "Messages, \(unread.count) unread",
            detail: detail,
            systemImage: "message.fill",
            tint: Color(.systemGreen),
            playHint: "Reads your unread messages one by one"
        ) {
            conversation.submitTyped("read my messages")
        }
    }

    private var locationCard: some View {
        BriefingCard(
            title: "Where am I?",
            detail: location.lastKnownDescription.map { "Near \($0)." } ?? "Not checked yet.",
            systemImage: "location.fill",
            tint: Color(.systemIndigo),
            playHint: "Finds your location and says the address"
        ) {
            conversation.submitTyped("where am i")
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }
}

/// One row of the briefing: symbol, title, detail, and a play button. The row itself is one VoiceOver
/// element that reads everything; its default action and the play button both speak the part.
private struct BriefingCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let playHint: String
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            HStack(spacing: 14) {
                IconTile(systemName: systemImage, color: tint, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "play.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityHint(playHint)
    }
}
