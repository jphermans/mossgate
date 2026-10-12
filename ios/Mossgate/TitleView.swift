import SwiftUI

/// Title screen — lists worlds and their levels, with a setup button.
struct TitleView: View {
    let onStartLevel: (Int) -> Void
    /// Start today's Daily Gate.
    ///
    /// Separate from `onStartLevel` because it deliberately skips the unlock check: the daily is
    /// free for everyone, but the gate it lives on is still behind the progression chain, so
    /// going through the ordinary path refuses it and the tap does nothing.
    let onStartDaily: (Int) -> Void
    /// Start a Coin Rush. Timed, so like the other two it skips the unlock check — the
    /// world is rebuilt from a fresh seed and there is no gate of this run to unlock.
    let onStartCoinRush: (Int) -> Void
    /// Start an Endless Run. Like the daily it deliberately skips the unlock check: it
    /// rebuilds the world from a fresh seed, so there is no gate of this run to unlock.
    let onStartEndless: (Int) -> Void
    let onOpenSetup: () -> Void
    let onOpenHelp: () -> Void
    let onOpenGameCenter: () -> Void
    /// Tapped a world that is not playable — either the paywall or the progression.
    let onLockedTap: (World) -> Void
    let onBuyFullGame: () -> Void
    let onRestore: () -> Void

    @ObservedObject private var settings = SettingsStore.shared
    /// Read here, not just in the manager: this is what lets the Game Center button say whether
    /// the player is signed in instead of always claiming to be Game Center and doing nothing.
    @ObservedObject private var gameCenter = GameCenterManager.shared
    @ObservedObject private var store = Store.shared
    /// Which world is expanded. Test hook `-CollapseWorlds 1` starts with none of
    /// them open, so every world card and the purchase card fit on one screen for a
    /// screenshot — there is no way to script a scroll.
    @State private var expandedWorld: Int =
        ProcessInfo.processInfo.arguments.contains("-CollapseWorlds") ? -1 : 0

