import SwiftUI

/// In-game HUD: coin counter + level name + pause button.
struct GameHUDView: View {
    let hud: MossgateScene.HudInfo
    /// The pause button only makes sense while actually playing.
    var showsPause: Bool = true
    let onPause: () -> Void
    /// Straight back to the menu, without pausing first.
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                pill
                Spacer()
                title
                Spacer()
                // Back is always available, pause only while playing: needing to
                // pause before you can leave is two taps to do one thing, and the
                // pause panel already carries its own way out.
                HStack(spacing: 8) {
                    backButton
                    if showsPause {
                        pauseButton
                    } else {
                        // Keep the row's geometry stable when the button is hidden.
                        Color.clear.frame(width: 38, height: 38)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            Spacer()
        }
    }

    private var pill: some View {
        HStack(spacing: 10) {
            // Coins
            HStack(spacing: 5) {
                Circle()
                    .fill(Color("MossgateLantern"))
                    .frame(width: 8, height: 8)
                Text("\(hud.coins)/\(hud.total)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color("MossgateCream"))
            }
            // Lanterns collected in this level
            if hud.lanternsTotal > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color("MossgateLantern"))
                    Text("\(hud.lanterns)/\(hud.lanternsTotal)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color("MossgateCream"))
                }
            }
            // Light (lives) — shown as a fraction, matching the coin and lantern
            // counters, so each death reading 3/3 -> 2/3 -> 1/3 -> 0/3 is
            // unmistakable. The heart is deliberate: a flame here would be
            // confused with the lantern count beside it.
            HStack(spacing: 5) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color("MossgateLantern"))
                Text("\(hud.lives)/\(hud.maxLives)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color("MossgateCream"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color("MossgateSurface").opacity(0.75))
                .overlay(Capsule().strokeBorder(Color("MossgateBorder"), lineWidth: 1))
        )
    }

    private var title: some View {
        VStack(spacing: 2) {
            Text(hud.levelName)
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(Color("MossgateCream"))
                .lineLimit(1)
            Text(hud.cleared ? "Cleared" : "Keep the lantern lit")
                .font(.system(size: 10))
                .foregroundStyle(hud.cleared ? Color("MossgateLantern") : Color("MossgateMuted"))
        }
    }

    private var pauseButton: some View {
        Button(action: onPause) {
            Image(systemName: "pause.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color("MossgateCream"))
                .frame(width: 38, height: 38)
                .background(
                    Circle().fill(Color("MossgateSurface").opacity(0.75))
                        .overlay(Circle().strokeBorder(Color("MossgateBorder"), lineWidth: 1))
                )
        }
    }

    /// Back to the menu. The chevron is the system's own gesture for this, and it
    /// sits in the corner the thumb is not fighting the jump button for.
    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color("MossgateCream"))
                .frame(width: 38, height: 38)
                .background(
                    Circle().fill(Color("MossgateSurface").opacity(0.75))
                        .overlay(Circle().strokeBorder(Color("MossgateBorder"), lineWidth: 1))
                )
        }
        .accessibilityLabel("Back to the gates")
    }
}

/// On-screen control buttons (left, right, drop, jump).
struct GameControlsView: View {
    @ObservedObject var touch: TouchState
    let onSceneRef: (MossgateScene) -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack {
                HStack(spacing: 10) {
                    ctrlButton(label: "◀", key: "left") { touch.left = $0 }
                    ctrlButton(label: "▶", key: "right") { touch.right = $0 }
                }
                Spacer()
                HStack(spacing: 10) {
                    // Paired with the DOWN pad, because they do the same job in opposite
                    // directions. DOWN pans the camera to show what waits below; without an
                    // UP there was no way to see what is above you before going back up.
                    ctrlButton(label: "▲", key: "up") { touch.up = $0 }
                    ctrlButton(label: "▼", key: "down") { touch.down = $0 }
                    ctrlButton(label: "JUMP", key: "jump",
                               isPrimary: true) { touch.jump = $0 }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    private func ctrlButton(label: String, key: String,
                            isPrimary: Bool = false,
                            onChange: @escaping (Bool) -> Void) -> some View {
        ControlButton(label: label, isPrimary: isPrimary, onPress: {
            // A real press always wins over the filming demo: it cancels it and hands control
            // back, so a stray -DemoPlay launch can be taken over at any moment.
            DemoMode.stop()
            onChange(true)
        }, onRelease: { onChange(false) })
    }
}

private struct ControlButton: View {
    let label: String
    let isPrimary: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: {}) {
            Text(label)
                .font(.system(size: isPrimary ? 16 : 22, weight: .semibold))
                .foregroundStyle(isPrimary ? Color("MossgatePrimaryFg") : Color("MossgateCream"))
                .frame(width: isPrimary ? 96 : 64, height: isPrimary ? 64 : 64)
                .background(
                    RoundedRectangle(cornerRadius: isPrimary ? 32 : 16)
                        .fill(pressed
                              ? Color("MossgateLantern")
                              : (isPrimary ? Color("MossgateLantern") : Color("MossgateSurface").opacity(0.75)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isPrimary ? 32 : 16)
                        .strokeBorder(Color("MossgateBorder"), lineWidth: isPrimary ? 0 : 1)
                )
        }
        .buttonStyle(PressableButtonStyle(pressed: $pressed, onPress: onPress, onRelease: onRelease))
        // Never let a press outlive the button.
        //
        // PressableButtonStyle releases from `.onChange(isPressed)`, which does not run if the
        // button is torn out of the hierarchy while it is still pressed — and that happens at
        // exactly the moments that matter: the HUD rebuilding, a phase change, a rotation, a
        // level restart. The input would then stay on for good and survive the restart, which
        // is a character that runs by itself into the dark while nothing is being touched.
        .onDisappear {
            if pressed {
                pressed = false
                onRelease()
            }
        }
    }
}

private struct PressableButtonStyle: ButtonStyle {
    @Binding var pressed: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed && !pressed {
                    pressed = true
                    onPress()
                } else if !isPressed && pressed {
                    pressed = false
                    onRelease()
                }
            }
    }
}

