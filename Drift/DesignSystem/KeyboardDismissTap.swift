//
//  KeyboardDismissTap.swift
//  Drift
//
//  Tap-outside-to-dismiss for the keyboard — the Android-style behavior that
//  iOS doesn't provide by default.
//
//  A plain SwiftUI `.onTapGesture` can't do this cleanly on a `Form`/`List`:
//  the list swallows the tap, and a blanket gesture fights field focus. So we
//  add ONE tap recognizer to the host window that:
//    • recognizes simultaneously and never cancels touches, so buttons,
//      pickers, steppers and field focus all keep working, and
//    • skips dismissal when the tap lands on a text field, so tapping one field
//      while another is focused just moves the cursor instead of closing.
//  The recognizer is scoped to the view's lifetime (removed when it disappears).
//
//  Usage:  Form { ... }.dismissKeyboardOnTapOutside()
//

import SwiftUI
import UIKit

extension View {
    /// Dismisses the keyboard when the user taps outside any text input.
    func dismissKeyboardOnTapOutside() -> some View {
        background(KeyboardDismissTap())
    }
}

private struct KeyboardDismissTap: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = WindowAwareView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false   // never intercept touches itself
        view.onMoveToWindow = { window in
            if let window {
                context.coordinator.attach(to: window)
            } else {
                context.coordinator.detach()
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private weak var tap: UITapGestureRecognizer?

        func attach(to window: UIWindow) {
            guard tap == nil else { return }
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            recognizer.cancelsTouchesInView = false   // controls still get the tap
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
            self.window = window
            self.tap = recognizer
        }

        func detach() {
            if let tap, let window { window.removeGestureRecognizer(tap) }
            tap = nil
            window = nil
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let window else { return }
            let point = recognizer.location(in: window)
            // Don't dismiss when tapping a text field — let it take the cursor.
            if let hit = window.hitTest(point, with: nil), hit.isInsideTextInput {
                return
            }
            window.endEditing(true)
        }

        // Fire alongside the list's pan and any control's own gesture.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// A zero-size helper that reports when it joins (or leaves) a window.
private final class WindowAwareView: UIView {
    var onMoveToWindow: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onMoveToWindow?(window)
    }
}

private extension UIView {
    /// True when this view is, or sits inside, a UIKit text input.
    var isInsideTextInput: Bool {
        var current: UIView? = self
        while let view = current {
            if view is UITextField || view is UITextView { return true }
            current = view.superview
        }
        return false
    }
}