    var body: some View {
        ZStack {
            // The backdrop is attached as a BACKGROUND of the base colour, not as a ZStack
            // sibling.
            //
            // As a sibling it becomes part of the stack's layout: a scaledToFill image asking
            // for the whole screen makes the stack's ideal size unbounded, and the ScrollView
            // next to it then has nothing to scroll. That is the report — "i can not scroll to
            // the setup page anymore on the start page" — and the Setup entry lives at the
            // bottom of that scroll.
            //
            // The painting, as an OVERLAY on the base colour.
            //
            // It used to be a .background() of that Color — which sits BEHIND the view, and the
            // Color is opaque, so the image could never show at any blur or opacity. Same bug as
            // the splash, from the same misunderstanding of what .background() does.
            //
            // It stays a bounded Rectangle rather than a bare scaledToFill image, because that
            // is what keeps the ScrollView below scrollable: an image with no frame is laid out
            // at its own size, the stack's ideal size goes unbounded, and the ScrollView beside
            // it then has nothing to scroll. That was the report — "i can not scroll to the
            // setup page anymore on the start page".
            //
            // A Rectangle is flexible and takes the available space, so it satisfies both: the
            // image is drawn on top of the fill, and the stack is never asked for an infinite
            // height. It also covers the safe areas without the scale-and-clip dance the old
            // sibling version needed to hide the clipped edge of its blur.
            Rectangle()
                .fill(Color("MossgateDusk"))
                .overlay(
                    Image("TitleBackdrop")
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 9)
                        .saturation(0.9)
                        .opacity(0.6)
                )
                .clipped()
                .ignoresSafeArea()
            duskGradient
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    // Above everything, including the purchase card.
                    //
                    // It first sat below the purchase card, which on a 16 Pro put it half over
                    // the fold — so a free player, who is exactly who a daily is for, had to
                    // scroll to discover the feature existed. Reported as "where are the mini
                    // games?".
                    dailyCard
                    endlessCard
                    coinRushCard
                    ForEach(Worlds.all, id: \.id) { world in
                        worldCard(world)
                        // Directly after the free world, before the ones it unlocks. It used to
                        // sit above the whole list, which made it a banner over the game rather
                        // than an offer for what comes next; here it reads as the next step,
                        // which is what it is.
                        if world.id == 0, !settings.hasFullGame {
                            fullGameCard
                        }
                    }
                    Button(action: onOpenHelp) {
                        Label("How to play", systemImage: "questionmark.circle")
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color("MossgateLantern").opacity(0.16))
                                    .overlay(RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(Color("MossgateLantern").opacity(0.55),
                                                      lineWidth: 1))
                            )
                            .foregroundStyle(Color("MossgateCream"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    HStack(spacing: 12) {
                        Button(action: onOpenSetup) {
                            Label("Setup", systemImage: "slider.horizontal.3")
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color("MossgateSurface").opacity(0.85))
                                        .overlay(RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(Color("MossgateBorder"), lineWidth: 1))
                                )
                                .foregroundStyle(Color("MossgateCream"))
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Button(action: onOpenGameCenter) {
                            // Says what tapping it will do. The manager publishes the sign-in
                            // state and nothing read it, so a signed-out player saw a button
                            // labelled "Game Center", tapped it, and got no feedback at all —
                            // the tap re-attempts sign-in and returns silently either way.
                            Label(gameCenter.isAuthenticated ? "Game Center" : "Sign in",
                                  systemImage: "trophy")
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color("MossgateSurface").opacity(0.85))
                                        .overlay(RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(Color("MossgateBorder"), lineWidth: 1))
                                )
                                .foregroundStyle(Color("MossgateCream"))
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    credits
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 32)
            }
        }
    }

    private var duskGradient: some View {
        LinearGradient(colors: [
            Color(red: 0.027, green: 0.078, blue: 0.086),
            Color(red: 0.071, green: 0.220, blue: 0.227),
            Color(red: 0.110, green: 0.275, blue: 0.212),
            Color(red: 0.051, green: 0.133, blue: 0.110),
        ], startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
        .opacity(0.6)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("DUSK RUINS")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(4)
                    .foregroundStyle(Color("MossgateLantern"))
                Spacer()
                // Keep the version where it can be read without scrolling —
                // useful when checking which build is installed on a device.
                Text("v\(AppInfo.shortVersion) (\(AppInfo.build))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color("MossgateMuted"))
            }
            Text("Mossgate")
                .font(.system(size: 44, weight: .semibold, design: .serif))
                .foregroundStyle(Color("MossgateCream"))
            Text("A JPHsystems game")
                .font(.system(size: 12))
                .tracking(2)
                .foregroundStyle(Color("MossgateMuted"))
            Text("Keep the lantern lit. Choose a gate.")
                .font(.system(size: 14))
                .foregroundStyle(Color("MossgateMuted"))
                .padding(.top, 6)
        }
    }

    /// World 0 is free; the other five are the single purchase. Locked cards say
    /// which kind of locked they are, because "buy this" and "finish the last
    /// world" are very different things to be told.
    private func worldCard(_ world: World) -> some View {
        let unlocked = settings.worldUnlocked(world.id)
        let isOpen = unlocked && expandedWorld == world.id
        let gates = settings.gates.filter { $0.world == world.id }
        let clearedCount = gates.filter { settings.cleared[$0.id] }.count
        // A finished world has to LOOK finished at a glance, not require counting
        // six ticked rows: it is both the thing you earned and the gate to the next
        // world, which is exactly what the player is looking for on this screen.
        let complete = unlocked && settings.worldComplete(world.id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                guard unlocked else { onLockedTap(world); return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedWorld = (expandedWorld == world.id) ? -1 : world.id
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(world.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(unlocked ? Color("MossgateCream") : Color("MossgateMuted"))
                        Text(unlocked ? (complete ? "Every gate cleared." : world.blurb)
                                      : (settings.worldLockReason(world.id) ?? ""))
                            .font(.system(size: 11))
                            .foregroundStyle(complete ? Color("MossgateLantern") : Color("MossgateMuted"))
                    }
                    Spacer()
                    if unlocked {
                        if complete {
                            Label("COMPLETE", systemImage: "checkmark.seal.fill")
                                .font(.system(size: 11, weight: .heavy))
                                .tracking(2)
                                .foregroundStyle(Color("MossgateLantern"))
                        } else {
                            Text("\(clearedCount)/\(gates.count)")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color("MossgateLantern"))
                        }
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .foregroundStyle(Color("MossgateMuted"))
                    } else {
                        Label(settings.hasFullGame ? "Locked" : "Full game",
                              systemImage: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color("MossgateLantern"))
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(complete ? Color("MossgateLantern").opacity(0.13)
                                       : Color("MossgateSurface").opacity(unlocked ? 0.9 : 0.5))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(complete ? Color("MossgateLantern").opacity(0.65)
                                                   : Color("MossgateBorder"),
                                          lineWidth: complete ? 1.5 : 1))
                )
            }
            if isOpen {
                VStack(spacing: 6) {
                    ForEach(gates, id: \.id) { level in
                        let open = settings.gateUnlocked(level.id)
                        Button {
                            guard open else {
                                // This is the guard that actually fires — the row intercepts
                                // before onStartLevel, so RootView's check is only a backstop.
                                // Name the gate in the way, in the same voice the locked-world
                                // tap uses: "Finish the gate before it" was true and did not say
                                // which gate, on a list where several are locked.
                                let all = Levels.all
                                let prev = (level.id > 0 && level.id - 1 < all.count)
                                    ? all[level.id - 1].name : "the gate before it"
                                settings.notice = "Finish \(prev) to open this one."
                                return
                            }
                            onStartLevel(level.id)
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(level.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(open ? Color("MossgateCream")
                                                              : Color("MossgateMuted"))
                                    Text(open ? level.blurb : "Finish the gate before it.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color("MossgateMuted"))
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    if !open {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color("MossgateMuted"))
                                    } else {
                                        if settings.cleared[level.id] {
                                            Text("CLEAR")
                                                .font(.system(size: 16, weight: .heavy))
                                                .tracking(2)
                                                .foregroundStyle(Color("MossgateLantern"))
                                        }
                                        HStack(spacing: 4) {
                                            // Medal first, count second: the star is the
                                            // summary and the number is the detail.
                                            Image(systemName: settings.medal(for: level.id, of: level.coins.count).symbol ?? "")
                                                .font(.system(size: 9))
                                                .foregroundStyle(Color(settings.medal(for: level.id, of: level.coins.count).tintName))
                                            Text("\(settings.bestCoins[level.id])/\(level.coins.count)")
                                        }
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(Color("MossgateMuted"))
                                    }
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color("MossgateSurface").opacity(open ? 0.6 : 0.35))
                            )
                        }
                    }
                }
            }
        }
    }

    /// Coin Rush.
    ///
    /// The third mini-game. The clock is the whole idea, so the card leads with the time rather
    /// than the world.
    private var coinRushCard: some View {
        let best = settings.coinRushBest
        return Button {
            settings.startCoinRushRun()
            onStartCoinRush(0)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("COIN RUSH")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(3)
                        .foregroundStyle(Color("MossgateLantern"))
                    Spacer(minLength: 0)
                    if best > 0 {
                        Text("best \(best)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color("MossgateMuted"))
                    }
                }
                Text("\(SettingsStore.coinRushSeconds) seconds. Take everything you can reach.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("MossgateCream"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(best > 0 ? "Your best is \(best) coins. Every run is a new gate."
                              : "One gate, one clock, no second chances.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color("MossgateMuted"))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color("MossgateSurface").opacity(0.85))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color("MossgateBorder"), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    /// Endless Run.
    ///
    /// The second of the three mini-games. Unlike the daily there is no seed to share — a fresh
    /// world each time is the point — so this card is about the personal best, which is the only
    /// thing that carries between runs.
    private var endlessCard: some View {
        let best = settings.endlessBest
        return Button {
            settings.startEndlessRun()
            onStartEndless(0)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("ENDLESS RUN")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(3)
                        .foregroundStyle(Color("MossgateLantern"))
                    Spacer(minLength: 0)
                    if best > 0 {
                        Text("best \(best)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color("MossgateMuted"))
                    }
                }
                Text("One chain, gate after gate, until the light runs out.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("MossgateCream"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(best > 0 ? "Your longest is \(best) gates. A new world every time."
                              : "A new world every time. Gates behind you are the score.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color("MossgateMuted"))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color("MossgateSurface").opacity(0.85))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color("MossgateBorder"), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    /// Today's Daily Gate.
    ///
    /// Free for everyone, and the only thing in the game that is different tomorrow. It sits
    /// above the world list rather than inside it: the 36 gates are the game, and this is the
    /// reason to open it again.
    private var dailyCard: some View {
        let played = DailyGate.playedToday
        let streak = DailyGate.streak
        let streakWord = streak == 1 ? "day" : "days"
        return Button {
            settings.startDailyRun()
            onStartDaily(DailyGate.gateIndex)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("DAILY GATE")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(3)
                        .foregroundStyle(Color("MossgateLantern"))
                    Spacer(minLength: 0)
                    Text(DailyGate.todayLabel())
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color("MossgateMuted"))
                }
                Text(played ? "Finished — \(DailyGate.bestCoins) coins. A new one tomorrow."
                            : "A fresh gate today, the same for everyone.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("MossgateCream"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(streak > 0
                     ? "\(streak) \(streakWord) in a row · coins are the score"
                     : "Coins are the score. Every player gets the same gate.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color("MossgateMuted"))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color("MossgateLantern").opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color("MossgateLantern").opacity(0.38), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    /// The single purchase. Only shown while it is not owned, so the free game never
    /// has a price tag sitting on it unprompted.
    private var fullGameCard: some View {
        let extra = Levels.totalGates - Worlds.gatesPerWorld
        return VStack(alignment: .leading, spacing: 10) {
            Text("Five more worlds")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color("MossgateCream"))
            Text("Mossgate Dusk is yours to keep. The Full Game unlocks Ember Caves, Frost Spires, Void Garden, Sunken Choir and Ashen Crown — \(extra) more gates, and every one of them rebuilt each time you play.")
                .font(.system(size: 12))
                .foregroundStyle(Color("MossgateMuted"))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(action: onBuyFullGame) {
                    Text(store.busy ? "Contacting the App Store…" : (store.priceText ?? "Unlock Full Game"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color("MossgatePrimaryFg"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color("MossgateLantern"))
                        )
                }
                .disabled(store.busy)
                Button(action: onRestore) {
                    Text("Restore")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color("MossgateCream"))
                        .frame(minWidth: 104, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color("MossgateSurface").opacity(0.85))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color("MossgateBorder"), lineWidth: 1))
                        )
                }
                .disabled(store.busy)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color("MossgateLantern").opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color("MossgateLantern").opacity(0.45), lineWidth: 1))
        )
    }

    private var credits: some View {
        VStack(spacing: 4) {
            Text("Made by JPHsystems")
                .font(.system(size: 11))
                .tracking(2)
                .foregroundStyle(Color("MossgateMuted"))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}

// MARK: - Filming harness

/// The `-DemoPlay` filming harness's on/off switch.
///
/// It exists so a test flag can never hold the game hostage. Before this, `-DemoPlay` held the
/// right pad down and retried every death with no way out: the game played itself forever, and
/// from the outside that is indistinguishable from a bug — a character that runs by itself
/// into the deep, restarts, and burns every life in seconds. Now the demo gives up on a
/// deadline, and any real press on a control cancels it instantly.
enum DemoMode {
    static var active = false
    /// The touch state the demo is driving, so cancelling can let go of it.
    static weak var driver: TouchState?
    /// Well past anything a promo clip needs, and short enough that a stray launch cannot
    /// leave the game playing itself for long.
    static let deadline: TimeInterval = 40

    /// Let go and stop. Safe to call when the demo was never on.
    static func stop() {
        guard active else { return }
        active = false
        driver?.right = false
        driver?.jump = false
    }
}

/// Reads CFBundleShortVersionString / CFBundleVersion from the main bundle.
enum AppInfo {
    /// Public pages, and the only place these URLs are written down.
    ///
    /// The first two are exactly what App Store Connect lists as the Support URL and the
    /// Privacy Policy URL. Kept as constants so the listing, this screen, and anything that
    /// quotes them later cannot drift apart — Apple re-checks these URLs after submission,
    /// so a 404 is a review risk rather than a copy nit.
    static let supportURL = URL(string: "https://jphermans.github.io/mossgate-support/")!
    static let privacyURL = URL(string: "https://jphermans.github.io/mossgate-support/#privacy")!
    static let changelogURL = URL(string: "https://jphermans.github.io/mossgate-support/#changelog")!

    static var shortVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
    static var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
    }
}