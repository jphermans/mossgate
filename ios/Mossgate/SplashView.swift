import SwiftUI

struct SplashView: View {
    let onContinue: () -> Void

    @State private var pulse = false
    @State private var lift = false

    var body: some View {
        ZStack {
            // Dusk gradient — same colours as the game canvas
            LinearGradient(
                colors: [
                    Color(red: 0.027, green: 0.078, blue: 0.086), // #071416
                    Color(red: 0.071, green: 0.220, blue: 0.227), // #12383a
                    Color(red: 0.110, green: 0.275, blue: 0.212), // #1c4636
                    Color(red: 0.051, green: 0.133, blue: 0.110), // #0d221c
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Soft amber radial glow behind the lantern
            RadialGradient(
                colors: [
                    Color(red: 0.94, green: 0.63, blue: 0.25).opacity(0.35),
                    Color.clear
                ],
                center: .center,
                startRadius: 8,
                endRadius: 260
            )
            .ignoresSafeArea()
            .opacity(pulse ? 1 : 0.7)
            .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: pulse)

            VStack(spacing: 18) {
                LanternMark(size: 132)

                Text("DUSK RUINS")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .tracking(4)
                    .foregroundStyle(Color(red: 0.94, green: 0.63, blue: 0.25))
                    .opacity(lift ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.05), value: lift)

                Text("Mossgate")
                    .font(.custom("Georgia", size: 64).weight(.semibold))
                    .foregroundStyle(Color(red: 0.957, green: 0.918, blue: 0.831))
                    .opacity(lift ? 1 : 0)
                    .offset(y: lift ? 0 : 8)
                    .animation(.easeOut(duration: 0.55).delay(0.18), value: lift)

                Text("a JPHsystems game")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .tracking(2)
                    .foregroundStyle(Color(red: 0.608, green: 0.710, blue: 0.659))
                    .opacity(lift ? 1 : 0)
                    .offset(y: lift ? 0 : 8)
                    .animation(.easeOut(duration: 0.55).delay(0.32), value: lift)
            }

            VStack {
                Spacer()
                Button(action: onContinue) {
                    Text("Tap to begin")
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .tracking(2)
                        .foregroundStyle(Color(red: 0.957, green: 0.918, blue: 0.831))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().fill(
                                Color(red: 0.078, green: 0.188, blue: 0.173).opacity(0.78)
                            )
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                Color(red: 0.94, green: 0.63, blue: 0.25).opacity(0.6),
                                lineWidth: 1
                            )
                        )
                }
                .opacity(lift ? 1 : 0)
                .animation(.easeOut(duration: 0.55).delay(0.55), value: lift)
                .padding(.bottom, 56)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onContinue)
        .onAppear {
            pulse = true
            lift = true
        }
    }
}

/// Procedural lantern mark — the same dusk-amber-candle motif as the
/// game's favicon, just bigger and rendered with Core Graphics-friendly SwiftUI.
struct LanternMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // Outer amber ring (glow)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.94, green: 0.63, blue: 0.25).opacity(0.55),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: size * 0.18,
                        endRadius: size * 0.55
                    )
                )
                .frame(width: size, height: size)

            // Darker amber inner core
            Circle()
                .fill(Color(red: 0.768, green: 0.416, blue: 0.196)) // #c46a32
                .frame(width: size * 0.7, height: size * 0.7)

            // Bright center
            Circle()
                .fill(Color(red: 0.941, green: 0.627, blue: 0.251)) // #f0a040
                .frame(width: size * 0.46, height: size * 0.46)

            // Wick (cream cap on top)
            RoundedRectangle(cornerRadius: size * 0.04)
                .fill(Color(red: 0.957, green: 0.918, blue: 0.831)) // #f4ead4
                .frame(width: size * 0.09, height: size * 0.18)
                .offset(y: -size * 0.42)
        }
        .frame(width: size, height: size)
    }
}