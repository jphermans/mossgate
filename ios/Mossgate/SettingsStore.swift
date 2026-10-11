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

    func markCleared(level: Int, coins: Int) {
        guard level < cleared.count else { return }
        cleared[level] = true
        bestCoins[level] = max(bestCoins[level], coins)
        UserDefaults.standard.set(cleared, forKey: "cleared")
        UserDefaults.standard.set(bestCoins, forKey: "bestCoins")
    }

    func resetProgress() {
        cleared = Array(repeating: false, count: Levels.totalGates)
        bestCoins = Array(repeating: 0, count: Levels.totalGates)
        UserDefaults.standard.removeObject(forKey: "cleared")
        UserDefaults.standard.removeObject(forKey: "bestCoins")
        refillLives()
    }
}