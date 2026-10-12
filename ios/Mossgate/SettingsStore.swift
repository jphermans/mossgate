import Foundation
import Combine

/// Player settings — sound (ambient/music) toggle, SFX toggle.
/// Persisted in UserDefaults so they survive app restarts.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var soundOn: Bool {
        didSet { UserDefaults.standard.set(soundOn, forKey: "soundOn") }
    }
    @Published var sfxOn: Bool {
        didSet { UserDefaults.standard.set(sfxOn, forKey: "sfxOn") }
    }
    /// On by default, like the sound settings, and the only one that costs nothing to leave on:
    /// a taptic pulse is silent, so it cannot annoy anyone nearby the way music can.
    @Published var hapticsOn: Bool {
        didSet { UserDefaults.standard.set(hapticsOn, forKey: "hapticsOn") }
    }
    @Published var soundVolume: Double {
        didSet { UserDefaults.standard.set(soundVolume, forKey: "soundVolume") }
    }
    @Published var sfxVolume: Double {
        didSet { UserDefaults.standard.set(sfxVolume, forKey: "sfxVolume") }
    }

    /// Use a paired game controller. On by default — a pad is strictly better
    /// than the on-screen buttons, but the toggle lets someone turn it off if a
    /// drifting stick is causing trouble.
    @Published var controllerOn: Bool {
        didSet { UserDefaults.standard.set(controllerOn, forKey: "controllerOn") }
    }

    /// Seed for the current run. Every restart reshuffles the worlds — sky
    /// palette, starfield, mover timing and pickup placement all derive from it,
    /// so a level never looks or plays quite the same twice.
    ///
    /// Deliberately NOT persisted: a new launch is a new world. (Relaunching to
    /// see what you get is the point.)
    @Published private(set) var runSeed: Int = {
        // Test hook: -Seed N forces a seed so two runs can be compared.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-Seed"), i + 1 < args.count,
           let n = Int(args[i + 1]) { return n }
        return Int.random(in: 1...999_999)
    }()

    /// The run's gate list. Rebuilt when the seed changes, and cached here so the
    /// title screen does not regenerate 36 gates on every layout pass.
    @Published private(set) var gates: [Level] = []

    /// Roll a fresh set of worlds without relaunching.
    func newRun() {
        runSeed = Int.random(in: 1...999_999)
        gates = Levels.build(seed: runSeed)
    }

    /// Start today's Daily Gate.
    ///
    /// The run's gates are rebuilt from the date's seed, which is what makes the gate identical
    /// for every player. It costs the player nothing: the seed is deliberately not persisted, so
    /// a launch is a new world anyway, and progress is keyed on `gateKey` rather than on the
    /// seed, so no progress depends on which seed is in force.
    // MARK: - Coin Rush

    /// A timed grab: as many coins as you can reach before the clock runs out.
    ///
    /// A property of the run like Endless, and the only mode with a deadline. The gate is an
    /// ordinary generated one — coins are already scattered where they are hard to reach, which
    /// is what makes a time limit interesting rather than busywork.
    @Published private(set) var coinRushRun = false
    @Published private(set) var coinRushLeft = 0

    static let coinRushSeconds = 45

    var coinRushBest: Int { UserDefaults.standard.integer(forKey: "coinRushBest") }

    func startCoinRushRun() {
        coinRushRun = true
        coinRushLeft = SettingsStore.coinRushSeconds
        runSeed = Int.random(in: 1...999_999)
        gates = Levels.build(seed: runSeed)
    }

    /// One second gone.
    func tickCoinRush() {
        guard coinRushRun, coinRushLeft > 0 else { return }
        coinRushLeft -= 1
    }

    /// The clock beat you, or you left. The coin count is whatever the HUD had at that moment.
    func endCoinRushRun(coins: Int) {
        if coins > coinRushBest { UserDefaults.standard.set(coins, forKey: "coinRushBest") }
        coinRushRun = false
        coinRushLeft = 0
    }

    // MARK: - Endless Run

    /// Whether the current run is an Endless one.
    ///
    /// A property of the RUN rather than a setting, like the daily's seed: it begins when the
    /// card is tapped and ends when the run does, and nothing persists it.
    @Published private(set) var endlessRun = false

    /// Gates reached in this Endless run.
    @Published private(set) var endlessGates = 0

    /// The best chain so far. Persisted, because a personal best that vanishes on relaunch is
    /// not a personal best.
    var endlessBest: Int { UserDefaults.standard.integer(forKey: "endlessBest") }

    /// Start an Endless run: a fresh world, and a chain to see how far it goes.
    ///
    /// A new seed rather than the current one, so the chain is not a repeat of whatever the
    /// player was just looking at — the appeal is not knowing what is next.
    func startEndlessRun() {
        endlessRun = true
        endlessGates = 0
        runSeed = Int.random(in: 1...999_999)
        gates = Levels.build(seed: runSeed)
    }

    /// One more gate behind us. Returns how many that makes.
    @discardableResult
    func noteEndlessGate() -> Int {
        endlessGates += 1
        if endlessGates > endlessBest { UserDefaults.standard.set(endlessGates, forKey: "endlessBest") }
        return endlessGates
    }

    /// Leaving the mode, or it ending. Never persisted, so this only has to be true for the
    /// life of the run.
    func endEndlessRun() {
        endlessRun = false
        endlessGates = 0
    }

    func startDailyRun() {
        runSeed = DailyGate.seed()
        gates = Levels.build(seed: runSeed)
    }

    // MARK: - The full game, and world progression

    /// Whether the single in-app purchase is owned. Written by `Store` and read by
    /// the gating rule below, so the paywall has exactly one definition.
    @Published var hasFullGame = false

    /// One-shot message for the player, shown as an alert and cleared on dismiss.
    @Published var notice: String?

    /// Finished every gate in a world. The gate count is fixed even though the
    /// layouts are not, which is what makes this stable across runs.
    func worldComplete(_ world: Int) -> Bool {
        let base = world * Worlds.gatesPerWorld
        guard base >= 0, base + Worlds.gatesPerWorld <= cleared.count else { return false }
        return (base..<base + Worlds.gatesPerWorld).allSatisfy { cleared[$0] }
    }

    /// A world is playable when it is the free one, or when the full game is owned
    /// AND every world before it is finished. Two rules, in that order: the paywall
    /// first, then the progression.
    func worldUnlocked(_ world: Int) -> Bool {
        if Worlds.all.first(where: { $0.id == world })?.free == true { return true }
        guard hasFullGame else { return false }
        return (0..<world).allSatisfy { worldComplete($0) }
    }

    /// Whether a gate can be played.
    ///
    /// Two rules stacked: its world has to be open, and within the world the gates
    /// are taken in order — each one opens when the one before it is cleared. The
    /// first gate of a world needs no ancestor, only the world itself.
    func gateUnlocked(_ key: Int) -> Bool {
        let world = Levels.world(of: key)
        let slot = Levels.slot(of: key)
        guard worldUnlocked(world) else { return false }
        if slot == 0 { return true }
        let previous = key - 1
        guard previous >= 0, previous < cleared.count else { return false }
        return cleared[previous]
    }

    /// Why a gate cannot be played yet, or nil when it can. Shown on its row.
    func gateLockReason(_ key: Int) -> String? {
        if gateUnlocked(key) { return nil }
        return "Finish the gate before it"
    }

    /// Why a world cannot be played yet, or nil when it can. Shown on its card.
    func worldLockReason(_ world: Int) -> String? {
        if worldUnlocked(world) { return nil }
        if !hasFullGame { return "Full game" }
        let prev = Worlds.all.first { $0.id == world - 1 }
        return "Finish \(prev?.name ?? "the world before")"
    }

    /// Per-level progress (cleared + best coin count), persisted across launches.
    @Published var cleared: [Bool]
    @Published var bestCoins: [Int]

    /// The player's remaining light. Starts (and caps) at 3. Losing a life is
    /// "the wick went out"; clearing a level or picking up a lantern refills one.
    /// Persisted so progress survives a relaunch.
    @Published private(set) var lives: Int
    static let maxLives = 3

    private init() {
        self.soundOn = UserDefaults.standard.object(forKey: "soundOn") as? Bool ?? true
        self.sfxOn = UserDefaults.standard.object(forKey: "sfxOn") as? Bool ?? true
        self.hapticsOn = UserDefaults.standard.object(forKey: "hapticsOn") as? Bool ?? true
        self.soundVolume = UserDefaults.standard.object(forKey: "soundVolume") as? Double ?? 0.5
        self.sfxVolume = UserDefaults.standard.object(forKey: "sfxVolume") as? Double ?? 0.7
        self.controllerOn = UserDefaults.standard.object(forKey: "controllerOn") as? Bool ?? true

        self.lives = UserDefaults.standard.object(forKey: "lives") as? Int ?? SettingsStore.maxLives

        // A constant, not Levels.all.count: this runs while the singleton is being
        // built, and Levels.all reads the run seed back off it.
        let totalLevels = Levels.totalGates
        let savedCleared = (UserDefaults.standard.array(forKey: "cleared") as? [Bool]) ?? []
        self.cleared = (0..<totalLevels).map { savedCleared.indices.contains($0) ? savedCleared[$0] : false }

        let savedBest = (UserDefaults.standard.array(forKey: "bestCoins") as? [Int]) ?? []
        self.bestCoins = (0..<totalLevels).map { savedBest.indices.contains($0) ? savedBest[$0] : 0 }

        self.gateProgress = UserDefaults.standard.data(forKey: "gateProgress")
            .flatMap { try? JSONDecoder().decode([String: GateSnapshot].self, from: $0) } ?? [:]

        self.gates = Levels.build(seed: runSeed)

        // Test hook: -CompleteWorld N marks every gate in world N as cleared, so the
        // finished-world state can be seen and photographed without playing six
        // gates. In-memory only — nothing is written to UserDefaults.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-CompleteWorld"), i + 1 < args.count,
           let w = Int(args[i + 1]) {
            let base = w * Worlds.gatesPerWorld
            for k in base..<min(base + Worlds.gatesPerWorld, cleared.count) {
                cleared[k] = true
            }
        }
    }

    // MARK: - Light / lives

    /// Called on death. Returns the new total.
    @discardableResult
    func loseLife() -> Int {
        lives = max(0, lives - 1)
        UserDefaults.standard.set(lives, forKey: "lives")
        return lives
    }

    /// Called on level clear or lantern pickup. Returns the new total.
    /// Capped at `maxLives`.
    @discardableResult
    func gainLife() -> Int {
        lives = min(SettingsStore.maxLives, lives + 1)
        UserDefaults.standard.set(lives, forKey: "lives")
        return lives
    }

    /// Refill to full — used when the player runs out and starts a fresh run.
    func refillLives() {
        lives = SettingsStore.maxLives
        UserDefaults.standard.set(lives, forKey: "lives")
    }

    var isOutOfLight: Bool { lives <= 0 }

    // ── Where a gate was left ─────────────────────────────────────
    /// Enough to put the player back where they were.
    ///
    /// Reported as: "When leaving game to menu and there is a progression then this
    /// is not saved. So player have to restart the level complete." The scene already
    /// held all of this for its checkpoints; the missing part was any of it surviving
    /// the gate being torn down.
    struct GateSnapshot: Codable {
        var coins: [Int]
        var lanterns: [Int]
        var checkpoint: Int
        var x: Double
        var y: Double
        /// The run seed the gate was built from. Gates are regenerated every run
        /// (worlds change on each restart, by design), so a snapshot from another run
        /// describes geometry that does not exist in this one. It is discarded rather
        /// than trusted, or the player resumes inside a wall.
        var seed: Int
    }

    @Published private(set) var gateProgress: [String: GateSnapshot]

    func gateProgress(for level: Int) -> GateSnapshot? { gateProgress["\(level)"] }

    func saveGateProgress(_ snap: GateSnapshot, level: Int) {
        gateProgress["\(level)"] = snap
        persistGateProgress()
    }

    func clearGateProgress(for level: Int) {
        guard gateProgress.removeValue(forKey: "\(level)") != nil else { return }
        persistGateProgress()
    }

    private func persistGateProgress() {
        guard let data = try? JSONEncoder().encode(gateProgress) else { return }
        UserDefaults.standard.set(data, forKey: "gateProgress")
    }

    func markCleared(level: Int, coins: Int) {
        guard level < cleared.count else { return }
        cleared[level] = true
        bestCoins[level] = max(bestCoins[level], coins)
        UserDefaults.standard.set(cleared, forKey: "cleared")
        UserDefaults.standard.set(bestCoins, forKey: "bestCoins")
        // The gate is finished, so there is nothing to resume into.
        clearGateProgress(for: level)
    }

    func resetProgress() {
        cleared = Array(repeating: false, count: Levels.totalGates)
        bestCoins = Array(repeating: 0, count: Levels.totalGates)
        UserDefaults.standard.removeObject(forKey: "cleared")
        UserDefaults.standard.removeObject(forKey: "bestCoins")
        gateProgress = [:]
        UserDefaults.standard.removeObject(forKey: "gateProgress")
        refillLives()
    }
}

