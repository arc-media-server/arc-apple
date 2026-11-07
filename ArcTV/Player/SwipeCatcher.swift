import SwiftUI
import UIKit

/// Swipes across the Siri Remote's touch surface, for scrubbing (as tvOS's own players). The
/// remote's touches go to the focused view's window, so the pan recognizer sits on the window
/// while this (invisible) view is on screen. Only sideways swipes count; it lets the focus engine
/// see the same touches (the screen ignores the move commands a swipe also sends).
struct SwipeCatcher: UIViewRepresentable {
    /// Whether a swipe may start scrubbing now.
    let enabled: Bool
    let began: () -> Void
    /// How far across the surface the finger has moved since the swipe began, in points.
    let changed: (CGFloat) -> Void
    let ended: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Host {
        let host = Host()
        host.isUserInteractionEnabled = false
        host.pan = context.coordinator.pan
        return host
    }

    func updateUIView(_ host: Host, context: Context) {
        let c = context.coordinator
        c.enabled = enabled
        c.began = began
        c.changed = changed
        c.ended = ended
    }

    static func dismantleUIView(_ host: Host, coordinator: Coordinator) {
        coordinator.pan.view?.removeGestureRecognizer(coordinator.pan)
    }

    final class Host: UIView {
        var pan: UIPanGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let pan else { return }
            if let window {
                window.addGestureRecognizer(pan)
            } else {
                pan.view?.removeGestureRecognizer(pan)
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var enabled = false
        var began: () -> Void = {}
        var changed: (CGFloat) -> Void = { _ in }
        var ended: () -> Void = {}
        private var sideways = false

        lazy var pan: UIPanGestureRecognizer = {
            let p = UIPanGestureRecognizer(target: self, action: #selector(moved(_:)))
            p.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            p.cancelsTouchesInView = false
            p.delegate = self
            return p
        }()

        @objc private func moved(_ r: UIPanGestureRecognizer) {
            let t = r.translation(in: r.view)
            switch r.state {
            case .began:
                sideways = false
            case .changed:
                // Decided once the finger has moved a little: mostly sideways, or not at all.
                if !sideways {
                    guard abs(t.x) > 24, abs(t.x) > abs(t.y) * 1.5 else { return }
                    sideways = true
                    began()
                }
                changed(t.x)
            case .ended, .cancelled, .failed:
                if sideways { ended() }
                sideways = false
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ r: UIGestureRecognizer) -> Bool { enabled }

        func gestureRecognizer(_ r: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
