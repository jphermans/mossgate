import UIKit

/// Art shared between the SpriteKit scene and the SwiftUI screens.
///
/// The sprites on disk (`idle-1`, `coin-1`, `spike`, …) are reachable by name
/// from both, so they need no helper. The lantern is different: it is drawn at
/// runtime, and the help screen has to show the *same* lantern the player picks
/// up — teaching a look-alike would be worse than teaching none. So the drawing
/// lives here and both callers use it.
enum GameArt {
    /// The lantern pickup: a lit wick in a dark glass body, under a warm halo.
    static func lanternImage() -> UIImage {
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            // Outer glow halo
            let halo   = UIColor(red: 1.0, green: 0.78, blue: 0.40, alpha: 0.0).cgColor
            let haloIn = UIColor(red: 1.0, green: 0.78, blue: 0.40, alpha: 0.45).cgColor
            let haloColors = [haloIn, halo] as CFArray
            let haloStops: [CGFloat] = [0, 1]
            let haloGrad = CGGradient(colorsSpace: space, colors: haloColors, locations: haloStops)!
            cg.drawRadialGradient(haloGrad,
                                  startCenter: CGPoint(x: size.width/2, y: size.height/2 + 4),
                                  startRadius: 0,
                                  endCenter:   CGPoint(x: size.width/2, y: size.height/2 + 4),
                                  endRadius:   size.width/2,
                                  options: [])

            // Top loop / handle
            UIColor(red: 0.35, green: 0.22, blue: 0.10, alpha: 1).setStroke()
            cg.setLineWidth(2)
            cg.addArc(center: CGPoint(x: size.width/2, y: size.height/2 - 8),
                      radius: 5, startAngle: .pi, endAngle: 0, clockwise: true)
            cg.strokePath()

            // Body (dark glass with warm glow inside)
            let body = CGRect(x: size.width/2 - 10, y: size.height/2 - 8, width: 20, height: 18)
            UIColor(red: 0.15, green: 0.10, blue: 0.06, alpha: 1).setFill()
            UIBezierPath(roundedRect: body, cornerRadius: 3).fill()

            // Inner glow
            let innerColors = [
                UIColor(red: 1.0, green: 0.92, blue: 0.70, alpha: 1).cgColor,
                UIColor(red: 1.0, green: 0.70, blue: 0.30, alpha: 0.8).cgColor,
            ] as CFArray
            let innerStops: [CGFloat] = [0, 1]
            let innerGrad = CGGradient(colorsSpace: space, colors: innerColors, locations: innerStops)!
            cg.saveGState()
            UIBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), cornerRadius: 2).addClip()
            cg.drawLinearGradient(innerGrad,
                                  start: CGPoint(x: body.midX, y: body.minY),
                                  end:   CGPoint(x: body.midX, y: body.maxY),
                                  options: [])
            cg.restoreGState()

            // Base
            UIColor(red: 0.25, green: 0.16, blue: 0.08, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: size.width/2 - 12, y: size.height/2 + 10, width: 24, height: 4),
                         cornerRadius: 1).fill()
        }
    }
}
