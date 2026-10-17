import SwiftUI
import UIKit

// MARK: - Buttons

/// Large, full-width button with a label and icon. Minimum height is well above 60 pt.
/// The default tint is the accent; `Theme.danger` (or `.red`) gives the destructive look; any other
/// tint is a solid fill with white text.
struct BigButton: View {
    let title: String
    let systemImage: String
    var hint: String = ""
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(BigLabelStyle())
        }
        .buttonStyle(FilledButtonStyle(fill: fill, foreground: .white))
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }

    private var fill: Color {
        if tint == .red { return Theme.danger }
        return tint
    }
}

/// Icon beside centred, wrapping text. Used inside every big button.
struct BigLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
                .imageScale(.medium)
                .accessibilityHidden(true)
            configuration.title
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The persistent microphone button. Its value says what the assistant is doing; the symbol changes
/// with the state too, so color is never the only cue.
struct MicButton: View {
    let state: ConversationState
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                if state == .listening && !reduceMotion {
                    Circle()
                        .fill(Theme.listening.opacity(0.18))
                        .scaleEffect(1.2)
                        .transition(.opacity)
                }
                Circle()
                    .fill(fill)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                symbolImage
                    .font(.title.weight(.semibold))
                    .imageScale(.large)
                    .foregroundStyle(foreground)
            }
            .frame(width: Theme.micSize, height: Theme.micSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state)
        .accessibilityLabel("Microphone")
        .accessibilityValue(state.label)
        .accessibilityHint(hint)
        .accessibilityAddTraits(state == .listening ? .isSelected : [])
    }

    @ViewBuilder
    private var symbolImage: some View {
        if state == .listening && !reduceMotion {
            Image(systemName: symbol)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        } else {
            Image(systemName: symbol)
        }
    }

    private var symbol: String {
        switch state {
        case .idle: return "mic.fill"
        case .listening: return "waveform"
        case .thinking: return "ellipsis"
        case .speaking: return "speaker.wave.2.fill"
        }
    }

    private var fill: Color {
        switch state {
        case .listening: return Theme.listening
        case .thinking: return Color(.systemGray5)
        default: return Theme.accent
        }
    }

    private var foreground: Color {
        state == .thinking ? Theme.text : .white
    }

    private var hint: String {
        switch state {
        case .idle: return "Double tap to start listening"
        case .listening: return "Double tap to stop listening"
        case .thinking, .speaking: return "Double tap to interrupt and talk"
        }
    }
}

/// Red stop button, shown while the assistant is busy.
struct StopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Stop", systemImage: "stop.fill")
                .labelStyle(BigLabelStyle())
                .frame(minWidth: 96)
        }
        .buttonStyle(FilledButtonStyle(fill: Theme.danger, foreground: .white))
        .frame(maxWidth: 180)
        .accessibilityLabel("Stop")
        .accessibilityHint("Stops speaking and listens again")
    }
}

/// Shows the current state as a symbol and words. Changes are also spoken or announced.
struct StatusLabel: View {
    let state: ConversationState
    var font: Font = .headline

