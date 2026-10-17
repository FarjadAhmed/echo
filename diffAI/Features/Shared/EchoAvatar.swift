import SwiftUI

/// ECHO's glyph: a calm accent-colored orb with a white symbol, in the spirit of Siri and Voice Memos.
/// The symbol changes with the conversation state (waveform when ready, microphone while listening,
/// dots while thinking, a moving waveform while speaking). A soft halo breathes while listening or
/// speaking. All motion is off when Reduce Motion is on; the status text always says the state too.
///
/// Decorative by default (`accessibilityHidden`). Wrap it in a Button to make it a control.
struct EchoAvatar: View {
    let state: ConversationState
    var size: CGFloat = 160

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    private var animates: Bool { !reduceMotion && (state == .speaking || state == .listening) }
    private var orbSize: CGFloat { size * 0.8 }

    var body: some View {
        ZStack {
            // Soft halo. Only drawn at sizes where it reads as a halo, not a smudge.
            if size >= 60 {
                Circle()
                    .fill(Theme.accent.opacity(0.10))
                    .scaleEffect(animates && breathing ? 1.0 : 0.88)
                Circle()
                    .fill(Theme.accent.opacity(0.14))
                    .frame(width: size * 0.9, height: size * 0.9)
                    .scaleEffect(animates && breathing ? 1.04 : 0.96)
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.82), Theme.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size >= 60 ? orbSize : size, height: size >= 60 ? orbSize : size)
                .shadow(color: Theme.accent.opacity(size >= 60 ? 0.3 : 0), radius: size * 0.06, y: size * 0.03)

            glyph
                .font(.system(size: (size >= 60 ? orbSize : size) * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: state)
        .onAppear(perform: restartBreathing)
        .onChange(of: state) { _, _ in restartBreathing() }
        .onChange(of: reduceMotion) { _, _ in restartBreathing() }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        switch state {
        case .idle:
            Image(systemName: "waveform")
        case .listening:
            Image(systemName: "mic.fill")
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
        case .thinking:
            Image(systemName: "ellipsis")
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
        case .speaking:
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: !reduceMotion)
        }
    }

    private func restartBreathing() {
        if animates {
            // Speaking breathes gently; listening a little faster.
            let duration = state == .listening ? 1.0 : 1.6
            breathing = false
            withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                breathing = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                breathing = false
            }
        }
    }
}
