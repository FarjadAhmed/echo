import SwiftUI

/// The heart of the trust model: ECHO shows exactly what it is about to do and waits.
/// The engine has already spoken the request, so this screen says nothing on its own.
/// Three choices, always visible: confirm, change, cancel. Magic tap confirms; the escape gesture cancels.
struct ApprovalView: View {
    let request: ApprovalRequest

    @EnvironmentObject private var conversation: ConversationEngine
    @AccessibilityFocusState private var headingFocused: Bool
    @Environment(\.echoHighContrast) private var highContrast

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                VStack(spacing: 12) {
                    HeroSymbol(systemName: "checkmark.shield.fill")

                    Text("Ready for your approval")
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($headingFocused)

                    Text(request.title)
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                Text(request.summary)
                    .font(.title3)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                if !request.rows.isEmpty || request.requiresBiometric {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Here are the details:")
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                            .padding(.leading, 4)
                            .accessibilityAddTraits(.isHeader)
                        detailsCard
                    }
                }

                if let caution = request.caution {
                    cautionCard(caution)
                }

                actions
            }
            .padding()
            .padding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(Theme.text)
        .echoBackground()
        .presentationBackground(Theme.background)
        .presentationCornerRadius(24)
        .accessibilityAction(.magicTap) { conversation.approve() }
        .accessibilityAction(.escape) { conversation.cancelApproval() }
        .onAppear {
            // Give the sheet a moment to settle so VoiceOver lands on the heading, not the grabber.
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                headingFocused = true
            }
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(request.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { RowDivider(inset: 0) }
                detailRow(label: row.label, value: row.value)
            }
            if request.requiresBiometric {
                if !request.rows.isEmpty { RowDivider(inset: 0) }
                HStack(spacing: 12) {
                    IconTile(systemName: "faceid", color: Color(.systemGreen))
                    Text("Face ID required")
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .frame(minHeight: 52)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Face ID required before this runs")
            }
        }
        .padding(.horizontal, 16)
        .background(Theme.cardShape().fill(Theme.surface))
        .overlay {
            if highContrast {
                Theme.cardShape().strokeBorder(Theme.strongBorder, lineWidth: 1.5)
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    private func cautionCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.caution)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(border: Theme.caution.opacity(0.6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Caution: \(text)")
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                conversation.approve()
            } label: {
                Label(request.confirmLabel, systemImage: "checkmark")
                    .labelStyle(BigLabelStyle())
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityLabel(request.confirmLabel)
            .accessibilityHint(request.requiresBiometric
                ? "Asks for Face ID, then does this"
                : "Does this now. Nothing has happened yet.")

            Button {
                conversation.changeApproval()
            } label: {
                Label("Change details", systemImage: "pencil")
                    .labelStyle(BigLabelStyle())
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel("Change details")
            .accessibilityHint("Nothing is done. ECHO asks what you want to change")

            Button {
                conversation.cancelApproval()
            } label: {
                Label("Cancel action", systemImage: "xmark")
                    .labelStyle(BigLabelStyle())
            }
            .buttonStyle(SecondaryButtonStyle(tint: Theme.danger))
            .accessibilityLabel("Cancel action")
            .accessibilityHint("Stops here. Nothing is sent or changed")
        }
        .padding(.top, 8)
    }
}
