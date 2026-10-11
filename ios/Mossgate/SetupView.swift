import SwiftUI

/// Setup screen — sound on/off, SFX on/off, music volume slider, SFX volume slider.
struct SetupView: View {
    let onDone: () -> Void
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var controllers = ControllerList.shared
    @State private var showResetConfirm = false

    var body: some View {
        ZStack {
            Color("MossgateDusk").ignoresSafeArea()
            duskGradient
            VStack(spacing: 20) {
                HStack {
                    Button(action: onDone) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color("MossgateCream"))
                            .padding(10)
                            .background(
                                Circle().fill(Color("MossgateSurface").opacity(0.85))
                                    .overlay(Circle().strokeBorder(Color("MossgateBorder"), lineWidth: 1))
                            )
                    }
                    Spacer()
                    Text("SETUP")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(4)
                        .foregroundStyle(Color("MossgateLantern"))
                    Spacer()
                    Color.clear.frame(width: 38, height: 38)
                }
                .padding(.top, 16)
                .padding(.horizontal, 18)

                ScrollView {
                    VStack(spacing: 14) {
                        toggleRow(
                            title: "Sound",
                            blurb: "Ambient dusk and music",
                            isOn: $settings.soundOn
                        )
                        volumeRow(
                            title: "Music volume",
                            value: $settings.soundVolume,
                            enabled: settings.soundOn
                        )
                        toggleRow(
                            title: "SFX",
                            blurb: "Jumps, coins, deaths, gates",
                            isOn: $settings.sfxOn
                        )
                        volumeRow(
                            title: "SFX volume",
                            value: $settings.sfxVolume,
                            enabled: settings.sfxOn
                        )
                        Divider()
                            .background(Color("MossgateBorder"))
                            .padding(.vertical, 4)
                        runSection
                        Divider()
                            .background(Color("MossgateBorder"))
                            .padding(.vertical, 4)
                        controllerSection
                        Divider()
                            .background(Color("MossgateBorder"))
                            .padding(.vertical, 4)
                        Button(role: .destructive) {
                            showResetConfirm = true
                        } label: {
                            Text("Reset all progress")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.red.opacity(0.5), lineWidth: 1)
                                )
                        }
                        Text("Mossgate v\(AppInfo.shortVersion) (\(AppInfo.build))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color("MossgateMuted"))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                    }
                    .padding(.horizontal, 22)
                }
                // -SetupLarge 1 also scrolls to the bottom, which is the only way
                // to reach the controller section in a headless screenshot (no
                // gesture input). Default anchor is unchanged otherwise.
                .defaultScrollAnchor(
                    ProcessInfo.processInfo.arguments.contains("-SetupLarge") ? .bottom : .top
                )
            }
        }
        .alert("Reset all progress?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                settings.resetProgress()
                AudioEngine.shared.tap()
            }
        } message: {
            Text("Cleared levels and best coin counts will be cleared. This can't be undone.")
        }
    }

    /// The run seed and a way to reroll it. Every restart already picks a new
    /// one; this is for when you want a different world now.
    private var runSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New worlds")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color("MossgateCream"))
                Text("Every restart reshuffles the sky, the pickups and the platform timing.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color("MossgateMuted"))
            }
            HStack {
                Text("Seed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color("MossgateCream"))
                Text("\(settings.runSeed)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color("MossgateMuted"))
                Spacer()
                Button {
                    settings.newRun()
                    AudioEngine.shared.tap()
                } label: {
                    Text("Shuffle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color("MossgatePrimaryFg"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10).fill(Color("MossgateLantern"))
                        )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("MossgateSurface").opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color("MossgateBorder"), lineWidth: 1))
        )
    }

    /// External controller support: the toggle, what's connected, and the button
    /// mapping so a pad is usable without a manual.
    private var controllerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            toggleRow(
                title: "Game controller",
                blurb: controllers.infos.isEmpty
                    ? "No controller connected"
                    : controllers.names.joined(separator: ", "),
                // Must be the real Published binding. A hand-rolled
                // Binding(get:set:) here had SwiftUI push its stale internal
                // value back through `set` on the first render, which flipped
                // this to false on launch and silently disabled controller input.
                isOn: $settings.controllerOn
            )
            if settings.controllerOn {
                if controllers.infos.isEmpty {
                    Text("Pair one in iOS Settings › Bluetooth. Mossgate picks it up on its own — nothing to configure here.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color("MossgateMuted"))
                        .padding(.horizontal, 4)
                } else {
                    // What's attached and what kind it is. The type comes from the
                    // concrete profile class, so an Xbox pad reads "Xbox" rather
                    // than the generic "extended gamepad".
                    VStack(spacing: 6) {
                        ForEach(controllers.infos) { info in
                            mappingRow("Type", info.summary)
                            if !info.category.isEmpty, info.category != info.name {
                                mappingRow("Category", info.category)
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color("MossgateSurface").opacity(0.6))
                    )
                }
                VStack(spacing: 6) {
                    mappingRow("Jump", "A  ·  d-pad up")
                    mappingRow("Down", "B  ·  d-pad down  ·  stick down")
                    mappingRow("Move", "left stick  ·  d-pad")
                    mappingRow("Pause", "Menu  ·  Options")
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color("MossgateSurface").opacity(0.6))
                )
            }
        }
    }

    private func mappingRow(_ label: String, _ keys: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color("MossgateCream"))
                .frame(width: 64, alignment: .leading)
            Text(keys)
                .font(.system(size: 12))
                .foregroundStyle(Color("MossgateMuted"))
            Spacer()
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
    private func toggleRow(title: String, blurb: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color("MossgateCream"))
                Text(blurb)
                    .font(.system(size: 12))
                    .foregroundStyle(Color("MossgateMuted"))
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color("MossgateLantern"))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("MossgateSurface").opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color("MossgateBorder"), lineWidth: 1))
        )
    }

    private func volumeRow(title: String, value: Binding<Double>, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color("MossgateCream"))
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color("MossgateMuted"))
            }
            Slider(value: value, in: 0...1)
                .tint(Color("MossgateLantern"))
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("MossgateSurface").opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color("MossgateBorder"), lineWidth: 1))
        )
    }
}