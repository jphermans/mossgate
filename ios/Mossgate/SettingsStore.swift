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

    private init() {
        self.soundOn = UserDefaults.standard.object(forKey: "soundOn") as? Bool ?? true
        self.sfxOn = UserDefaults.standard.object(forKey: "sfxOn") as? Bool ?? true
        self.soundVolume = UserDefaults.standard.object(forKey: "soundVolume") as? Double ?? 0.5
        self.sfxVolume = UserDefaults.standard.object(forKey: "sfxVolume") as? Double ?? 0.7

        let totalLevels = Levels.all.count
        let savedCleared = (UserDefaults.standard.array(forKey: "cleared") as? [Bool]) ?? []
        self.cleared = (0..<totalLevels).map { savedCleared.indices.contains($0) ? savedCleared[$0] : false }

        let savedBest = (UserDefaults.standard.array(forKey: "bestCoins") as? [Int]) ?? []
        self.bestCoins = (0..<totalLevels).map { savedBest.indices.contains($0) ? savedBest[$0] : 0 }
    }

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
    }
}