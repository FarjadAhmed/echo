import SwiftUI
import UIKit

/// Invisible view that reports device shakes (UIKit motion events) to SwiftUI.
struct ShakeDetector: UIViewRepresentable {
    let onShake: () -> Void

    func makeUIView(context: Context) -> ShakeView {
        let view = ShakeView()
        view.onShake = onShake
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: ShakeView, context: Context) {
        uiView.onShake = onShake
    }
}

final class ShakeView: UIView {
    var onShake: (() -> Void)?
    private var keyboardObserver: NSObjectProtocol?

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        becomeFirstResponder()
        // A text field takes first responder while the keyboard is up; take it back afterwards.
        if keyboardObserver == nil {
            keyboardObserver = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.becomeFirstResponder() }
            }
        }
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            onShake?()
        }
    }
}
