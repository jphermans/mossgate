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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: phase) { _, newValue in
            AppDelegate.orientationLock = (newValue == .splash) ? .portrait : .landscape
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.windows.first?.rootViewController?
                    .setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
        .onAppear {
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
            GameControlsView(touch: touch, onSceneRef: { _ in })
            if hud.phase == .play {
                GameHUDView(hud: hud) {
                    session.scene?.pause()
                }
            }
            if hud.phase == .pause || hud.phase == .dead || hud.phase == .win {
                OverlayPanel(
                    phase: hud.phase,
                    hud: hud,
                    onResume: { session.scene?.resume() },
                    // Out of light: no retry — the only way on is back to the
                    // gates, which refills the lantern to full.
                    onRetry: (hud.phase == .dead && hud.lives <= 0)
                             ? nil
                             : { session.scene?.retryLevel() },
                    onQuit:   {
                        if hud.lives <= 0 { SettingsStore.shared.refillLives() }
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