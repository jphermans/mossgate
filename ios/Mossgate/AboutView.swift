import SwiftUI
import UIKit

/// Help / About — one scrollable screen: how to play, what everything in a level
/// is, how the light works, and who made it.
///
/// The legend uses the game's own sprites rather than SF Symbols. The whole job
/// of a help screen is recognising the things you will meet, so showing the real
/// coin, the real bramble and the real gate is the point — an icon font would
/// teach nothing.
struct AboutView: View {
    let onDone: () -> Void

    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        ZStack {
            Color("MossgateDusk").ignoresSafeArea()

            VStack(spacing: 0) {
                // The title and Done live in a real bar that owns its own layout
                // space. A floating bar always covers whatever happens to be
                // underneath it, which on a scrolling screen is a moving target.
                topBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Carry the lantern to the gate. Keep it lit.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color("MossgateMuted"))
                        // Two columns. This screen is only ever read in landscape,
                        // and a single tall column would mean scrolling through
                        // most of it on a screen this short.
                        HStack(alignment: .top, spacing: 22) {
                            VStack(alignment: .leading, spacing: 22) {
                                controls
                                light
                                about
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 22) {
                                legend
                                seedSection
                                worlds
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            sprite("idle-1", size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("HOW TO PLAY")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(Color("MossgateLantern"))
                Text("Mossgate")
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(Color("MossgateCream"))
            }
            Spacer(minLength: 0)
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color("MossgatePrimaryFg"))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color("MossgateLantern"))
                    )
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(
            Color("MossgateDusk")
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color("MossgateBorder"))
                        .frame(height: 1)
                }
        )
    }

    // MARK: - Controls

    private var controls: some View {
        section("Controls") {
            infoRow(title: "Move", detail: "The left and right pads, or the left stick or d-pad on a controller.") {
                sprite("run-1", size: 38)
            }
            divider
            infoRow(title: "Jump", detail: "JUMP, or A on a controller. Press again in mid-air for a second jump — you need it to reach the high ledges.") {
                sprite("jump-1", size: 38)
            }
            divider
            infoRow(title: "Down", detail: "Look down over an edge, or dive faster while falling.") {
                sprite("ledge", size: 38)
            }
        }
    }

    // MARK: - Legend

    private var legend: some View {
        section("What you'll meet") {
            infoRow(title: "Coins", detail: "Twelve in a level. The count you finish with is your best for it.") {
                sprite("coin-1", size: 34)
            }
            divider
            infoRow(title: "Lanterns", detail: "Pick one up to win back a light, up to three. They are the only way to get one back.") {
                lanternIcon
            }
            divider
            infoRow(title: "Waystones", detail: "Touch one and it remembers where you got to, so a fall costs you less.") {
                sprite("checkpoint", size: 34)
            }
            divider
            infoRow(title: "Brambles", detail: "One touch costs a light.") {
                sprite("spike", size: 34)
            }
            divider
            infoRow(title: "The gate", detail: "Reach it to clear the level.") {
                sprite("flag-1", size: 34)
            }
            divider
            infoRow(title: "Stone and ledges", detail: "Stone is solid everywhere. Pale ledges are one-way: they hold you up, and you can jump up through them from below.") {
                HStack(spacing: 6) {
                    sprite("block", size: 34)
                    sprite("ledge", size: 34)
                }
            }
        }
    }

    // MARK: - The run seed

    /// The seed is the one part of the game that is not a mechanic, so it sits in its own
    /// section rather than in the legend. It is written from what useSeed actually does, not from
    /// what a seed ought to do: it regrows the gates and leaves cleared/bestCoins alone, and
    /// those are keyed per gate number, so a shuffle keeps your clears pointing at the same
    /// slots while the gates under them change. Worth saying plainly — a shuffle that looks
    /// like it kept your progress is the kind of thing a player should be told, not discover.
    private var seedSection: some View {
        section("The run seed") {
            infoRow(title: "Run seed",
                    detail: "The number the gates are built from. The same seed always builds the same climb, so a seed is how you hand someone your exact set of gates.") {
                Image(systemName: "number")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color("MossgateLantern"))
            }
            divider
            infoRow(title: "Shuffling",
                    detail: "Builds a fresh climb. Your clears and best counts stay where they are — they are kept per gate number, not per seed, so a shuffled climb starts with the marks the old one left.") {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color("MossgateLantern"))
            }
            divider
            infoRow(title: "Passing one on",
                    detail: "In Setup, share your seed or type someone else's in. The gates are rebuilt from it as soon as it is set, and the number is remembered next time you open the game.") {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color("MossgateLantern"))
            }
        }
    }

    // MARK: - Light

    private var light: some View {
        section("Your light") {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color("MossgateLantern"))
                Text("\(SettingsStore.maxLives)/\(SettingsStore.maxLives)")
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color("MossgateCream"))
                Text("at the start of a run")
                    .font(.system(size: 12))
                    .foregroundStyle(Color("MossgateMuted"))
                Spacer(minLength: 0)
            }
            Text("Every bramble, and every fall into the dark, costs one light. You carry on from the last waystone you touched. Lose all three and the run is over — starting again refills the lantern.\n\nThis is the counter in the top corner while you play.")
                .font(.system(size: 12))
                .foregroundStyle(Color("MossgateMuted"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Worlds

    private var worlds: some View {
        section("A different world each time") {
            Text("Every restart reshuffles the sky and the stars, where the coins and lanterns sit, and the timing of the moving platforms. The gate is always reachable — only the way there changes.")
                .font(.system(size: 12))
                .foregroundStyle(Color("MossgateMuted"))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("This run")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color("MossgateCream"))
                Text("seed \(settings.runSeed)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color("MossgateLantern"))
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - About

    private var about: some View {
        section("About") {
            VStack(alignment: .leading, spacing: 5) {
                Text("Mossgate — Dusk Ruins")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("MossgateCream"))
                Text("A JPHsystems game.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color("MossgateMuted"))
                Text("\(Worlds.all.count) worlds · \(Levels.all.count) levels")
                    .font(.system(size: 12))
                    .foregroundStyle(Color("MossgateMuted"))
                Text("Version \(AppInfo.shortVersion) (\(AppInfo.build))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color("MossgateMuted"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            divider

            // Reachable from inside the app, which is what a reviewer looks for: a support
            // route and a privacy policy that are live, not placeholders. Same URLs the store
            // listing carries.
            linkRow("Support",
                    "Questions, bug reports, and the changelog for every release.",
                    AppInfo.supportURL, symbol: "lifepreserver")
            divider
            linkRow("Privacy Policy",
                    "What the game does and does not collect.",
                    AppInfo.privacyURL, symbol: "hand.raised")
        }
    }

    // MARK: - Building blocks

    /// An external link, styled to sit alongside the info rows.
    ///
    /// A `Link` rather than a Button calling `UIApplication.shared.open`, so it picks up the
    /// platform's own affordances — long-press preview, open-in-background, and correct
    /// handling if the URL is ever unreachable.
    private func linkRow(_ title: String, _ detail: String,
                         _ url: URL, symbol: String) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color("MossgateLantern"))
                    .frame(width: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color("MossgateCream"))
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color("MossgateMuted"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color("MossgateMuted"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    /// One of the game's own sprite images. Interpolation is off so the pixel art
    /// stays crisp instead of being smeared by the scaler.
    private func sprite(_ name: String, size: CGFloat) -> some View {
        Group {
            if let ui = UIImage(named: name) {
                Image(uiImage: ui)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }

    /// The procedurally drawn lantern, the same art the scene hands the player.
    private var lanternIcon: some View {
        Image(uiImage: GameArt.lanternImage())
            .interpolation(.none)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color("MossgateBorder"))
            .frame(height: 1)
    }

    private func infoRow<Icon: View>(title: String, detail: String,
                                     @ViewBuilder icon: () -> Icon) -> some View {
        HStack(alignment: .top, spacing: 14) {
            icon()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color("MossgateCream"))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color("MossgateMuted"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(3)
                .foregroundStyle(Color("MossgateLantern"))
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color("MossgateSurface").opacity(0.85))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color("MossgateBorder"), lineWidth: 1))
            )
        }
    }
}
