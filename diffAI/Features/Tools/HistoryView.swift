import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var speechOutput: SpeechOutputCoordinator
    @State private var confirmClear = false

    var body: some View {
        List {
            if history.items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                    Text("Nothing yet")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("Descriptions, readings and scanned documents will appear here.")
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
            ForEach(history.items) { item in
                HStack(alignment: .top, spacing: 14) {
                    IconTile(systemName: symbol(for: item.kind), color: color(for: item.kind), size: 30)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(item.kind), \(item.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.summary)
                            .font(.body)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Double tap to hear it again")
                .accessibilityAction {
                    Task { await speechOutput.say(item.summary) }
                }
            }
            if !history.items.isEmpty {
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Label("Clear history", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityHint("Deletes all saved items")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("History")
        .confirmationDialog("Clear history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) {
                history.clear()
                Task { await speechOutput.say("History cleared.") }
            }
            Button("Keep history", role: .cancel) {}
        } message: {
            Text("All saved descriptions and readings are deleted.")
        }
        .onAppear {
            Task { await speechOutput.announceScreen(AppScreen.history.announcement) }
        }
    }

    private func color(for kind: String) -> Color {
        switch kind {
        case "Description": return Color(.systemIndigo)
        case "Text": return Color(.systemOrange)
        case "Document": return Color(.systemBlue)
        case "Color": return Color(.systemPink)
        case "Find": return Color(.systemGreen)
        default: return Color(.systemGray)
        }
    }

    private func symbol(for kind: String) -> String {
        switch kind {
        case "Description": return "camera.viewfinder"
        case "Text": return "text.viewfinder"
        case "Document": return "doc.text.viewfinder"
        case "Color": return "paintpalette"
        case "Find": return "magnifyingglass"
        default: return "clock"
        }
    }
}
