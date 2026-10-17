import SwiftUI

/// Web assistant: demo favorites, a web address field, the page, and page actions.
/// Every control goes through the conversation, so voice and touch do the same thing.
struct WebAssistantView: View {
    @EnvironmentObject private var web: WebAssistantController
    @EnvironmentObject private var conversation: ConversationEngine
    @EnvironmentObject private var speechOutput: SpeechOutputCoordinator
    @State private var address = ""
    @FocusState private var addressFocused: Bool
    @Environment(\.echoHighContrast) private var highContrast

    var body: some View {
        VStack(spacing: 12) {
            favorites
            addressField

            WebViewRepresentable(webView: web.store.webView)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(highContrast ? Theme.strongBorder : Theme.separator, lineWidth: highContrast ? 1.5 : 0.5)
                )
                .frame(maxHeight: .infinity)
                .accessibilityLabel("Web page")

            WebLoadStatus(store: web.store)

            VStack(spacing: 10) {
                BigButton(title: "What can I do here?", systemImage: "list.bullet", hint: "Describes this page and what you can do") {
                    conversation.submitTyped("what can I do here")
                }
                readerButtons
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .echoBackground()
        .navigationTitle("Web")
        .onAppear {
            Task { await speechOutput.announceScreen(AppScreen.web.announcement) }
        }
    }

    private var favorites: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(WebAssistantController.favorites) { favorite in
                Button {
                    conversation.submitTyped("open \(favorite.spokenName)")
                } label: {
                    HStack(spacing: 12) {
                        IconTile(systemName: symbol(for: favorite), color: color(for: favorite), size: 30)
                        Text(favorite.title)
                            .font(.body.weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(CompactCardButtonStyle())
                .accessibilityLabel(favorite.title)
                .accessibilityHint("Opens this demo page. It works offline.")
            }
        }
    }

    private func color(for favorite: WebFavorite) -> Color {
        switch favorite.id {
        case "demo_news": return Color(.systemRed)
        case "demo_shop": return Color(.systemGreen)
        case "demo_appointment": return Color(.systemOrange)
        case "demo_bank": return Color(.systemIndigo)
        default: return Color(.systemBlue)
        }
    }

    private func symbol(for favorite: WebFavorite) -> String {
        switch favorite.id {
        case "demo_news": return "newspaper"
        case "demo_shop": return "cross.case"
        case "demo_appointment": return "calendar.badge.clock"
        case "demo_bank": return "building.columns"
        default: return "globe"
        }
    }

    private var isAddressEmpty: Bool { address.trimmingCharacters(in: .whitespaces).isEmpty }

    private var addressField: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            TextField("Web address or site name", text: $address)
                .font(.title3)
                .foregroundStyle(Theme.text)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($addressFocused)
                .onSubmit(openAddress)
                .accessibilityLabel("Web address")
                .accessibilityHint("Type a web address or a site name, then press return or Go")
            Button(action: openAddress) {
                // The 60 pt frame is inside the label, so the whole area is tappable.
                Text("Go")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(isAddressEmpty ? Color(.systemGray3) : Theme.accent))
                    .frame(minHeight: Theme.minTapHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isAddressEmpty)
            .accessibilityLabel("Go")
            .accessibilityHint("Opens the address you typed")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(minHeight: Theme.minTapHeight)
        .background(Theme.cardShape().fill(Theme.surface))
        .overlay {
            if addressFocused {
                Theme.cardShape().strokeBorder(Theme.accent, lineWidth: 2)
            } else if highContrast {
                Theme.cardShape().strokeBorder(Theme.strongBorder, lineWidth: 1.5)
            }
        }
    }

    @ViewBuilder
    private var readerButtons: some View {
        switch web.readerStatus {
        case .none:
            Button {
                conversation.submitTyped("read the page")
            } label: {
                Label("Read the page", systemImage: "speaker.wave.2")
                    .labelStyle(BigLabelStyle())
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel("Read the page")
            .accessibilityHint("Reads the main text aloud")
        case .reading:
            HStack(spacing: 10) {
                BigButton(title: "Pause", systemImage: "pause.fill", hint: "Pauses reading") {
                    conversation.submitTyped("pause")
                }
                BigButton(title: "Stop", systemImage: "stop.fill", hint: "Stops reading", tint: Theme.danger) {
                    conversation.submitTyped("stop")
                }
            }
        case .paused:
            HStack(spacing: 10) {
                BigButton(title: "Resume", systemImage: "play.fill", hint: "Continues reading") {
                    conversation.submitTyped("resume")
                }
                BigButton(title: "Stop", systemImage: "stop.fill", hint: "Stops reading", tint: Theme.danger) {
                    conversation.submitTyped("stop")
                }
            }
        }
    }

    /// Observes the store directly, because `loadError` and `isLoading` are published on it, not on the controller.
    private struct WebLoadStatus: View {
        @ObservedObject var store: WebViewStore

        var body: some View {
            if let error = store.loadError {
                ErrorText(message: error)
            } else if store.isLoading {
                Label("Loading the page", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private func openAddress() {
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines)
        address = ""
        guard !clean.isEmpty else { return }
        conversation.submitTyped("open \(clean)")
    }
}

/// A tighter card button for the four demo favorites, so the web page keeps most of the screen.
private struct CompactCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapHeight)
            .background(Theme.cardShape(Theme.buttonCornerRadius).fill(configuration.isPressed ? Theme.pressed : Theme.surface))
            .contentShape(Theme.cardShape(Theme.buttonCornerRadius))
    }
}
