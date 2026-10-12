import SwiftUI

/// Title screen — lists worlds and their levels, with a setup button.
struct TitleView: View {
    let onStartLevel: (Int) -> Void
    let onOpenSetup: () -> Void
    let onOpenHelp: () -> Void
    let onOpenGameCenter: () -> Void
    /// Tapped a world that is not playable — either the paywall or the progression.
    let onLockedTap: (World) -> Void
    let onBuyFullGame: () -> Void
    let onRestore: () -> Void

    @ObservedObject private var settings = SettingsStore.shared
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
                    // Above the world list, not below it: in landscape the six world
                    // cards fill the screen, so a purchase card underneath them is
                    // something you have to go looking for.
                    if !settings.hasFullGame {
                        fullGameCard
                    }
                    ForEach(Worlds.all, id: \.id) { world in
                        worldCard(world)
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
                            Label("Game Center", systemImage: "trophy")
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
                                settings.notice = "Finish the gate before it to open this one."
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
                                        Text("\(settings.bestCoins[level.id])/\(level.coins.count)")
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