extension SettingsStore {
    /// Adopt a seed someone shared.
    ///
    /// `runSeed` is `private(set)`, and this lives in the same file, which is the only place
    /// allowed to write it. It mirrors the reshuffle path: rebuild the gates from the new seed
    /// and let everything keyed on the seed follow. The per-run snapshot is keyed on the seed
    /// already, so a new seed is a new key rather than stale progress.
    ///
    /// Clamped to the range the randomiser draws from, so a mistyped or hostile number cannot
    /// produce a seed no real run would ever have.
    func useSeed(_ seed: Int) {
        let clamped = min(max(seed, 1), 999_999)
        guard clamped != runSeed else { return }
        runSeed = clamped
        gates = Levels.build(seed: clamped)
    }
}


/// How well a gate has been played, judged by the best coin run against that gate's total.
///
/// Thresholds are thirds, and the top tier is all of them: a medal for reaching the flag would
/// be a medal for turning up, and every gate is reachable. The tiers only mean anything because
/// coins can be missed — they are placed where they are hard to collect, not sprinkled on the
/// path.
///
/// `nil` for none rather than a colour that happens to look like background: a gate nobody has
/// cleared well should show no medal at all, not a dim one.
enum GateMedal {
    case none, bronze, silver, gold

    /// One glyph for all three tiers; the tint carries the meaning. Three different symbols
    /// would need three glyphs that exist on every supported OS, and the app's palette already
    /// reads a colour change better than a shape change at 9pt.
    var symbol: String? { self == .none ? nil : "star.fill" }

    /// The palette NAME, not a `Color`. This file is data, not UI, and it does not import
    /// SwiftUI — resolving the name is the view's job.
    var tintName: String {
        switch self {
        case .none:   return "MossgateMuted"
        case .gold:   return "MossgateLantern"
        case .silver: return "MossgateCream"
        case .bronze: return "MossgateMuted"
        }
    }
}

extension SettingsStore {
    /// The medal for a gate, given its coin total.
    func medal(for level: Int, of total: Int) -> GateMedal {
        guard total > 0, level < bestCoins.count else { return .none }
        let best = bestCoins[level]
        if best >= total { return .gold }
        let ratio = Double(best) / Double(total)
        if ratio >= 2.0 / 3.0 { return .silver }
        if ratio >= 1.0 / 3.0 { return .bronze }
        return .none
    }
}
