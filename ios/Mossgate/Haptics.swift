import UIKit

/// Haptics for the moments that already have a sound.
///
/// The call sites are deliberately the ones `AudioEngine` already uses: a moment worth hearing is
/// a moment worth feeling, and keeping the two side by side means neither drifts when a new
/// moment is added. The method names mirror that API exactly so the pairing reads as one thing at
/// the call site rather than two unrelated lines.
///
/// Each call picks a generator by what the moment IS, not by how strong it should feel: a light
/// tap for something collected, a soft one for something that stops, a rigid one for losing the
/// wick, and a success pattern for arriving somewhere. A single "default" generator everywhere
/// would make a coin and a death indistinguishable in the hand.
///
/// `prepare()` before each fire, because the taptic engine has a short window after being asked
/// and an unprepared generator is the difference between a tap and nothing at all.
///
/// Every call no-ops where there is no taptic engine — every simulator, and every iPad. That is
/// why the call sites are unconditional: a capability check at each one would be noise, and this
/// is the only place that knows whether it can actually buzz.
enum Haptics {
    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle,
                               _ intensity: CGFloat = 1.0) {
        // One guard in each fire path rather than at ten call sites: the setting belongs to
        // the mechanism, not to every place that asks it to buzz.
        guard SettingsStore.shared.hapticsOn else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
    }

    private static func note(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard SettingsStore.shared.hapticsOn else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    /// A button. Barely there on purpose — the whole game is tapped constantly and a firm pulse
    /// on every control would be exhausting rather than informative.
    static func tap() { impact(.light, 0.5) }

    /// Leaving the ground. Heavier for the second jump, so a double jump is felt as the extra
    /// effort it costs.
    static func jump(_ double: Bool = false) { impact(.light, double ? 0.9 : 0.6) }

    /// Touching down. A soft style rather than light: it should register as arrival, not as
    /// another thing collected.
    static func land() { impact(.soft) }

    static func coin() { impact(.light, 0.7) }

    /// A waystone. Success rather than impact, because it is good news rather than an event.
    static func checkpoint() { note(.success) }

    /// Losing the wick. Rigid is the only style that reads as a mistake rather than a touch.
    static func die() { impact(.rigid) }

    /// The gate opening.
    static func win() { note(.success) }
}
