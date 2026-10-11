import Foundation
import GameKit
import UIKit

/// GameKit integration. The achievement and leaderboard identifiers are
/// placeholders — they only work once you've wired a real Apple Developer
/// Team ID and registered the identifiers in App Store Connect.
///
/// Until then, calls become silent no-ops, so the game is fully playable
/// without Game Center configured.
final class GameCenterManager: NSObject, ObservableObject {
    static let shared = GameCenterManager()

    @Published var isAuthenticated = false
    @Published var lastError: String?

    private override init() {
        super.init()
        GKLocalPlayer.local.authenticateHandler = { [weak self] gc, error in
            guard let self else { return }
            Task { @MainActor in
                self.isAuthenticated = (gc != nil)
                self.lastError = error?.localizedDescription
            }
        }
    }

    /// Report an achievement (e.g. "Cleared all of World 1").
    /// Identifier `nil` means the achievement isn't registered yet — we just
    /// log locally and move on. Once you set up Game Center in App Store Connect,
    /// swap the placeholder IDs below for real ones.
    func reportAchievement(id: String, percent: Double = 100.0) {
        guard isAuthenticated else { return }
        let achievement = GKAchievement(identifier: id)
        achievement.percentComplete = percent
        achievement.showsCompletionBanner = true
        GKAchievement.report([achievement]) { error in
            if let error { print("[GameCenter] achievement \(id): \(error)") }
        }
    }

    /// Submit a coin score for a level.
    func submitScore(level: Int, coins: Int) {
        guard isAuthenticated else { return }
        let score = GKScore(leaderboardIdentifier: "level_\(level)_best")
        score.value = Int64(coins)
        GKScore.report([score]) { error in
            if let error { print("[GameCenter] score \(level): \(error)") }
        }
    }

    /// Open the Game Center dashboard (used from the title screen).
    func openDashboard(presenter: UIViewController?) {
        guard isAuthenticated else { return }
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
    static func levelCleared(_ level: Level) {
        // First clear of any level
        if level.id == 0 {
            GameCenterManager.shared.reportAchievement(id: "first_clear")
        }
        // All-of-world-1 clear
        if level.world == 0 {
            let allCleared = (0..<Levels.count(in: 0)).allSatisfy { id in
                SettingsStore.shared.cleared.indices.contains(id) && SettingsStore.shared.cleared[id]
            }
            if allCleared {
                GameCenterManager.shared.reportAchievement(id: "world_1_cleared")
            }
        }
        GameCenterManager.shared.submitScore(level: level.id, coins: SettingsStore.shared.bestCoins[level.id])
    }
}