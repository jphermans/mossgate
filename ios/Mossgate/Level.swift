import Foundation

/// Player physics constants — kept identical to the original canvas engine so the
/// game feels the same after the SpriteKit port.
enum Phys {
    static let playerW: CGFloat = 18
    static let playerH: CGFloat = 32
    static let run: CGFloat = 255
    static let accelG: CGFloat = 2800
    static let accelA: CGFloat = 1650
    static let friction: CGFloat = 2400
    static let jumpV: CGFloat = 580
    static let dJumpV: CGFloat = 500
    static let gRise: CGFloat = 1400
    static let gFall: CGFloat = 2900
    static let gApex: CGFloat = 760
    static let apex: CGFloat = 100
    static let maxFall: CGFloat = 860
    static let coyote: CGFloat = 0.11
    static let buffer: CGFloat = 0.13
}

enum GameState {
    case title, play, pause, dead, win
    case levelSelect, setup
}

struct Coin { let x: CGFloat; let y: CGFloat }
struct Lantern { let x: CGFloat; let y: CGFloat }   // pickup: a small lantern you can take to extend your light
struct Spike { let x: CGFloat; let y: CGFloat; let w: CGFloat; let h: CGFloat }
struct Checkpoint { let x: CGFloat; let y: CGFloat }
struct Solid {
    let x: CGFloat; let y: CGFloat; let w: CGFloat; let h: CGFloat
    let oneway: Bool
}
struct MoverDef {
    let x: CGFloat; let y: CGFloat; let w: CGFloat; let h: CGFloat
    let axis: String  // "x" or "y"
    let distance: CGFloat
    let period: CGFloat
    let phase: CGFloat
}

struct Level {
    let id: Int
    let world: Int
    let name: String
    let blurb: String
    let width: CGFloat
    let height: CGFloat
    let killY: CGFloat
    let spawn: CGPoint
    let solids: [Solid]
    let movers: [MoverDef]
    let coins: [Coin]
    let lanterns: [Lantern]   // bonus pickups: small lanterns that refill your light
    let spikes: [Spike]
    let checkpoints: [Checkpoint]
    let flag: CGPoint
}