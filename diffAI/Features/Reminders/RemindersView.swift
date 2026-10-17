import SwiftUI

/// Reminders screen: add by voice, add by hand, and a list where every row is one spoken element.
struct RemindersView: View {
    @EnvironmentObject private var store: ReminderStore
    @EnvironmentObject private var conversation: ConversationEngine
    @EnvironmentObject private var speechOutput: SpeechOutputCoordinator

    @State private var showManualEntry = false
    @State private var newTitle = ""
    @State private var newDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var newRepeatsDaily = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        List {
            Section {
                Button {
                    addByVoice()
                } label: {
                    Label("Add by voice", systemImage: "mic.fill")
                        .labelStyle(BigLabelStyle())
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityLabel("Add by voice")
                .accessibilityHint("Starts listening. Say remind me to, then what and when.")

                Button {
                    withAnimation { showManualEntry.toggle() }
                } label: {
                    HStack {
                        Label("Add by hand", systemImage: "square.and.pencil")
                            .labelStyle(BigLabelStyle())
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Image(systemName: showManualEntry ? "chevron.up" : "chevron.down")
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Add by hand")
                .accessibilityValue(showManualEntry ? "Expanded" : "Collapsed")
                .accessibilityHint("Shows fields to type a reminder and pick a time")

                if showManualEntry {
                    manualEntry
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))

            Section {
                if store.reminders.isEmpty {
                    Text("No reminders yet. Add one by voice or by hand.")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTapHeight, alignment: .leading)
                } else {
                    ForEach(store.reminders) { reminder in
                        ReminderRow(reminder: reminder) {
                            delete(reminder)
                        }
                    }
                    .onDelete(perform: deleteRows)
                }
            } header: {
                Text("Your reminders")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .textCase(nil)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Reminders")
        .onAppear {
            Task { await speechOutput.announceScreen(AppScreen.reminders.announcement) }
        }
    }

    // MARK: - Manual entry

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("What should I remind you about?", text: $newTitle)
                .font(.title3)
                .textInputAutocapitalization(.sentences)
                .focused($titleFocused)
                .submitLabel(.done)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                )
                .accessibilityLabel("Reminder title")
                .accessibilityHint("Type what to remind you about")

            DatePicker("When", selection: $newDate, displayedComponents: [.date, .hourAndMinute])
                .font(.title3)
                .frame(minHeight: Theme.minTapHeight)
                .accessibilityLabel("When")
                .accessibilityHint("Pick the date and time for the reminder")

            Toggle("Every day", isOn: $newRepeatsDaily)
                .font(.title3)
                .frame(minHeight: Theme.minTapHeight)
                .accessibilityLabel("Every day")
                .accessibilityHint("Repeats the reminder at the same time each day")

            Button {
                addByHand()
            } label: {
                Text("Add reminder")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityLabel("Add reminder")
            .accessibilityHint("Saves the reminder with the title and time above")
        }
        .card()
    }

    // MARK: - Actions

    private func addByVoice() {
        Task { await speechOutput.say("Say: remind me to, then what and when.") }
        conversation.beginListening()
    }

    private func addByHand() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            titleFocused = true
            Task { await speechOutput.say("Please type what I should remind you about first.") }
            return
        }
        let date = newDate
        let repeats = newRepeatsDaily
        titleFocused = false
        Task {
            let allowed = await store.add(title: title, date: date, repeatsDaily: repeats)
            var sentence = "Added. I will remind you to \(spokenTitle(title)) \(ReminderFlow.spokenWhen(date, repeatsDaily: repeats))."
            if !allowed {
                sentence += " Notifications are off for ECHO, so I will only show it in the app."
            }
            newTitle = ""
            newRepeatsDaily = false
            withAnimation { showManualEntry = false }
            await speechOutput.say(sentence)
        }
    }

    private func deleteRows(at offsets: IndexSet) {
        let items = offsets.compactMap { store.reminders.indices.contains($0) ? store.reminders[$0] : nil }
        for item in items {
            delete(item)
        }
    }

    private func delete(_ reminder: Reminder) {
        store.remove(reminder)
        Task { await speechOutput.say("Deleted \(spokenTitle(reminder.title)).") }
    }

    private func spokenTitle(_ title: String) -> String {
        guard let first = title.first else { return title }
        return first.lowercased() + title.dropFirst()
    }
}

/// One reminder. Read by VoiceOver as a single element: "Take your pills, 8:00 PM, every day".
private struct ReminderRow: View {
    let reminder: Reminder
    let onDelete: () -> Void

    private var timeText: String {
        reminder.date.formatted(date: .omitted, time: .shortened)
    }

    private var whenText: String {
        if reminder.repeatsDaily {
            return "\(timeText), every day"
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(reminder.date) {
            return "Today, \(timeText)"
        }
        if calendar.isDateInTomorrow(reminder.date) {
            return "Tomorrow, \(timeText)"
        }
        return "\(reminder.date.formatted(date: .abbreviated, time: .omitted)), \(timeText)"
    }

    private var spokenLabel: String {
        if reminder.repeatsDaily {
            return "\(reminder.title), \(timeText), every day"
        }
        return "\(reminder.title), \(whenText)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconTile(systemName: reminder.repeatsDaily ? "repeat" : "bell.fill", color: Color(.systemOrange))
            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(whenText)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.minTapHeight, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint("Swipe up or down for actions, including Delete")
        .accessibilityAction(named: "Delete") {
            onDelete()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityLabel("Delete")
            .accessibilityHint("Deletes this reminder")
        }
    }
}
