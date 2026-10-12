import SwiftUI
import UIKit

/// Which way an iPhone Duo is folded — and whether this device is a Duo at all.
///
/// WHY THIS IS NOT ONLY THE HINGE API
///
/// iOS 27.1 introduced `UIHinge` / `UIHingeInteraction`, and that is the tidy answer — but it
/// only reports to a view the system decides is in a hinge-aware hierarchy. On a real Duo it
/// did not report at all: the app was found folded showing a BLACK SCREEN, which is exactly
/// what a landscape-only app looks like on a portrait display. The pose stayed `.unknown`, so
/// nothing was asked to rotate and nothing was drawn.
///
/// So there are two independent signals, and either one is enough:
///
///  1. The hinge, when the system chooses to tell us.
///  2. The window's own shape, which is the one that cannot silently fail. The Duo's outer
///     display is 1398x2034 — roughly 466x678pt, a wide PORTRAIT. The inner display is about
///     890x626pt, wider than tall. No ordinary iPhone is portrait at that shape: a 16 Pro is
///     402x874 and an SE 375x667, both far more slender. See `fromWindowSize`.
///
/// `.unknown` means behave exactly as before, and it is the default. A device satisfying
/// neither signal cannot be mistaken for a closed Duo and locked out of the game.
enum DuoPose: Equatable {
    case unknown
    /// Closed — the outer display. Splash and level list only.
    case closed
    /// Open or partway open — the inner display can host the game.
    case open

    var canPlay: Bool { self != .closed }
}

extension DuoPose {
    /// A test override, set by the `-ForceClosed` / `-ForceOpen` / `-ForceCloseAfter` hooks.
    ///
    /// It has to exist because the geometry reader is honest: the simulator's primary display
    /// IS the outer one, so on a simulator this would report closed no matter which pose a test
    /// means to exercise, and the flags would be silently overruled by the thing they are meant
    /// to stand in for.
    @MainActor static var forced: DuoPose?

    /// Classifies a window size. The thresholds are the whole argument, so they are explicit.
    ///
    /// Portrait is the outer display — but only if the shape is the wide one. Every iPhone in
    /// portrait is taller than wide, so shape alone would call all of them closed; what
    /// separates the Duo is that its portrait is 0.69 as wide as it is tall, against 0.46 for a
    /// 16 Pro and 0.56 for the widest ordinary iPhone. 0.60 sits in that gap.
    ///
    /// Landscape is the inner display, but only if it is big: ordinary iPhones in landscape are
    /// compact-height. 600pt sits above every phone and well below the inner display's 626pt.
    static func fromWindowSize(_ size: CGSize) -> DuoPose {
        let long = max(size.width, size.height)
        let short = min(size.width, size.height)
        guard long > 0, short > 0 else { return .unknown }

        if size.height > size.width {
            return (short / long) >= 0.60 ? .closed : .unknown
        }
        return short >= 600 ? .open : .unknown
    }
}

/// Reports the pose from both the hinge and the window's shape.
struct HingeReader: UIViewRepresentable {
    var onChange: (DuoPose) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false

        if #available(iOS 27.1, *) {
            // `UIHingeInteraction` is `NS_SWIFT_UI_ACTOR`, so the handler already arrives on the
            // main actor — no hop needed, and adding one would risk reordering updates.
            let interaction = UIHingeInteraction { _, update in
                if let forced = DuoPose.forced { onChange(forced); return }
                switch update.hinge?.status {
                case .closed:
                    onChange(.closed)
                case .partiallyOpen, .fullyOpen:
                    onChange(.open)
                default:
                    // Includes a nil hinge, which the header documents as "the interaction has
                    // left a hierarchy that provides hinge updates" — read it as unknown rather
                    // than guessing, because guessing `.closed` here is what blacks the screen.
                    break
                }
            }
            view.addInteraction(interaction)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Folding the phone changes the window's size, which re-runs the layout, which lands
        // here — so this is the signal that follows the fold rather than only reporting once.
        guard let size = uiView.window?.bounds.size, size.width > 0, size.height > 0 else { return }
        onChange(DuoPose.forced ?? DuoPose.fromWindowSize(size))
    }
}
