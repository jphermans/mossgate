import Foundation

/// The Daily Gate: one gate, one seed per calendar day, identical for everybody.
///
/// Asked for as a mini-game, and chosen as the first of three. It is deliberately built out of
/// what already exists — a seed produces the whole world set (`Levels.build(seed:)`), the
/// generated gates are already traversable by construction, and a player's progress is keyed
/// on `gateKey` rather than on the seed — so "today's gate" is a seed and an index rather than
/// a new game.
enum DailyGate {
    /// The seed for a given day.
    ///
    /// Derived from the date alone, with no per-device salt, so every player in the world gets
    /// the same gate. That is the whole point of a daily, and it would be easy to lose by
    /// mixing in a device id or the local time zone.
    static func seed(for date: Date = Date()) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 2026) * 10_000 + (c.month ?? 1) * 100 + (c.day ?? 1)
    }

    /// Days since the epoch, for the streak and for "played today".
    static func dayNumber(for date: Date = Date()) -> Int {
        Int(date.timeIntervalSince1970 / 86_400)
    }

    /// UTC deliberately: the gate has to change at one moment for everyone, and a per-device
    /// midnight would hand some players tomorrow's gate while others were still on today's.
    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal
    }

    /// Which gate of the day's set is today's.
    ///
    /// Rotates by day so it is not the same slot every time, and sits in a mid-difficulty world
    /// so a player meeting it early is not thrown straight at the hardest thing in the game.
    static let world = 2
    static var slot: Int { dayNumber() % Worlds.gatesPerWorld }
    /// Index into the seed's gate list.
    static var gateIndex: Int { world * Worlds.gatesPerWorld + slot }

    // MARK: - Your run

    private static let bestCoinsKey = "dailyBestCoins"
    private static let bestDayKey = "dailyBestDay"
    private static let streakKey = "dailyStreak"
    private static let lastDayKey = "dailyLastDay"

    static var bestCoins: Int { UserDefaults.standard.integer(forKey: bestCoinsKey) }
    static var bestDay: Int { UserDefaults.standard.integer(forKey: bestDayKey) }
    static var streak: Int { UserDefaults.standard.integer(forKey: streakKey) }

    /// Whether today's gate has already been finished. The card says so rather than hiding
    /// itself: a daily you cannot take twice is still worth showing the result of.
    static var playedToday: Bool { bestDay == dayNumber() }

    /// Record a finished daily.
    ///
    /// Keeps the best coins for the day and rolls the streak forward exactly once per calendar
    /// day — finishing the same gate three times must not count as a three-day streak, which is
    /// the obvious way to get this wrong.
    static func noteWin(coins: Int) {
        let today = dayNumber()
        let defaults = UserDefaults.standard

        if bestDay == today {
            if coins > bestCoins { defaults.set(coins, forKey: bestCoinsKey) }
            return
        }

        let finishedYesterday = defaults.integer(forKey: lastDayKey) == today - 1
        defaults.set(finishedYesterday ? streak + 1 : 1, forKey: streakKey)
        defaults.set(today, forKey: lastDayKey)
        defaults.set(today, forKey: bestDayKey)
        defaults.set(coins, forKey: bestCoinsKey)
    }

    /// Today's date for the card, so it is obvious the gate belongs to a particular day.
    static func todayLabel(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.timeZone = TimeZone(identifier: "UTC") ?? .current
        return f.string(from: date)
    }
}
