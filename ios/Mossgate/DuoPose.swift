import SwiftUI
import UIKit

/// Which way an iPhone Duo is folded — and whether this device is a Duo at all.
///
/// iOS 27.1 introduced `UIHinge` / `UIHingeInteraction` for exactly this: a view carries the
/// interaction and the system delivers hinge state to it. There is no device-level "am I a
/// foldable" query, because the answer depends on where in the hierarchy you ask.
///
/// Mossgate needs this because it is a landscape game whose canvas wants the inner display.
/// Closed, the outer display is portrait — a comfortable size for the splash and the level
/// list, and the wrong shape for a run. So the outer display shows the app, and refuses to
/// start one; the gate itself lives in `RootView`, in one place, next to the other rules
/// about leaving and entering a gate (`leaveToSplash`, `leaveCurrentGate`).
enum DuoPose: Equatable {
    /// Either not a foldable, or the hinge could not be read. Behave exactly as before.
    ///
    /// This is the default and it must stay the default: an unknown pose has to mean "ordinary
    /// iPhone", so a device without a hinge can never be mistaken for a closed Duo and locked
    /// out of playing the game.
    case unknown
    /// Closed — the outer display. Splash and level list only.
    case closed
    /// Open or partway open — the inner display can host the game.
    case open

    var canPlay: Bool { self != .closed }
}

/// Reads the hinge state through a zero-sized view that carries a `UIHingeInteraction`.
///
/// This is the UIKit route, which is the only public one that works below iOS 27.1 in the same
/// source file: SwiftUI's `onHingeChange` modifier is nicer, but referencing it at all would
/// require the deployment target to move. Behind `#available` like this, a build targeting
/// iOS 18 compiles, links and runs, and simply reports `.unknown` on anything older.
struct HingeReader: UIViewRepresentable {
    var onChange: (DuoPose) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false

        if #available(iOS 27.1, *) {
            // `UIHingeInteraction` is `NS_SWIFT_UI_ACTOR`, so the handler already arrives on
            // the main actor — no hop needed, and adding one would risk reordering updates.
            let interaction = UIHingeInteraction { _, update in
                let pose: DuoPose
                switch update.hinge?.status {
                case .closed:
                    pose = .closed
                case .partiallyOpen, .fullyOpen:
                    pose = .open
                default:
                    // Includes a nil hinge, which the header documents as "the interaction has
                    // left a hierarchy that provides hinge updates" — i.e. read it as unknown
                    // rather than guessing.
                    pose = .unknown
                }
                onChange(pose)
            }
            view.addInteraction(interaction)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
