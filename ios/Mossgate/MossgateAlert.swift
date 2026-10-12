import SwiftUI

/// An alert drawn in the game's own language.
///
/// The system alert is a grey box that belongs to iOS, not to Mossgate: it lands in the middle
/// of a dusk-lantern scene in the wrong palette, the wrong corner radius and the wrong button
/// shape. Every other surface in this app is built from `MossgateSurface`, a `MossgateBorder`
/// hairline and lantern-amber accents, so this is too — it uses the same palette names, the same
/// 14-point card radius and the same button treatment as the title screen's own buttons, which
/// means it will follow any palette change rather than drifting from it.
///
/// Deliberately one button. Every message this app raises is an acknowledgement, and a
/// two-button alert drawn by hand is a place for a mistake to hide.
// A button that dims and eases in slightly while held.
//
// Local rather than reusing the app's `PressableButtonStyle`: that one takes press/release
// callbacks because it drives the game's control pads, and this panel has no use for them.
// Reaching for it would have meant widening its access for no gain.
// (Plain comments, not ///, so the doc block above stays attached to MossgateAlert.)
private struct PressFade: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MossgateAlert: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dimming, not a wall: the scene stays visible behind it, which is the whole point
            // of styling this rather than using the system sheet.
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                // The app's eyebrow — the same small tracked amber caps as "DUSK RUINS" on the
                // title screen, doing the job the system alert used for its title.
                Text("MOSSGATE")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(Color("MossgateLantern"))

                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Color("MossgateCream"))
                    // Messages here are full sentences and can wrap; without this the panel
                    // clips them rather than growing.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onDismiss) {
                    Text("OK")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color("MossgatePrimaryFg"))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(Color("MossgateLantern")))
                }
                .buttonStyle(PressFade())
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color("MossgateSurface"))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color("MossgateBorder"), lineWidth: 1))
            )
            .padding(40)
        }
    }
}
