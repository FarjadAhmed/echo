import SwiftUI

/// Caregiver dashboard: demo activity, medication adherence and last known location, plus a check-in button.
/// The button goes through the conversation engine so voice and touch share one path.
struct CaregiverView: View {
    @EnvironmentObject private var store: CaregiverStore
    @EnvironmentObject private var speechOutput: SpeechOutputCoordinator
    @EnvironmentObject private var conversation: ConversationEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                demoBanner
                activityCard
                medicationCard
                locationCard
                checkInButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical)
        }
        .echoBackground()
        .navigationTitle("Caregiver")
        .animation(reduceMotion ? nil : .default, value: store.activity.count)
        .onAppear {
            Task { await speechOutput.announceScreen(AppScreen.caregiver.announcement) }
        }
    }

    // MARK: - Banner

    private var demoBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .symbolRenderingMode(.multicolor)
                .accessibilityHidden(true)
            Text("Demo data. Nothing here is real.")
                .font(.headline)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(border: Theme.caution.opacity(0.6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Demo data. Nothing here is real.")
        .accessibilityAddTraits(.isHeader)
        .accessibilitySortPriority(10)
    }

    // MARK: - Cards

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeading("Recent activity", symbol: "list.bullet.clipboard.fill", color: Color(.systemBlue))
            if store.activity.isEmpty {
                Text("No activity yet.")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(store.activity.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { RowDivider(inset: 0) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeText(for: entry.date))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(entry.event)
                        .font(.body)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(timeText(for: entry.date)), \(entry.event)")
            }
        }
        .card()
    }

    private var medicationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeading("Medication", symbol: "pills.fill", color: Color(.systemGreen))
            Text(store.adherenceText)
                .font(.body)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Medication. \(store.adherenceText)")
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeading("Last known location", symbol: "location.fill", color: Color(.systemIndigo))
            Text(store.lastLocationText)
                .font(.body)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Last known location. \(store.lastLocationText)")
    }

    private func cardHeading(_ title: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            IconTile(systemName: symbol, color: color, size: 30)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Check-in

    private var checkInButton: some View {
        Button {
            conversation.submitTyped("send a check-in")
        } label: {
            Label("Send check-in", systemImage: "paperplane.fill")
                .labelStyle(BigLabelStyle())
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityLabel("Send check-in")
        .accessibilityHint("Opens Messages with a text saying you are okay. You tap Send there.")
    }

    // MARK: - Helpers

    private func timeText(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
