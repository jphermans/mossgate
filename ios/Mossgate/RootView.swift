import SwiftUI
import UIKit
import SpriteKit

/// Top-level container. Drives the three top-level scenes:
///   1. Splash (JPHsystems-branded, portrait)
///   2. Title (level select, landscape)
///   3. Game (SpriteKit canvas, landscape, with overlays)
struct RootView: View {
    @State private var phase: Phase = .splash
    @State private var gameLevelIndex: Int = 0
    @State private var hud: MossgateScene.HudInfo = .empty
    @State private var showSetup = false
    @StateObject private var touch = TouchState()
    @StateObject private var session = GameSession()

    enum Phase: Equatable { case splash, title, game }

    var body: some View {
        ZStack {
            Color("MossgateDusk").ignoresSafeArea()

            switch phase {
            case .splash:
                SplashView {
                    withAnimation(.easeInOut(duration: 0.35)) { phase = .title }
                }
                .transition(.opacity)
            case .title:
                TitleView(
                    onStartLevel: { idx in
                        gameLevelIndex = idx
                        withAnimation(.easeInOut(duration: 0.25)) { phase = .game }
                    },
                    onOpenSetup: { showSetup = true },
                    onOpenGameCenter: {
                        GameCenterManager.shared.openDashboard(presenter: topViewController())
                    }
                )
                .transition(.opacity)
                .onAppear { AudioEngine.shared.playMusic(.dusk) }

            case .game:
                gameStack
                    .transition(.opacity)
            }
        }
        // Sheet must be attached to a stable parent — not inside the switch,
        // otherwise it gets torn down the moment `phase` changes and never
        // appears. Medium detents so it doesn't cover the full screen.
        .sheet(isPresented: $showSetup) {
            SetupView(onDone: { showSetup = false })
                .presentationDetents(Self.setupDetents)
                .presentationDragIndicator(.visible)
        }
        .onReceive(SettingsStore.shared.$controllerOn) { on in
            session.scene?.setControllerEnabled(on)
        }
        .onChange(of: phase) { _, newValue in
            AppDelegate.orientationLock = (newValue == .splash) ? .portrait : .landscape
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.windows.first?.rootViewController?
                    .setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
        .onAppear {
                    wireController()
                    AppDelegate.orientationLock = .portrait
                    let args = ProcessInfo.processInfo.arguments
                    // Test hook: -OpenSetup 1 lands on the title screen with the
                    // Setup sheet already presented (used to verify the sheet
                    // wiring without a simulator tap).
                    let wantsSetup = args.contains("-OpenSetup")
                    // Test hook: -SkipSplash 1 skips past the splash screen.
                    // Optional second arg -StartInLevel N jumps straight into level N (test rigs).
                    if let i = args.firstIndex(of: "-StartInLevel"),
                       i + 1 < args.count,
                       let idx = Int(args[i + 1]),
                       idx < Levels.all.count {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            gameLevelIndex = idx
                            phase = .game
                        }
                    } else if UserDefaults.standard.bool(forKey: "SkipSplash") || wantsSetup {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation(.easeInOut(duration: 0.35)) { phase = .title }
                            if wantsSetup {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    showSetup = true
                                }
                            }
                        }
                    }
                }
    }

    // MARK: - Game stack

    @ViewBuilder
    private var gameStack: some View {
        ZStack {
            MossgateGameView(levelIndex: gameLevelIndex, session: session, hud: $hud)
                .ignoresSafeArea()
                .onAppear {
                    session.scene?.setControllerEnabled(SettingsStore.shared.controllerOn)
                }
            GameControlsView(touch: touch, onSceneRef: { _ in })
            // Keep the HUD up while dead/win/game over so the light counter is
            // actually visible at the moment it drops. The pause button only
            // applies while playing.
            if hud.phase != .title && hud.phase != .pause {
                GameHUDView(hud: hud, showsPause: hud.phase == .play) {
                    session.scene?.pause()
                }
            }
            if hud.phase == .pause || hud.phase == .dead
               || hud.phase == .win || hud.phase == .gameOver {
                OverlayPanel(
                    phase: hud.phase,
                    hud: hud,
                    onResume: { session.scene?.resume() },
                    // Game over is terminal: the only way on is a fresh lantern.
                    onRetry: (hud.phase == .gameOver)
                             ? {
                                 SettingsStore.shared.refillLives()
                                 session.scene?.retryLevel()
                               }
                             : { session.scene?.retryLevel() },
                    onQuit:   {
                        // Leaving while out of light would otherwise strand the
                        // player on the gates with no light to spend.
                        if SettingsStore.shared.isOutOfLight { SettingsStore.shared.refillLives() }
                        withAnimation(.easeInOut(duration: 0.25)) { phase = .title }
                    },
                    onNext:   hud.phase == .win && gameLevelIndex < Levels.all.count - 1
                              ? { session.scene?.nextLevel(); gameLevelIndex += 1 }
                              : nil
                )
            }
        }
        .onChange(of: touch.left)  { _, _ in touch.push(to: session.scene) }
        .onChange(of: touch.right) { _, _ in touch.push(to: session.scene) }
        .onChange(of: touch.jump)  { _, _ in touch.push(to: session.scene) }
        .onChange(of: touch.down)  { _, _ in touch.push(to: session.scene) }
    }

    // MARK: - Helpers

    /// Detents for the Setup sheet.
    ///
    /// -SetupLarge 1 collapses it to a single tall detent, which is how the
    /// controller section (below the fold at medium height) gets photographed in
    /// tests. A `selection:` binding set before presentation is ignored — SwiftUI
    /// presents at the first detent in the list — so the list itself has to change.
    private static var setupDetents: Set<PresentationDetent> {
        ProcessInfo.processInfo.arguments.contains("-SetupLarge") ? [.large] : [.medium, .large]
    }

    /// External controller wiring. One place owns the GamepadManager callbacks,
    /// so there is a single writer for the device list the Setup screen shows.
    private func wireController() {
        let pad = GamepadManager.shared
        pad.onInput = { input in
            session.scene?.setGamepad(left: input.left, right: input.right,
                                      jump: input.jump, down: input.down)
        }
        pad.onMenu = { session.scene?.pause() }
        pad.onDevicesChanged = { infos in
            DispatchQueue.main.async { ControllerList.shared.infos = infos }
        }
        pad.start()
    }

    private func topViewController() -> UIViewController? {
        guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first?.windows.first else {
            return nil
        }
        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

extension MossgateScene.HudInfo {
    static let empty = MossgateScene.HudInfo(
        phase: .title, levelName: "", coins: 0, total: 0, cleared: false, jumps: 2,
        lanterns: 0, lanternsTotal: 0, lives: SettingsStore.maxLives, maxLives: SettingsStore.maxLives
    )
}