import SwiftUI
import UIKit

/// ECHO's look is Apple's own: system semantic colors only, so every screen follows light and dark mode
/// and the system Increase Contrast setting without any custom color math. The app's own High contrast
/// switch turns on the same high-contrast variants (see `ContrastOverride`) and also thickens borders
/// and weights through `\.echoHighContrast`.
enum Theme {
    // MARK: Colors (all system semantic colors)

    /// Screen background, as in Settings and Health.
    static let background = Color(.systemGroupedBackground)
    /// Cards, rows and fields on the screen background.
    static let surface = Color(.secondarySystemGroupedBackground)
    /// A field or chip inside a card.
    static let surfaceRaised = Color(.tertiarySystemGroupedBackground)
    /// Neutral fill for idle controls (thinking microphone, number badges).
    static let fill = Color(.tertiarySystemFill)
    /// Pressed highlight for rows and cards, like a Settings cell.
    static let pressed = Color(.systemGray4)
    /// Hairlines and borders.
    static let separator = Color(.separator)
    /// Stronger border used when high contrast is on.
    static let strongBorder = Color(.label).opacity(0.55)
    static let text = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)
    /// The app accent: system blue (Assets AccentColor).
    static let accent = Color.accentColor
    static let danger = Color(.systemRed)
    static let caution = Color(.systemOrange)
    static let success = Color(.systemGreen)
    /// Listening state: red, like the system recording indicator. Always paired with a symbol and text.
    static let listening = Color(.systemRed)

    // MARK: Shape and size

    static let cornerRadius: CGFloat = 16
    static let buttonCornerRadius: CGFloat = 14
    static let smallCornerRadius: CGFloat = 10
    /// Minimum touch target. Bigger than Apple's 44 pt because of tremor and low vision.
    static let minTapHeight: CGFloat = 60
    static let bigButtonHeight: CGFloat = 64
    static let micSize: CGFloat = 84
    static let shutterSize: CGFloat = 112
    /// Standard spacing between stacked blocks.
    static let spacing: CGFloat = 24
    /// Leading inset for row separators: after the icon tile.
    static let rowSeparatorInset: CGFloat = 64

    static func cardShape(_ radius: CGFloat = cornerRadius) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

// MARK: - High contrast

private struct EchoHighContrastKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when the app's High contrast switch or the system Increase Contrast setting is on.
    /// Components use it for thicker borders and bolder weights.
    var echoHighContrast: Bool {
        get { self[EchoHighContrastKey.self] }
        set { self[EchoHighContrastKey.self] = newValue }
    }
}

/// Applies the app's High contrast switch to the whole window as the system's Increase Contrast trait,
/// so every system color (and the AccentColor high-contrast variants) resolves to its stronger version.
struct ContrastOverride: UIViewRepresentable {
    let enabled: Bool

    func makeUIView(context: Context) -> OverrideView {
        let view = OverrideView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.enabled = enabled
        return view
    }

    func updateUIView(_ uiView: OverrideView, context: Context) {
        uiView.enabled = enabled
    }

    final class OverrideView: UIView {
        var enabled = false {
            didSet { apply() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        private func apply() {
            guard let window else { return }
            if enabled {
                window.traitOverrides.accessibilityContrast = .high
            } else if window.traitOverrides.contains(UITraitAccessibilityContrast.self) {
                window.traitOverrides.remove(UITraitAccessibilityContrast.self)
            }
        }
    }
}

// MARK: - Button styles

/// Filled accent button with white text: the main action on every screen.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FilledButtonStyle(fill: Theme.accent, foreground: .white).makeBody(configuration: configuration)
    }
}

/// Solid button in any color, for destructive (red) or neutral filled actions. Text must be white or label.
struct FilledButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        FilledBody(configuration: configuration, fill: fill, foreground: foreground)
    }

    private struct FilledBody: View {
        let configuration: ButtonStyleConfiguration
        let fill: Color
        let foreground: Color

        @Environment(\.legibilityWeight) private var legibilityWeight
        @Environment(\.echoHighContrast) private var highContrast
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.title3.weight(highContrast || legibilityWeight == .bold ? .bold : .semibold))
                .foregroundStyle(foreground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: Theme.bigButtonHeight)
                .background(
                    Theme.cardShape(Theme.buttonCornerRadius)
                        .fill(isEnabled ? fill : Color(.systemGray3))
                )
                .overlay {
                    if configuration.isPressed {
                        Theme.cardShape(Theme.buttonCornerRadius).fill(Color.black.opacity(0.15))
                    }
                }
                .contentShape(Theme.cardShape(Theme.buttonCornerRadius))
        }
    }
}

