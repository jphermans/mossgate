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

        self.lives = UserDefaults.standard.object(forKey: "lives") as? Int ?? SettingsStore.maxLives

        let totalLevels = Levels.all.count
        let savedCleared = (UserDefaults.standard.array(forKey: "cleared") as? [Bool]) ?? []
        self.cleared = (0..<totalLevels).map { savedCleared.indices.contains($0) ? savedCleared[$0] : false }

        let savedBest = (UserDefaults.standard.array(forKey: "bestCoins") as? [Int]) ?? []
        self.bestCoins = (0..<totalLevels).map { savedBest.indices.contains($0) ? savedBest[$0] : 0 }
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
        cleared = Array(repeating: false, count: Levels.all.count)
        bestCoins = Array(repeating: 0, count: Levels.all.count)
        UserDefaults.standard.removeObject(forKey: "cleared")
        UserDefaults.standard.removeObject(forKey: "bestCoins")
        refillLives()
    }
}