/// Pause / Dead / Win overlay panels.
struct OverlayPanel: View {
    let phase: GameState
    let hud: MossgateScene.HudInfo
    let onResume: () -> Void
    /// `nil` when there is no way to continue in place (out of light).
    let onRetry: (() -> Void)?
    /// A fresh attempt at the gate from the top, as opposed to carrying on from the last
    /// waystone. Falls back to `onRetry` when not supplied.
    var onRestart: (() -> Void)? = nil
    let onQuit: () -> Void
    let onNext: (() -> Void)?
    /// Name of the world whose LAST gate was just cleared — the moment a world
    /// becomes finished. Nil when the gate cleared was not the final one.
    var worldJustCompleted: String? = nil
    /// The next world exists but is not playable (not bought, or an earlier world
    /// is unfinished), so no "Next" button is offered.
    var nextWorldLocked: Bool = false

    /// Running out of light is now its own state rather than a relabelled death.
    private var isGameOver: Bool { phase == .gameOver }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                eyebrow
                title
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 14))
                        .foregroundStyle(Color("MossgateMuted"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }
                if nextWorldLocked {
                    Text("Every gate in this world is done. The next one is locked \u{2014} open it from the gates.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color("MossgateLantern"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }
                VStack(spacing: 8) {
                    if let onRetry {
                        primaryButton(action: {
                            // Pause resumes; death, win and game over restart.
                            if phase == .pause { onResume() } else { onRetry() }
                        })
                        // Game over has one obvious action, so a second
                        // "restart" button beside it would just be noise.
                        if !isGameOver { secondaryButton(action: onRestart ?? onRetry) }
                    }
                    if let onNext = onNext {
                        Button(action: onNext) {
                            Text(worldJustCompleted == nil ? "Next gate" : "Next world")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .foregroundStyle(Color("MossgateCream"))
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(Color("MossgateBorder"), lineWidth: 1)
                                )
                        }
                    }
                    // Was "All gates", in small muted text at the bottom of the panel. The way
                    // out was always here, but a de-emphasised label that reads as "show me the
                    // gates" is not findable, and it did not say which page it went to. Asked
                    // for as "add in the menu the option to go back to start page", where the
                    // start page is the splash the game opens on. It stays below the primary
                    // action, but it now says where it goes and looks like a button.
                    Button(action: onQuit) {
                        Text("Back to the start page")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color("MossgateCream"))
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color("MossgateBorder"), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
            }
            .padding(.vertical, 22)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color("MossgateSurface").opacity(0.95))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color("MossgateBorder"), lineWidth: 1))
            )
            .padding(.horizontal, 32)
        }
    }

    private var eyebrow: some View {
        Text(isGameOver ? "GAME OVER" : eyebrowText)
            .font(.system(size: 11, weight: .semibold))
            .tracking(4)
            .foregroundStyle(Color("MossgateLantern"))
    }

    private var title: some View {
        Text(isGameOver ? "The lantern is out" : titleText)
            .font(.system(size: 32, weight: .semibold, design: .serif))
            .foregroundStyle(Color("MossgateCream"))
            .multilineTextAlignment(.center)
    }

    private var subtitle: String? {
        if isGameOver {
            return "Three falls and the light is spent. Start over to relight the lantern."
        }
        switch phase {
        case .pause: return hud.levelName
        case .dead:  return "The wick went out. \(hud.lives) of \(hud.maxLives) left."
        case .win:
            let coins = "\(hud.coins) of \(hud.total) coins."
            if let world = worldJustCompleted {
                return "\(world) is finished \u{2014} every gate open. \(coins)"
            }
            return coins
        default:     return nil
        }
    }

    private var eyebrowText: String {
        switch phase {
        case .pause: return "PAUSED"
        case .dead:  return "WICK OUT"
        case .win:   return worldJustCompleted == nil ? "GATE OPEN" : "WORLD COMPLETE"
        default:     return ""
        }
    }

    private var titleText: String {
        switch phase {
        case .pause: return "Paused"
        case .dead:  return "Try again"
        case .win:
            // Finishing a whole world is a bigger moment than opening one gate,
            // and it is the moment the next world becomes reachable — so it says so.
            return worldJustCompleted == nil ? "Mossgate yields" : "Every gate open"
        default:     return ""
        }
    }

    private func primaryButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(primaryText)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(Color("MossgatePrimaryFg"))
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(Color("MossgateLantern"))
                )
        }
    }

    private var primaryText: String {
        switch phase {
        case .pause:    return "Resume"
        case .dead:     return "Relight"
        case .win:      return "Replay"
        case .gameOver: return "Start over"
        default:        return ""
        }
    }

    private func secondaryButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Restart level")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(Color("MossgateCream"))
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color("MossgateSurface").opacity(0.85))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color("MossgateBorder"), lineWidth: 1))
                )
        }
    }
}