    var body: some View {
        Label {
            Text(state.label)
                .foregroundStyle(state == .idle ? Theme.textSecondary : Theme.text)
        } icon: {
            Image(systemName: state.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
        }
        .font(font)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status")
        .accessibilityValue(state.label)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var iconColor: Color {
        switch state {
        case .idle: return Theme.textSecondary
        case .listening: return Theme.listening
        case .thinking, .speaking: return Theme.accent
        }
    }
}

// MARK: - Conversation

/// One chat bubble. The whole bubble is a single VoiceOver element: "You: …" or "ECHO: …".
struct MessageBubble: View {
    let message: ChatMessage

    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.echoHighContrast) private var highContrast

    private var isUser: Bool { message.role == .user }
    private var displayText: String { message.text.isEmpty ? "…" : message.text }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // The spacer keeps every bubble to roughly 80 % of the width.
            if isUser { Spacer(minLength: 48) } else { avatar }

            VStack(alignment: .leading, spacing: 8) {
                if let image = message.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                        .accessibilityHidden(true)
                }
                Text(displayText)
                    .font(.title3.weight(legibilityWeight == .bold || highContrast ? .semibold : .regular))
                    .foregroundStyle(isUser ? Color.white : Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isUser ? Theme.accent : Theme.surface)
            )
            .overlay {
                if highContrast && !isUser {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Theme.strongBorder, lineWidth: 1.5)
                }
            }

            if !isUser { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isUser ? "You" : "ECHO"): \(displayText)\(message.image == nil ? "" : ". With a photo")")
    }

    private var avatar: some View {
        EchoAvatar(state: .idle, size: 30)
            .accessibilityHidden(true)
    }
}

/// The words recognised so far, shown while the user speaks. Visual only; VoiceOver hears the final text.
struct PartialBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                )
        }
        .accessibilityHidden(true)
    }
}

/// "Task progress" card: done steps are ticked, the current and next steps are numbered.
/// One VoiceOver element that reads the whole state in a sentence.
struct TaskProgressCard: View {
    let steps: [ProgressStep]

    private var doneCount: Int { steps.filter(\.done).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Task progress")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                Text("\(doneCount) of \(steps.count) complete")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            ProgressView(value: Double(doneCount), total: Double(max(steps.count, 1)))
                .accessibilityHidden(true)
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    stepMarker(index: index, done: step.done)
                    Text(step.title)
                        .font(.body)
                        .foregroundStyle(step.done ? Theme.textSecondary : Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private func stepMarker(index: Int, done: Bool) -> some View {
        if done {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Theme.success)
        } else {
            Text("\(index + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.text)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.fill))
        }
    }

    private var spoken: String {
        let done = steps.filter(\.done).map(\.title)
        let next = steps.filter { !$0.done }.map(\.title)
        var parts = ["Task progress, \(doneCount) of \(steps.count) complete."]
        if !done.isEmpty { parts.append("Done: " + done.joined(separator: ", ") + ".") }
        if !next.isEmpty { parts.append("Next: " + next.joined(separator: ", ") + ".") }
        return parts.joined(separator: " ")
    }
}

/// Scrolling list of the conversation. The live partial transcript is visual only.
struct TranscriptView: View {
    let messages: [ChatMessage]
    let partial: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if messages.isEmpty {
                        Text("Tap the microphone and ask me anything, or type below.")
                            .font(.title3)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(messages.filter(\.isVisible)) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if !partial.isEmpty {
                        PartialBubble(text: partial)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Icon tiles and rows

/// A white SF Symbol on a colored rounded square, like a Settings row icon. Always decorative:
/// the row's text says what it is, so the color is never the only cue.
struct IconTile: View {
    let systemName: String
    var color: Color = Theme.accent
    var size: CGFloat = 32

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    private var side: CGFloat { size * min(max(scale, 1), 1.6) }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: side * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(
                RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                    .fill(color.gradient)
            )
            .accessibilityHidden(true)
    }
}

/// A grouped card that holds `FeatureRow`s separated by inset hairlines, like an inset-grouped list.
struct RowGroup<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.echoHighContrast) private var highContrast

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Theme.surface)
        .clipShape(Theme.cardShape())
        .overlay {
            if highContrast {
                Theme.cardShape().strokeBorder(Theme.strongBorder, lineWidth: 1.5)
            }
        }
    }
}

/// The hairline between rows of a `RowGroup`, inset past the icon tile.
struct RowDivider: View {
    var inset: CGFloat = Theme.rowSeparatorInset

    @Environment(\.echoHighContrast) private var highContrast

