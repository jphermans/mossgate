import SwiftUI

/// A confirmation in the game's own colours.
///
/// The system alert is the wrong voice for this: it arrives in iOS grey and blue,
/// over a dusk-teal screen, for the one action in the game that cannot be undone.
/// This is the same card language as the pause panel — the surface fill, the single
/// hairline border, the serif cream heading, the lantern-amber action — so the
/// choice reads as part of the world rather than as something the OS put on top.
///
/// Tapping the scrim cancels. On the one irreversible action, the cheaper gesture
/// should be the safe one.
struct GameConfirm: View {
    let title: String
    let message: String
    let confirmLabel: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundStyle(Color("MossgateCream"))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Color("MossgateMuted"))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    Button(action: onConfirm) {
                        Text(confirmLabel)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(Color("MossgatePrimaryFg"))
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color("MossgateLantern"))
                            )
                    }
                    Button(action: onCancel) {
                        Text("Keep it")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(Color("MossgateCream"))
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color("MossgateBorder"), lineWidth: 1)
                            )
                    }
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 20)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color("MossgateSurface").opacity(0.97))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color("MossgateBorder"), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
    }
}
