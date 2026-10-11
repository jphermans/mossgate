import SwiftUI

/// In-game HUD: coin counter + level name + pause button.
struct GameHUDView: View {
    let hud: MossgateScene.HudInfo
    let onPause: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                pill
                Spacer()
                title
                Spacer()
                pauseButton
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            Spacer()
        }
    }

    private var pill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color("MossgateLantern"))
                .frame(width: 8, height: 8)
            Text("\(hud.coins)/\(hud.total)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color("MossgateCream"))
            HStack(spacing: 2) {
                ForEach(0..<2, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(i < hud.jumps ? Color("MossgateLantern") : Color("MossgateBorder"))
                        .frame(width: 14, height: 5)
                }
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
    let onRetry: () -> Void
    let onQuit: () -> Void
    let onNext: (() -> Void)?

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
                VStack(spacing: 8) {
                    primaryButton
                    secondaryButton
                    if let onNext = onNext {
                        Button(action: onNext) {
                            Text("Next gate")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .foregroundStyle(Color("MossgateCream"))
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(Color("MossgateBorder"), lineWidth: 1)
                                )
                        }
                    }
                    Button(action: onQuit) {
                        Text("All gates")
                            .font(.system(size: 14))
                            .foregroundStyle(Color("MossgateMuted"))
                            .frame(maxWidth: .infinity, minHeight: 38)
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
        Text(eyebrowText)
            .font(.system(size: 11, weight: .semibold))
            .tracking(4)
            .foregroundStyle(Color("MossgateLantern"))
    }

    private var title: some View {
        Text(titleText)
            .font(.system(size: 32, weight: .semibold, design: .serif))
            .foregroundStyle(Color("MossgateCream"))
            .multilineTextAlignment(.center)
    }

    private var subtitle: String? {
        switch phase {
        case .pause: return hud.levelName
        case .dead:  return "The wick went out. Try again."
        case .win:   return "\(hud.coins) of \(hud.total) coins."
        default:     return nil
        }
    }

    private var eyebrowText: String {
        switch phase {
        case .pause: return "PAUSED"
        case .dead:  return "WICK OUT"
        case .win:   return "GATE OPEN"
        default:     return ""
        }
    }

    private var titleText: String {
        switch phase {
        case .pause: return "Paused"
        case .dead:  return "Try again"
        case .win:   return "Mossgate yields"
        default:     return ""
        }
    }

    private var primaryButton: some View {
        Button(action: primaryAction) {
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
        case .pause: return "Resume"
        case .dead:  return "Relight"
        case .win:   return "Replay"
        default:     return ""
        }
    }

    private func primaryAction() {
        switch phase {
        case .pause: onResume()
        case .dead:  onRetry()
        case .win:   onRetry()
        default:     break
        }
    }

    private var secondaryButton: some View {
        Button(action: onRetry) {
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