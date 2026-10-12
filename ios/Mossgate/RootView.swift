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
    /// Which way an iPhone Duo is folded. `.unknown` everywhere else, and on a Duo it stays
    /// `.unknown` until the hinge actually reports — which is the safe direction to be wrong in.
    @State private var duoPose: DuoPose = .unknown

    enum Phase: Equatable { case splash, title, game }

    /// The one sentence the app says when the phone is shut. One place, because two copies of a
    /// message drift the moment either is edited.
    private var foldedNotice: String {
        "Open your iPhone Duo to play — Mossgate runs on the inner display."
    }

    /// Leaving the splash.
    ///
    /// The single place that decides it, because there are two ways to ask: the button and the
    /// whole-screen tap, both of which arrive through `onContinue`, plus the test hook that
    /// stands in for a tap. A rule repeated at three call sites drifts.
    ///
    /// Closed, the Duo shows this screen and nothing else. The outer display introduces the game
    /// but cannot host it, so rather than letting the player into a level list they cannot use,
    /// the tap says what to do instead.
    private func beginFromSplash() {
        guard duoPose.canPlay else {
            SettingsStore.shared.notice = foldedNotice
            return
        }
        withAnimation(.easeInOut(duration: 0.35)) { phase = .title }
    }

    /// The single place that decides whether a run may start, which is why it is a function
    /// and not two guards: the level cards and the daily card both come through here, and a
    /// rule repeated at two call sites is a rule that drifts.
    ///
    /// Closed, this should be unreachable — `beginFromSplash` keeps the level list away — but it
    /// stays as the backstop, because "the menu requires an open phone" is the actual rule and
    /// this is where a run is actually started.
    private func refuseIfFolded() -> Bool {
        guard !duoPose.canPlay else { return false }
        // Goes through the existing single alert channel rather than adding a second `.alert`
        // to this view — the file already notes that two alerts compete for the same parent.
        SettingsStore.shared.notice = foldedNotice
        return true
    }

    /// Portrait while the splash is up, and portrait again while a Duo is closed — the outer
    /// display is a portrait surface, so holding it upright there is right. Landscape otherwise:
    /// the level select and the game as designed.
    private func applyOrientationLock() {
        let mask: UIInterfaceOrientationMask =
            (phase == .splash || !duoPose.canPlay) ? .portrait : .landscape
        guard AppDelegate.orientationLock != mask else { return }
        AppDelegate.orientationLock = mask
        adopt(mask)
    }

    /// Asks the scene to actually adopt the mask that was just set.
    ///
    /// `setNeedsUpdateOfSupportedInterfaceOrientations()` alone is not enough. It re-evaluates
    /// what is permitted but leaves the current orientation where it is, so a change made while
    /// the app is already laid out — the splash handing over to the level list, or a Duo folding
    /// under a running app — is simply not acted on. `requestGeometryUpdate` is the call that
    /// asks for the rotation.
    ///
    /// That omission is what produced the black screen: on a folded Duo the first lock applied a
    /// landscape mask to a portrait display, and every later correction was accepted and ignored,
    /// so the app sat there drawing nothing for the rest of the session.
    private func adopt(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            print("[orientation] could not adopt \(mask): \(error.localizedDescription)")
        }
    }

    var body: some View {
        ZStack {
            Color("MossgateDusk").ignoresSafeArea()

            switch phase {
            case .splash:
                SplashView { beginFromSplash() }
                .transition(.opacity)
            case .title:
                TitleView(
                    onStartLevel: { idx in
                        if refuseIfFolded() { return }
                        // The title screen already refuses, but a locked gate must not
                        // be reachable by any other caller either.
                        guard SettingsStore.shared.gateUnlocked(idx) else {
                            // Name the gate that is in the way, in the same voice the locked-world
                            // tap already uses. "That gate is still locked" was true and useless:
                            // the player is looking at a list where several rows are locked, and
                            // it did not say which one was blocking this one or what opened it.
                            let all = Levels.all
                            let prev = (idx > 0 && idx - 1 < all.count)
                                ? all[idx - 1].name : "the gate before it"
                            SettingsStore.shared.notice = "Finish \(prev) to open this one."
                            return
                        }
                        // Starting a level dismisses anything the alert was still showing. A
                        // notice set minutes ago — a locked tap, a Duo refusal, a Coin Rush
                        // result — otherwise sits on screen through the level change, so it looks
                        // like the tap produced it. That is exactly how a stale "finish the
                        // previous gate" alert came to look like it fired on an unlocked one.
                        SettingsStore.shared.notice = nil
                        Store.shared.message = nil
                        gameLevelIndex = idx
                        withAnimation(.easeInOut(duration: 0.25)) { phase = .game }
                    },
                    onStartDaily: { idx in
                        if refuseIfFolded() { return }
                        // Deliberately not guarded. The daily is free for everyone by design,
                        // and the gate it lives on is behind the progression chain, so the
                        // ordinary unlock check would refuse it — which is precisely what
                        // happened, silently: "nothing happens when I tap daily".
                        SettingsStore.shared.startDailyRun()
                        gameLevelIndex = idx
                        withAnimation(.easeInOut(duration: 0.25)) { phase = .game }
                    },
                    onStartCoinRush: { idx in
                        gameLevelIndex = idx
                        withAnimation(.easeInOut(duration: 0.25)) { phase = .game }
                    },
                    onStartEndless: { idx in
                        // Not guarded, for the same reason the daily is not: the world was just
                        // rebuilt from a fresh seed, so there is no gate of this run to unlock.
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
        .overlay(alignment: .topLeading) {
            // Reads the Duo hinge. One point in the corner: `UIHingeInteraction` has to live in
            // a view hierarchy to receive updates, and a zero-sized view is not guaranteed to.
            HingeReader { duoPose = $0 }
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
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
        // One channel for both: a Store message and a gameplay notice would otherwise be two
        // alerts competing for the same view. Drawn in the game's own style rather than the
        // system's — see MossgateAlert.
        .overlay {
            if let message = store.message ?? SettingsStore.shared.notice {
                MossgateAlert(message: message) {
                    store.message = nil
                    SettingsStore.shared.notice = nil
                }
                .transition(.opacity)
            }
        }
        // A reshuffle rebuilds the current level so the new world is visible
        // immediately. Setup is only reachable from the title screen, so no
        // in-level progress is lost.
        .onReceive(SettingsStore.shared.$runSeed) { _ in
            session.scene?.retryLevel()
        }
        .onChange(of: duoPose) { _, newPose in
            applyOrientationLock()
            // Closing the phone returns to the splash.
            //
            // The outer display introduces the game but cannot host a run, so leaving whatever
            // was on screen sitting behind it would be worse than showing the app's own front
            // door. Going through `leaveToSplash()` rather than setting `phase` directly is the
            // part that matters: it calls `leaveCurrentGate()` first, which SAVES the gate's
            // progress, so folding the phone mid-run costs nothing and reopening and returning
            // to that gate carries on where it left off.
            //
            // Only fires on the transition into `.closed`, so the player can still fold the
            // phone, see the splash, tap through and browse the level list with it shut.
            if newPose == .closed, phase != .splash { leaveToSplash() }
        }
        // The mask also has to follow the phase — portrait while the splash is up,
        // landscape for the level list and the game. The handler above covers the display
        // changing underneath; this covers the app moving between its own screens.
        .onChange(of: phase) { _, _ in applyOrientationLock() }
        .onAppear {
                    wireController()
                    // Warm the taptic engine up front, so the first jump of a session is felt as
                    // clearly as the hundredth rather than arriving while the engine is cold.
                    Haptics.warmUp()
                    Store.shared.start()
                    // Test hook: -TestSfx 1 renders every effect through the real
                    // audio graph offline and reports the level that comes out.
                    if ProcessInfo.processInfo.arguments.contains("-TestSfx") {
                        AudioEngine.shared.runSfxProbe()
                    }
                    // Seed the pose from the window's own size BEFORE any orientation lock is
                    // applied.
                    //
                    // Read from the key window rather than the scene's coordinate space: at
                    // `onAppear` the scene exists but its bounds can still be zero, and a zero
                    // size classifies as `.unknown` — which means landscape, which on a folded
                    // Duo is the black screen. The window is sized by the time this runs.
                    if let keyWindow = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .flatMap(\.windows)
                        .first(where: { $0.isKeyWindow }),
                       keyWindow.bounds.width > 0, keyWindow.bounds.height > 0 {
                        duoPose = DuoPose.fromWindowSize(keyWindow.bounds.size)
                    }
                    AppDelegate.orientationLock = .portrait
                    let args = ProcessInfo.processInfo.arguments
                    // Test hook: -ForceClosed 1 / -ForceOpen 1 pretend the Duo is shut or open,
                    // so the outer-display layout and the refusal can be exercised on any
                    // simulator. The simulator exposes one framebuffer per display but has no
                    // headless way to fold the device, so without these the closed path would
                    // be unverifiable on this machine.
                    if args.contains("-ForceClosed") { DuoPose.forced = .closed; duoPose = .closed }
                    else if args.contains("-ForceOpen") { DuoPose.forced = .open; duoPose = .open }
                    // Test hook: -ForceCloseAfter <seconds> opens first, then folds part-way
                    // through the session. The interesting behaviour is the TRANSITION into
                    // closed — returning to the splash and saving the run — and the simulator
                    // cannot fold the device, so without this the rule would only ever be
                    // exercised in its initial state, which is the case that already worked.
                    else if let ci = args.firstIndex(of: "-ForceCloseAfter"),
                            ci + 1 < args.count, let secs = Double(args[ci + 1]) {
                        DuoPose.forced = .open; duoPose = .open
                        DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
                            DuoPose.forced = .closed; duoPose = .closed
                        }
                    }
                    // Test hook: -ShowNotice 1 raises the app's own alert at launch, so the
                    // styled panel can be inspected without a simulator tap. The simulator
                    // cannot press a gate card, and this is the only visible path to it.
                    if args.contains("-ShowNotice") { SettingsStore.shared.notice = foldedNotice }
                    // Test hook: -TapBegin 1 does what "Tap to begin" does, through the same
                    // function the button and the whole-screen tap use. The simulator cannot tap,
                    // so without this the splash's gate would be unverifiable — and routing it
                    // through `beginFromSplash` means it cannot drift from the real path.
                    if args.contains("-TapBegin"), phase == .splash { beginFromSplash() }
                    // Test hook: -CoinRush 1 starts a timed run immediately. The card cannot be
                    // pressed on a simulator, so without this the clock, its countdown and the
                    // moment it ends would all be unverifiable.
                    // Deferred like -StartInLevel: -SkipSplash's own transition runs a beat later,
                    // and setting the phase here immediately would simply be overwritten by it.
                    if args.contains("-CoinRush") {
                        // Later than -SkipSplash's own 0.4s transition, not alongside it: two timers
                        // at the same deadline resolve by luck, and this one has to land second to
                        // survive.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                            SettingsStore.shared.startCoinRushRun()
                            gameLevelIndex = 0
                            withAnimation(.easeInOut(duration: 0.25)) { phase = .game }
                        }
                    }
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
                    // Retry carries on from the last waystone, not from the top of the gate.
                    //
                    // These two buttons used to do the same thing — restart the level — which
                    // meant `respawnAtCheckpoint()` was unreachable from the UI and the Help
                    // screen's promise ("you carry on from the last waystone you touched") was
                    // never kept. Reported as "relight seems not to go to the last position".
                    onRetry: (hud.phase == .gameOver)
                             ? {
                                 SettingsStore.shared.refillLives()
                                 session.scene?.respawnAtCheckpoint()
                               }
                             : { session.scene?.respawnAtCheckpoint() },
                    onRestart: (hud.phase == .gameOver)
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
        .onChange(of: touch.up)    { _, _ in touch.push(to: session.scene) }
        // Record a finished Daily Gate.
        //
        // Guarded on the run seed still being today's: the ordinary worlds share this phase
        // change, and a gate cleared in a normal run must never count towards the daily.
        .onChange(of: hud.phase) { _, newPhase in
            guard newPhase == .win, SettingsStore.shared.runSeed == DailyGate.seed() else { return }
            DailyGate.noteWin(coins: hud.coins)
        }
        // -DemoPlay 1: get off a death screen so filming can continue.
        //
        // Observed here rather than polled by a timer, because a timer closure capturing the
        // HUD reads a stale snapshot of the phase and its guard never fires — three takes sat
        // on the death panel for 40+ seconds apiece because of exactly that. A view body's
        // .onChange sees the real published value.
        //
        // Pause and win are deliberately not handled: neither is a dead end for a robot.
        .onChange(of: hud.phase) { _, newPhase in
            guard DemoMode.active,
                  newPhase == .dead || newPhase == .gameOver else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                SettingsStore.shared.refillLives()
                session.scene?.retryLevel()
            }
        }
        // -DemoPlay 1 — drives the game for filming, so it lives HERE rather than in the scene.
        //
        // Setting touch state on the scene directly does not work: the HUD pushes its own
        // TouchState to the scene, which overwrites whatever the scene set for itself, and a
        // layout pass can replace the scene object outright. Two recordings made that way were
        // 43 and 46 seconds of a character standing perfectly still. Going through the same
        // TouchState the on-screen buttons use means nothing can overwrite it.
        .onAppear {
            guard ProcessInfo.processInfo.arguments.contains("-DemoPlay") else { return }
            DemoMode.active = true
            DemoMode.driver = touch
            touch.right = true
            // Tighter than a human would play, because the demo cannot see brambles coming.
            _ = Timer.scheduledTimer(withTimeInterval: 0.34, repeats: true) { _ in
                guard DemoMode.active else { return }
                // A tap, not a hold — the game reads the jump on the rising edge.
                touch.jump = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { touch.jump = false }
            }
            // Let go on a deadline. A test flag must never be able to leave the game playing
            // itself indefinitely — that is what this harness did before DemoMode existed.
            DispatchQueue.main.asyncAfter(deadline: .now() + DemoMode.deadline) { DemoMode.stop() }
        }
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
                                      jump: input.jump, down: input.down, up: input.up)
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