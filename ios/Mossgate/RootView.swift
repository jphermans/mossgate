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
    @State private var showHelp = false
    @StateObject private var touch = TouchState()
    @StateObject private var session = GameSession()
    @ObservedObject private var store = Store.shared

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
                        // The title screen already refuses, but a locked gate must not
                        // be reachable by any other caller either.
                        guard SettingsStore.shared.gateUnlocked(idx) else {
                            SettingsStore.shared.notice = "That gate is still locked."
                            return
                        }
                        gameLevelIndex = idx
                        withAnimation(.easeInOut(duration: 0.25)) { phase = .game }
                    },
                    onOpenSetup: { showSetup = true },
                    onOpenHelp: { showHelp = true },
                    onOpenGameCenter: {
                        GameCenterManager.shared.openDashboard(presenter: topViewController())
                    },
                    onLockedTap: { world in
                        if SettingsStore.shared.hasFullGame {
                            let prev = Worlds.all.first { $0.id == world.id - 1 }?.name
                                       ?? "the world before"
                            SettingsStore.shared.notice = "Finish \(prev) to open this one."
                        } else {
                            Task { await Store.shared.buy() }
                        }
                    },
                    onBuyFullGame: { Task { await Store.shared.buy() } },
                    onRestore: { Task { await Store.shared.restore() } }
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
        // Help / About. Tall detent: it is a long read, not a quick setting.
        .sheet(isPresented: $showHelp) {
            AboutView(onDone: { showHelp = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onReceive(SettingsStore.shared.$controllerOn) { on in
            session.scene?.setControllerEnabled(on)
        }
        // One alert for both channels: a Store message and a gameplay notice would
        // otherwise be two alerts competing for the same view.
        .alert("Mossgate", isPresented: Binding(
            get: { store.message != nil || SettingsStore.shared.notice != nil },
            set: { if !$0 { store.message = nil; SettingsStore.shared.notice = nil } }
        )) {
            Button("OK") { store.message = nil; SettingsStore.shared.notice = nil }
        } message: {
            Text(store.message ?? SettingsStore.shared.notice ?? "")
        }
        // A reshuffle rebuilds the current level so the new world is visible
        // immediately. Setup is only reachable from the title screen, so no
        // in-level progress is lost.
        .onReceive(SettingsStore.shared.$runSeed) { _ in
            session.scene?.retryLevel()
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
                    Store.shared.start()
                    // Test hook: -TestSfx 1 renders every effect through the real
                    // audio graph offline and reports the level that comes out.
                    if ProcessInfo.processInfo.arguments.contains("-TestSfx") {
                        AudioEngine.shared.runSfxProbe()
                    }
                    AppDelegate.orientationLock = .portrait
                    let args = ProcessInfo.processInfo.arguments
                    // Test hook: -OpenSetup 1 lands on the title screen with the
                    // Setup sheet already presented (used to verify the sheet
                    // wiring without a simulator tap).
                    let wantsSetup = args.contains("-OpenSetup")
                    // Test hook: -OpenHelp 1 lands on the title screen with the
                    // help sheet already presented.
                    let wantsHelp = args.contains("-OpenHelp")
                    // Test hook: -SkipSplash 1 skips past the splash screen.
                    // Optional second arg -StartInLevel N jumps straight into level N (test rigs).
                    if let i = args.firstIndex(of: "-StartInLevel"),
                       i + 1 < args.count,
                       let idx = Int(args[i + 1]),
                       idx < SettingsStore.shared.gates.count {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            gameLevelIndex = idx
                            phase = .game
                        }
                    } else if UserDefaults.standard.bool(forKey: "SkipSplash") || wantsSetup || wantsHelp {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation(.easeInOut(duration: 0.35)) { phase = .title }
                            if wantsSetup {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    showSetup = true
                                }
                            }
                            if wantsHelp {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    showHelp = true
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
                GameHUDView(hud: hud,
                            showsPause: hud.phase == .play,
                            onPause: { session.scene?.pause() },
                            onBack: { leaveToMenu() })
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
                    onQuit:   { leaveToSplash() },
                    onNext:   hud.phase == .win && nextGatePlayable
                              ? { session.scene?.nextLevel(); gameLevelIndex += 1 }
                              : nil,
                    worldJustCompleted: justFinishedWorld,
                    nextWorldLocked: justFinishedWorld != nil && !nextGatePlayable
                )
            }
        }
        .onChange(of: touch.left)  { _, _ in touch.push(to: session.scene) }
        .onChange(of: touch.right) { _, _ in touch.push(to: session.scene) }
        .onChange(of: touch.jump)  { _, _ in touch.push(to: session.scene) }
        .onChange(of: touch.down)  { _, _ in touch.push(to: session.scene) }
    }

    // MARK: - Helpers

    /// The world the loaded gate belongs to.
    private var currentWorld: World? {
        let gates = SettingsStore.shared.gates
        guard gates.indices.contains(gameLevelIndex) else { return nil }
        let id = gates[gameLevelIndex].world
        return Worlds.all.first { $0.id == id }
    }

    /// Name of the world whose final gate was just cleared — the moment a world
    /// becomes finished. Nil the rest of the time.
    private var justFinishedWorld: String? {
        guard hud.phase == .win, let world = currentWorld,
              SettingsStore.shared.worldComplete(world.id) else { return nil }
        return world.name
    }

    /// Whether the next gate can actually be played.
    ///
    /// This is the paywall's third door, and now the progression's second. The title
    /// screen refuses to open a locked world or a locked gate, but "Next gate" used
    /// to walk straight into either — so finishing the free world handed over the
    /// paid world for free. Asking the same question in the same place is what stops
    /// the three doors disagreeing.
    private var nextGatePlayable: Bool {
        SettingsStore.shared.gateUnlocked(gameLevelIndex + 1)
    }

    /// Wrap up the current gate before leaving it, wherever we are going.
    ///
    /// One definition on purpose. Saving on the way out is a rule that was already missed in
    /// one place once — "Next gate" ignored the paywall because three callers each answered
    /// the same question — and two exits duplicating this is exactly how that happens again.
    private func leaveCurrentGate() {
        // Keeping the gate's progress is the fix for "When leaving game to menu and there is a
        // progression then this is not saved. So player have to restart the level complete."
        // A gate that ended by running out of light is the exception: that one starts over,
        // which is what losing your last life means.
        if SettingsStore.shared.isOutOfLight {
            session.scene?.discardProgression()
            SettingsStore.shared.refillLives()
        } else {
            session.scene?.saveProgression()
        }
    }

    /// Back to the gates.
    private func leaveToMenu() {
        leaveCurrentGate()
        withAnimation(.easeInOut(duration: 0.25)) { phase = .title }
    }

    /// Back to the splash poster — the page the game opens on, which is what "the start page"
    /// means. Separate from `leaveToMenu()`, which goes to the gates; the HUD's back chevron
    /// is that one, so both destinations stay reachable.
    private func leaveToSplash() {
        leaveCurrentGate()
        withAnimation(.easeInOut(duration: 0.35)) { phase = .splash }
    }

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