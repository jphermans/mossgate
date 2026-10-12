import UIKit

/// Haptics for the moments that already have a sound.
///
/// The call sites are deliberately the ones `AudioEngine` already uses: a moment worth hearing is
/// a moment worth feeling, and keeping the two side by side means neither drifts when a new
/// moment is added. The method names mirror that API exactly so the pairing reads as one thing at
/// the call site rather than two unrelated lines.
///
/// WHY THE GENERATORS ARE STATIC
///
/// The first version created a generator on every call, called `prepare()`, and fired. On a real
/// device that produces nothing at all while looking perfectly correct. A freshly created
/// generator has to spin the taptic engine up from cold, and the system does not wait around for
/// it — `prepare()` on a generator that is microseconds old buys back none of that time. One
/// generator per style, created once and re-armed after each fire, is what leaves the engine warm
/// by the time a pulse is asked for.
///
/// Each call picks a generator by what the moment IS, not by how strong it should feel: a light
/// tap for something collected, a soft one for something that stops, a rigid one for losing the
/// wick, and success for arriving somewhere. A single generator everywhere would make a coin and
/// a death indistinguishable in the hand.
///
/// Every call no-ops where there is no taptic engine — every simulator, and every iPad. That is
/// why the call sites are unconditional: a capability check at each one would be noise, and this
/// is the only place that knows whether it can actually buzz.
enum Haptics {
    // `UIFeedbackGenerator` is not Sendable, so these are main-actor bound. Every call site is on
    // the main thread already — the scene and the views — so nothing has to hop.
    @MainActor private static let lightTap = UIImpactFeedbackGenerator(style: .light)
    @MainActor private static let softTouch = UIImpactFeedbackGenerator(style: .soft)
    @MainActor private static let rigidKnock = UIImpactFeedbackGenerator(style: .rigid)
    @MainActor private static let notification = UINotificationFeedbackGenerator()

    /// Warm the engine. Called once as the game starts, so the first jump of a session is felt as
    /// clearly as the hundredth — otherwise it starts cold on exactly the moment a player is most
    /// likely to be paying attention.
    @MainActor static func warmUp() {
        lightTap.prepare()
        softTouch.prepare()
        rigidKnock.prepare()
        notification.prepare()
    }

    @MainActor private static func fire(_ generator: UIImpactFeedbackGenerator, _ intensity: CGFloat) {
        // One guard in each fire path rather than at ten call sites: the setting belongs to the
        // mechanism, not to every place that asks it to buzz.
        guard SettingsStore.shared.hapticsOn else { return }
        generator.impactOccurred(intensity: intensity)
        // Re-arm straight away: the next pulse may be a frame behind this one.
        generator.prepare()
    }

    @MainActor private static func note(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard SettingsStore.shared.hapticsOn else { return }
        notification.notificationOccurred(type)
        notification.prepare()
    }

    /// A button. At the light end on purpose — the game is tapped constantly, and a firm pulse on
    /// every control would be exhausting rather than informative.
    @MainActor static func tap() { fire(lightTap, 0.8) }

    /// Leaving the ground. Harder for the second jump, so a double jump is felt as the extra
    /// effort it costs.
    @MainActor static func jump(_ double: Bool = false) { fire(lightTap, double ? 1.0 : 0.8) }

    /// Touching down. Soft rather than light, so arrival reads as arrival rather than as another
    /// thing collected.
    @MainActor static func land() { fire(softTouch, 1.0) }

    @MainActor static func coin() { fire(lightTap, 0.9) }

    /// A waystone. Success rather than impact, because it is good news rather than an event.
    @MainActor static func checkpoint() { note(.success) }

    /// Losing the wick. Rigid is the only style that reads as a mistake rather than a touch.
    @MainActor static func die() { fire(rigidKnock, 1.0) }

    /// The gate opening.
    @MainActor static func win() { note(.success) }
}