/// Secondary button: a card-colored button with tinted text, like a grouped-list action.
/// Pass `tint: Theme.danger` for a destructive secondary action.
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        SecondaryBody(configuration: configuration, tint: tint)
    }

    private struct SecondaryBody: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color

        @Environment(\.legibilityWeight) private var legibilityWeight
        @Environment(\.echoHighContrast) private var highContrast
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.title3.weight(highContrast || legibilityWeight == .bold ? .bold : .semibold))
                .foregroundStyle(isEnabled ? tint : Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapHeight)
                .background(
                    Theme.cardShape(Theme.buttonCornerRadius)
                        .fill(configuration.isPressed ? Theme.pressed : Theme.surface)
                )
                .overlay {
                    if highContrast {
                        Theme.cardShape(Theme.buttonCornerRadius)
                            .strokeBorder(isEnabled ? tint : Theme.strongBorder, lineWidth: 2)
                    }
                }
                .contentShape(Theme.cardShape(Theme.buttonCornerRadius))
        }
    }
}

/// A tappable card (quick actions, mode choices). Selected cards get an accent border and,
/// in the views that use it, a checkmark, so selection never depends on color alone.
struct CardButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        CardBody(configuration: configuration, isSelected: isSelected)
    }

    private struct CardBody: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool

        @Environment(\.echoHighContrast) private var highContrast

        var body: some View {
            configuration.label
                .foregroundStyle(Theme.text)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapHeight)
                .background(
                    Theme.cardShape().fill(configuration.isPressed ? Theme.pressed : Theme.surface)
                )
                .overlay {
                    if isSelected {
                        Theme.cardShape().strokeBorder(Theme.accent, lineWidth: 3)
                    } else if highContrast {
                        Theme.cardShape().strokeBorder(Theme.strongBorder, lineWidth: 1.5)
                    }
                }
                .contentShape(Theme.cardShape())
        }
    }
}

/// A full-width row inside a `RowGroup`: highlights like a Settings cell when pressed.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.text)
            .background(configuration.isPressed ? Theme.pressed : Color.clear)
            .contentShape(Rectangle())
    }
}

/// A 60-pt capsule for secondary navigation and mode pickers. Selected chips are filled with the accent
/// and show a checkmark.
struct ChipButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration, isSelected: isSelected)
    }

    private struct ChipBody: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool

        @Environment(\.legibilityWeight) private var legibilityWeight
        @Environment(\.echoHighContrast) private var highContrast

        var body: some View {
            configuration.label
                .font(.body.weight(highContrast || legibilityWeight == .bold ? .bold : .semibold))
                .foregroundStyle(isSelected ? Color.white : Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .frame(minHeight: Theme.minTapHeight)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Theme.accent : (configuration.isPressed ? Theme.pressed : Theme.surface))
                )
                .overlay {
                    if highContrast && !isSelected {
                        Capsule(style: .continuous).strokeBorder(Theme.strongBorder, lineWidth: 1.5)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
    }
}

// MARK: - Card

/// A rounded card on the grouped background. High contrast adds a visible border.
struct CardModifier: ViewModifier {
    var borderColor: Color?
    var borderWidth: CGFloat = 1.5

    @Environment(\.echoHighContrast) private var highContrast

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.cardShape().fill(Theme.surface))
            .overlay {
                if let borderColor {
                    Theme.cardShape().strokeBorder(borderColor, lineWidth: highContrast ? max(borderWidth, 2.5) : borderWidth)
                } else if highContrast {
                    Theme.cardShape().strokeBorder(Theme.strongBorder, lineWidth: 1.5)
                }
            }
    }
}

extension View {
    func card() -> some View {
        modifier(CardModifier())
    }

    /// A card with a colored border, for cautions and highlighted states.
    func card(border: Color, width: CGFloat = 1.5) -> some View {
        modifier(CardModifier(borderColor: border, borderWidth: width))
    }

    /// Fills the whole screen with the grouped system background.
    func echoBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}
