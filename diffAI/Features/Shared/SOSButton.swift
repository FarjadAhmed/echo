import SwiftUI

/// The Emergency button. It goes through the conversation, so the engine asks for approval
/// (and speaks the request) before any call is placed. Nothing happens without an explicit yes.
///
/// `.prominent` is a full-width solid red button (simple mode, voice only).
/// `.row` is a calmer card row with a red SOS tile, for the Home screen: obvious, not alarming.
struct SOSButton: View {
    enum Style {
        case prominent
        case row
    }

    var style: Style = .prominent

    @EnvironmentObject private var conversation: ConversationEngine
    @Environment(\.echoHighContrast) private var highContrast

    var body: some View {
        switch style {
        case .prominent:
            Button(action: trigger) {
                Label("Emergency", systemImage: "sos")
                    .labelStyle(BigLabelStyle())
            }
            .buttonStyle(FilledButtonStyle(fill: Theme.danger, foreground: .white))
            .accessibilityLabel("Emergency")
            .accessibilityHint("Calls your emergency contact after you confirm")
        case .row:
            Button(action: trigger) {
                HStack(spacing: 16) {
                    IconTile(systemName: "sos", color: Theme.danger, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Emergency")
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                        Text("Calls your emergency contact after you confirm")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapHeight + 12, alignment: .leading)
            }
            .buttonStyle(RowButtonStyle())
            .background(Theme.surface)
            .clipShape(Theme.cardShape())
            .overlay {
                Theme.cardShape().strokeBorder(Theme.danger.opacity(highContrast ? 1 : 0.35), lineWidth: highContrast ? 2 : 1)
            }
            .accessibilityLabel("Emergency")
            .accessibilityHint("Calls your emergency contact after you confirm")
        }
    }

    private func trigger() {
        conversation.submitTyped("help me")
    }
}