    var body: some View {
        Rectangle()
            .fill(highContrast ? Theme.strongBorder : Theme.separator)
            .frame(height: highContrast ? 1 : 0.5)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

/// A Settings-style row: icon tile, title, optional subtitle, chevron. At least 60 pt tall.
struct FeatureRow: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    var color: Color = Theme.accent
    var hint: String = ""
    var showsChevron = true
    let action: () -> Void

    @Environment(\.echoHighContrast) private var highContrast

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                IconTile(systemName: systemImage, color: color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(highContrast ? .semibold : .regular))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(highContrast ? Theme.textSecondary : Theme.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapHeight, alignment: .leading)
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}

// MARK: - Home pieces

/// A quick-action tile: a colored icon tile above a title. One button, one VoiceOver element.
struct QuickActionCard: View {
    let title: String
    let systemImage: String
    var hint: String = ""
    var color: Color = Theme.accent
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    IconTile(systemName: systemImage, color: color, size: 40)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                    }
                }
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(CardButtonStyle(isSelected: isSelected))
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A 60-pt capsule for secondary navigation and mode selection. Selected chips show a checkmark.
struct NavChip: View {
    let title: String
    let systemImage: String
    var hint: String = ""
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isSelected ? "checkmark" : systemImage)
        }
        .buttonStyle(ChipButtonStyle(isSelected: isSelected))
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "Or type your request" field with a Send button, on a card-colored rounded rectangle.
struct TypedRequestField: View {
    @Binding var text: String
    var placeholder = "Or type your request"
    let onSend: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.echoHighContrast) private var highContrast

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text, axis: .vertical)
                .font(.title3)
                .foregroundStyle(Theme.text)
                .lineLimit(1...4)
                .submitLabel(.send)
                .focused($isFocused)
                .onSubmit(onSend)
                .padding(.vertical, 12)
                .accessibilityLabel("Type your request")
                .accessibilityHint("Type what you want to ask, then press return or Send")
            Button(action: onSend) {
                // The frame is inside the label, so the whole 60 pt square is tappable.
                Image(systemName: "arrow.up.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isEmpty ? Color(.systemGray3) : Theme.accent)
                    .frame(width: Theme.minTapHeight, height: Theme.minTapHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isEmpty)
            .accessibilityLabel("Send")
            .accessibilityHint("Sends your typed request")
        }
        .padding(.leading, 16)
        .padding(.trailing, 2)
        .frame(minHeight: Theme.minTapHeight)
        .background(Theme.cardShape().fill(Theme.surface))
        .overlay {
            if isFocused {
                Theme.cardShape().strokeBorder(Theme.accent, lineWidth: 2)
            } else if highContrast {
                Theme.cardShape().strokeBorder(Theme.strongBorder, lineWidth: 1.5)
            }
        }
    }
}

/// A section heading above a group of cards, marked as a header for the VoiceOver rotor.
struct SectionHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.bold))
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A large decorative SF Symbol in hierarchical accent, used at the top of onboarding and sheets.
struct HeroSymbol: View {
    let systemName: String
    var tint: Color = Theme.accent

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 80

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: min(size, 112), weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(minHeight: 88)
            .accessibilityHidden(true)
    }
}

/// An error card: red warning symbol, readable label-colored text. Announced as "Problem: …".
struct ErrorText: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Theme.danger)
                .accessibilityHidden(true)
            Text(message)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(border: Theme.danger.opacity(0.7))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Problem: \(message)")
    }
}

// MARK: - Modifiers

/// Applies the Large text setting as a floor: text is never smaller than accessibility 2,
/// and never shrinks for someone whose system setting is already larger.
struct LargeTextModifier: ViewModifier {
    let enabled: Bool

    @Environment(\.dynamicTypeSize) private var current

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.dynamicTypeSize(max(current, .accessibility2))
        } else {
            content
        }
    }
}

/// Solid surface when Reduce Transparency is on, the system bar material otherwise.
struct BarBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            Rectangle().fill(.bar)
        }
    }
}
