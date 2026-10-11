import SwiftUI

/// Title screen — lists worlds and their levels, with a setup button.
struct TitleView: View {
    let onStartLevel: (Int) -> Void
    let onOpenSetup: () -> Void
    let onOpenGameCenter: () -> Void

    @ObservedObject private var settings = SettingsStore.shared
    @State private var expandedWorld: Int = 0

    var body: some View {
        ZStack {
            Color("MossgateDusk").ignoresSafeArea()
            duskGradient
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    ForEach(Worlds.all, id: \.id) { world in
                        worldCard(world)
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
            Text("DUSK RUINS")
                .font(.system(size: 12, weight: .semibold))
                .tracking(4)
                .foregroundStyle(Color("MossgateLantern"))
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

    private func worldCard(_ world: World) -> some View {
        let isOpen = expandedWorld == world.id
        let levelsInWorld = Levels.all.filter { $0.world == world.id }
        let clearedCount = levelsInWorld.filter { settings.cleared[$0.id] }.count
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedWorld = (expandedWorld == world.id) ? -1 : world.id
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(world.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color("MossgateCream"))
                        Text(world.blurb)
                            .font(.system(size: 11))
                            .foregroundStyle(Color("MossgateMuted"))
                    }
                    Spacer()
                    Text("\(clearedCount)/\(levelsInWorld.count)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color("MossgateLantern"))
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Color("MossgateMuted"))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color("MossgateSurface").opacity(0.9))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color("MossgateBorder"), lineWidth: 1))
                )
            }
            if isOpen {
                VStack(spacing: 6) {
                    ForEach(levelsInWorld, id: \.id) { level in
                        Button { onStartLevel(level.id) } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(level.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color("MossgateCream"))
                                    Text(level.blurb)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color("MossgateMuted"))
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    if settings.cleared[level.id] {
                                        Text("CLEAR")
                                            .font(.system(size: 10, weight: .heavy))
                                            .tracking(2)
                                            .foregroundStyle(Color("MossgateLantern"))
                                    }
                                    Text("\(settings.bestCoins[level.id])/\(level.coins.count)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(Color("MossgateMuted"))
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color("MossgateSurface").opacity(0.6))
                            )
                        }
                    }
                }
            }
        }
    }

    private var credits: some View {
        VStack(spacing: 4) {
            Text("Made by JPHsystems")
                .font(.system(size: 11))
                .tracking(2)
                .foregroundStyle(Color("MossgateMuted"))
            Text("v\(AppInfo.shortVersion) (\(AppInfo.build))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color("MossgateMuted").opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}

/// Reads CFBundleShortVersionString / CFBundleVersion from the main bundle.
enum AppInfo {
    static var shortVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
    static var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
    }
}