import Foundation
import GameKit
import UIKit

/// GameKit integration. The achievement and leaderboard identifiers below
/// are placeholders that match what a typical App Store Connect registration
/// looks like. They only start reporting once a real Apple Developer Team
/// ID is wired and the identifiers are registered in App Store Connect.
///
/// Until then, calls become silent no-ops so the game is fully playable
/// without Game Center configured. The auth flow still runs (it just falls
/// back to "not signed in"), so the UI is correct.
final class GameCenterManager: NSObject, ObservableObject {
    static let shared = GameCenterManager()

    /// Public so SwiftUI views can show "Sign in to Game Center" / hide the
    /// button when already authenticated.
    @Published private(set) var isAuthenticated = false
    @Published private(set) var lastError: String?
    @Published private(set) var displayName: String = ""

    /// Replace these with the real identifiers from App Store Connect.
    /// Each achievement and each per-level leaderboard needs its own ID.
    enum ID {
        // Achievements
        static let firstClear        = "grp.mossgate.first_clear"
        static let allCoinsLevel     = "grp.mossgate.all_coins_level"
        static let world1Cleared     = "grp.mossgate.world_1_cleared"
        static let world2Cleared     = "grp.mossgate.world_2_cleared"
        static let noDeathRun        = "grp.mossgate.no_death_run"
        // Leaderboards (per-level, score = coin count)
        static func levelLeaderboard(_ levelId: Int) -> String {
            "grp.mossgate.level_\(levelId)_best"
        }
        // Global leaderboard: total coins across all levels
        static let totalCoinsLeaderboard = "grp.mossgate.total_coins"
    }

    private override init() {
        super.init()
        authenticate()
    }

    /// Trigger the system Game Center sign-in flow. Idempotent — if the player
    /// is already signed in, the system just hands back the existing player.
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] gc, error in
            guard let self else { return }
            Task { @MainActor in
                self.isAuthenticated = (gc != nil)
                self.lastError = error?.localizedDescription
                if let player = gc as? GKLocalPlayer {
                    self.displayName = player.displayName
                }
            }
        }
    }

    /// Report an achievement (e.g. "Cleared all of World 1").
    /// Silently no-ops if the player isn't signed in.
    func reportAchievement(id: String, percent: Double = 100.0) {
        guard isAuthenticated else { return }
        let achievement = GKAchievement(identifier: id)
        achievement.percentComplete = percent
        achievement.showsCompletionBanner = true
        GKAchievement.report([achievement]) { error in
            if let error { print("[GameCenter] achievement \(id): \(error)") }
        }
    }

    /// Submit a coin score for a single level.
    func submitLevelScore(level: Int, coins: Int) {
        guard isAuthenticated else { return }
        let score = GKScore(leaderboardIdentifier: ID.levelLeaderboard(level))
        score.value = Int64(coins)
        GKScore.report([score]) { error in
            if let error { print("[GameCenter] score \(level): \(error)") }
        }
    }

    /// Submit the global "total coins across all cleared levels" score.
    func submitTotalScore(_ totalCoins: Int) {
        guard isAuthenticated else { return }
        let score = GKScore(leaderboardIdentifier: ID.totalCoinsLeaderboard)
        score.value = Int64(totalCoins)
        GKScore.report([score]) { error in
            if let error { print("[GameCenter] total score: \(error)") }
        }
    }

    /// Open the Game Center dashboard (used from the title screen).
    func openDashboard(presenter: UIViewController?) {
        guard isAuthenticated else {
            // Try to authenticate, then show a hint if that fails.
            authenticate()
            return
        }
        let gc = GKGameCenterViewController(state: .default)
        gc.gameCenterDelegate = self
        presenter?.present(gc, animated: true)
    }
}

extension GameCenterManager: GKGameCenterControllerDelegate {
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}

/// Convenience hooks called from the scene when something noteworthy happens.
enum Achievements {
    /// Call this when a level is completed. Reports:
    ///  - first_clear the first time any level is cleared
    ///  - all_coins_level the first time the player grabs every coin in a level
    ///  - world_1_cleared / world_2_cleared when every level in a world is cleared
    /// Also submits the per-level score and the running total.
    static func levelCleared(_ level: Level, coins: Int, totalCoins: Int, allCoinsCollected: Bool) {
        let gc = GameCenterManager.shared
        // First clear of any level
        if SettingsStore.shared.cleared.firstIndex(of: true) == nil {
            gc.reportAchievement(id: GameCenterManager.ID.firstClear)
        }
        // All coins in this level
        if allCoinsCollected {
            gc.reportAchievement(id: GameCenterManager.ID.allCoinsLevel)
        }
        // All-of-world cleared
        if level.world == 0 {
            let allCleared = (0..<Levels.count(in: 0)).allSatisfy { id in
                SettingsStore.shared.cleared.indices.contains(id) && SettingsStore.shared.cleared[id]
            }
            if allCleared { gc.reportAchievement(id: GameCenterManager.ID.world1Cleared) }
        } else if level.world == 1 {
            let allCleared = (0..<Levels.count(in: 1)).allSatisfy { id in
                let i = id + Levels.count(in: 0)
                return SettingsStore.shared.cleared.indices.contains(i) && SettingsStore.shared.cleared[i]
            }
            if allCleared { gc.reportAchievement(id: GameCenterManager.ID.world2Cleared) }
        }
        gc.submitLevelScore(level: level.id, coins: coins)
        gc.submitTotalScore(totalCoins)
    }
}