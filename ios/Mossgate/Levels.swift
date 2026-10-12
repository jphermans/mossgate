import Foundation
import CoreGraphics

/// All levels. Currently 4 worlds, 15 levels (~3-4 hours of play).
/// Layout matches the original game canvas pixels (1 unit = 1 pt).
enum Levels {
    /// The hand-authored gates. They open their world: they teach the idea, and
    /// they are identical every run so there is something to learn. Everything
    /// after them is generated — see `Levels.build(seed:)`.
    static let authored: [Level] = [
        // ──────────── WORLD 1: MOSSGATE DUSK ────────────
        Level(
            id: 0, world: 0,
            name: "Wick Road",
            blurb: "Run, jump, and ride the stone across the gap.",
            width: 3120, height: 760, killY: 740,
            spawn: CGPoint(x: 88, y: 512),
            solids: [
                Solid(x: 0, y: 512, w: 704, h: 240, oneway: false),
                Solid(x: 960, y: 512, w: 560, h: 240, oneway: false),
                Solid(x: 1600, y: 448, w: 190, h: 26, oneway: true),
                Solid(x: 1880, y: 384, w: 190, h: 26, oneway: true),
                Solid(x: 2160, y: 512, w: 960, h: 240, oneway: false),
            ],
            movers: [
                MoverDef(x: 747, y: 512, w: 170, h: 22, axis: "x", distance: 43, period: 3.3, phase: 0),
            ],
            coins: [
                Coin(x: 180, y: 460), Coin(x: 300, y: 460), Coin(x: 430, y: 440),
                Coin(x: 560, y: 460), Coin(x: 820, y: 420), Coin(x: 910, y: 400),
                Coin(x: 1360, y: 450), Coin(x: 1688, y: 400), Coin(x: 1968, y: 332),
                Coin(x: 2400, y: 456), Coin(x: 2620, y: 440), Coin(x: 2840, y: 456),
            ],
            lanterns: [Lantern(x: 352, y: 427), Lantern(x: 1240, y: 427), Lantern(x: 1975, y: 299)],

            spikes: [
                Spike(x: 1180, y: 478, w: 40, h: 34),
                Spike(x: 1340, y: 478, w: 40, h: 34),
            ],
            checkpoints: [Checkpoint(x: 1040, y: 512)],
            flag: CGPoint(x: 2980, y: 512)
        ),
        Level(
            id: 1, world: 0,
            name: "Ash Span",
            blurb: "The second jump is what clears the broken stair.",
            width: 2680, height: 1020, killY: 1000,
            spawn: CGPoint(x: 80, y: 704),
            solids: [
                Solid(x: 0, y: 704, w: 420, h: 280, oneway: false),
                Solid(x: 500, y: 608, w: 176, h: 26, oneway: true),
                Solid(x: 760, y: 480, w: 176, h: 26, oneway: true),
                Solid(x: 980, y: 820, w: 640, h: 180, oneway: false),
                Solid(x: 1560, y: 480, w: 240, h: 26, oneway: true),
                Solid(x: 1880, y: 300, w: 680, h: 28, oneway: true),
            ],
            movers: [
                MoverDef(x: 980, y: 480, w: 170, h: 22, axis: "x", distance: 120, period: 3.4, phase: 0),
                MoverDef(x: 1320, y: 480, w: 170, h: 22, axis: "x", distance: 50, period: 3.4, phase: .pi),
                MoverDef(x: 1700, y: 390, w: 220, h: 22, axis: "y", distance: 90, period: 4.2, phase: 0),
            ],
            coins: [
                Coin(x: 160, y: 648), Coin(x: 280, y: 640),
                Coin(x: 580, y: 556), Coin(x: 840, y: 420),
                Coin(x: 1120, y: 400), Coin(x: 1320, y: 390),
                Coin(x: 1660, y: 420), Coin(x: 1860, y: 250),
                Coin(x: 2140, y: 246), Coin(x: 2360, y: 246),
            ],
            lanterns: [Lantern(x: 210, y: 619), Lantern(x: 1300, y: 735), Lantern(x: 1680, y: 395)],

            spikes: [
                Spike(x: 1080, y: 786, w: 40, h: 34), Spike(x: 1180, y: 786, w: 40, h: 34),
                Spike(x: 1280, y: 786, w: 40, h: 34), Spike(x: 1380, y: 786, w: 40, h: 34),
                Spike(x: 1480, y: 786, w: 40, h: 34),
            ],
            checkpoints: [
                Checkpoint(x: 840, y: 480), Checkpoint(x: 1660, y: 480),
            ],
            flag: CGPoint(x: 2400, y: 300)
        ),
        Level(
            id: 2, world: 0,
            name: "Moss Crown",
            blurb: "Two lifts, a pit of iron, then the last gate.",
            width: 3920, height: 1120, killY: 1080,
            spawn: CGPoint(x: 84, y: 768),
            solids: [
                Solid(x: 0, y: 768, w: 760, h: 280, oneway: false),
                Solid(x: 900, y: 768, w: 280, h: 280, oneway: false),
                Solid(x: 1120, y: 960, w: 760, h: 140, oneway: false),
                Solid(x: 1880, y: 768, w: 360, h: 280, oneway: false),
                Solid(x: 2320, y: 672, w: 168, h: 26, oneway: true),
                // 96 between ledges, not 128.
                //
                // A running jump rises 120 at its very best, and only stays that high for the
                // middle of its arc — so a 128 step across a 72 gap was a ledge you rush past
                // and fail to land on. You arrive too low and there is nothing to do about it
                // once you are underneath. Reported as "some walls and platforms are too high
                // and character can never jump on it". 96 leaves a comfortable margin over a
                // single jump and keeps the climb the same length.
                Solid(x: 2560, y: 576, w: 168, h: 26, oneway: true),
                Solid(x: 2800, y: 480, w: 180, h: 26, oneway: true),
                Solid(x: 3040, y: 232, w: 640, h: 28, oneway: true),
            ],
            movers: [
                MoverDef(x: 1240, y: 768, w: 180, h: 22, axis: "x", distance: 60, period: 3.2, phase: 0),
                MoverDef(x: 1630, y: 768, w: 180, h: 22, axis: "x", distance: 70, period: 3.2, phase: .pi),
                MoverDef(x: 2920, y: 324, w: 200, h: 22, axis: "y", distance: 92, period: 3.8, phase: 0.4),
            ],
            coins: [
                Coin(x: 200, y: 710), Coin(x: 340, y: 700), Coin(x: 480, y: 690),
                Coin(x: 700, y: 710), Coin(x: 1020, y: 710), Coin(x: 1260, y: 680),
                Coin(x: 1560, y: 660), Coin(x: 1980, y: 710), Coin(x: 2400, y: 620),
                Coin(x: 2640, y: 490), Coin(x: 2888, y: 360), Coin(x: 3040, y: 180),
                Coin(x: 3280, y: 176), Coin(x: 3480, y: 176),
            ],
            lanterns: [Lantern(x: 380, y: 683), Lantern(x: 1500, y: 875), Lantern(x: 2644, y: 459)],

            spikes: [
                Spike(x: 420, y: 734, w: 40, h: 34), Spike(x: 640, y: 734, w: 40, h: 34),
                Spike(x: 1220, y: 926, w: 40, h: 34), Spike(x: 1320, y: 926, w: 40, h: 34),
                Spike(x: 1440, y: 926, w: 40, h: 34), Spike(x: 1560, y: 926, w: 40, h: 34),
                Spike(x: 1680, y: 926, w: 40, h: 34),
            ],
            checkpoints: [
                Checkpoint(x: 1000, y: 768), Checkpoint(x: 2040, y: 768),
            ],
            flag: CGPoint(x: 3520, y: 232)
        ),

        // ──────────── WORLD 2: EMBER CAVES ────────────
        Level(
            id: 6, world: 1,
            name: "Tinder Hall",
            blurb: "The first room down, and already it listens.",
            width: 2880, height: 880, killY: 860,
            spawn: CGPoint(x: 88, y: 580),
            solids: [
                Solid(x: 0, y: 580, w: 540, h: 280, oneway: false),
                Solid(x: 660, y: 580, w: 220, h: 280, oneway: false),
                Solid(x: 880, y: 580, w: 320, h: 32, oneway: true),
                Solid(x: 1300, y: 580, w: 200, h: 280, oneway: false),
                Solid(x: 1600, y: 460, w: 180, h: 28, oneway: true),
                Solid(x: 1860, y: 360, w: 180, h: 28, oneway: true),
                Solid(x: 2120, y: 580, w: 760, h: 280, oneway: false),
            ],
            movers: [
                MoverDef(x: 1710, y: 580, w: 200, h: 22, axis: "x", distance: 140, period: 3.6, phase: 0),
            ],
            coins: [
                Coin(x: 160, y: 528), Coin(x: 300, y: 528), Coin(x: 460, y: 528),
                Coin(x: 760, y: 528), Coin(x: 1040, y: 528), Coin(x: 1180, y: 528),
                Coin(x: 1400, y: 528), Coin(x: 1660, y: 408), Coin(x: 1920, y: 308),
                Coin(x: 2240, y: 528), Coin(x: 2440, y: 528), Coin(x: 2640, y: 528),
            ],
            lanterns: [Lantern(x: 270, y: 495), Lantern(x: 1400, y: 495), Lantern(x: 1950, y: 275)],

            spikes: [
                Spike(x: 600, y: 546, w: 40, h: 34), Spike(x: 1340, y: 546, w: 40, h: 34),
                Spike(x: 1450, y: 546, w: 40, h: 34),
            ],
            checkpoints: [Checkpoint(x: 1240, y: 580)],
            flag: CGPoint(x: 2740, y: 580)
        ),
        Level(
            id: 7, world: 1,
            name: "Sulphur Ledge",
            blurb: "Hold the line. The gap below is no accident.",
            width: 3200, height: 1080, killY: 1060,
            spawn: CGPoint(x: 88, y: 800),
            solids: [
                Solid(x: 0, y: 800, w: 380, h: 260, oneway: false),
                Solid(x: 480, y: 700, w: 200, h: 28, oneway: true),
                Solid(x: 760, y: 600, w: 200, h: 28, oneway: true),
                Solid(x: 1060, y: 800, w: 280, h: 260, oneway: false),
                Solid(x: 1380, y: 700, w: 180, h: 28, oneway: true),
                Solid(x: 1620, y: 540, w: 200, h: 28, oneway: true),
                Solid(x: 1880, y: 800, w: 200, h: 260, oneway: false),
                Solid(x: 2140, y: 700, w: 220, h: 28, oneway: true),
                Solid(x: 2440, y: 540, w: 220, h: 28, oneway: true),
                Solid(x: 2740, y: 380, w: 460, h: 28, oneway: true),
            ],
            movers: [
                MoverDef(x: 1120, y: 600, w: 180, h: 22, axis: "y", distance: 110, period: 3.4, phase: 0),
                MoverDef(x: 2200, y: 700, w: 180, h: 22, axis: "y", distance: 100, period: 3.6, phase: .pi / 2),
            ],
            coins: [
                Coin(x: 180, y: 748), Coin(x: 320, y: 748),
                Coin(x: 560, y: 648), Coin(x: 840, y: 548),
                Coin(x: 1180, y: 600), Coin(x: 1440, y: 648),
                Coin(x: 1700, y: 488), Coin(x: 1940, y: 748),
                Coin(x: 2220, y: 648), Coin(x: 2520, y: 488),
                Coin(x: 2820, y: 328), Coin(x: 2980, y: 328), Coin(x: 3140, y: 328),
            ],
            lanterns: [Lantern(x: 580, y: 615), Lantern(x: 1470, y: 615), Lantern(x: 2250, y: 615)],

            spikes: [
                Spike(x: 410, y: 766, w: 40, h: 34), Spike(x: 510, y: 766, w: 40, h: 34),
                Spike(x: 1100, y: 766, w: 40, h: 34), Spike(x: 1480, y: 766, w: 40, h: 34),
                Spike(x: 1580, y: 766, w: 40, h: 34), Spike(x: 2080, y: 766, w: 40, h: 34),
            ],
            checkpoints: [
                Checkpoint(x: 1080, y: 800), Checkpoint(x: 1900, y: 800),
            ],
            flag: CGPoint(x: 3040, y: 380)
        ),
        Level(
            id: 8, world: 1,
            name: "Pyre Path",
            blurb: "The stones rise and fall. So must you.",
            width: 3440, height: 1180, killY: 1160,
            spawn: CGPoint(x: 84, y: 860),
            solids: [
                Solid(x: 0, y: 860, w: 320, h: 300, oneway: false),
                Solid(x: 380, y: 760, w: 180, h: 28, oneway: true),
                Solid(x: 620, y: 640, w: 180, h: 28, oneway: true),
                Solid(x: 860, y: 500, w: 180, h: 28, oneway: true),
                Solid(x: 1140, y: 860, w: 280, h: 300, oneway: false),
                Solid(x: 1480, y: 720, w: 180, h: 28, oneway: true),
                Solid(x: 1740, y: 580, w: 180, h: 28, oneway: true),
                Solid(x: 2000, y: 460, w: 200, h: 28, oneway: true),
                Solid(x: 2280, y: 860, w: 320, h: 300, oneway: false),
                Solid(x: 2680, y: 700, w: 200, h: 28, oneway: true),
                Solid(x: 2980, y: 540, w: 360, h: 28, oneway: true),
            ],
            movers: [
                MoverDef(x: 1240, y: 714, w: 180, h: 22, axis: "y", distance: 124, period: 3.6, phase: 0),
                MoverDef(x: 2400, y: 719, w: 180, h: 22, axis: "y", distance: 119, period: 3.6, phase: .pi),
                MoverDef(x: 2700, y: 540, w: 200, h: 22, axis: "x", distance: 100, period: 3.2, phase: 0.5),
            ],
            coins: [
                Coin(x: 180, y: 808), Coin(x: 460, y: 708),
                Coin(x: 700, y: 588), Coin(x: 940, y: 448),
                Coin(x: 1180, y: 808), Coin(x: 1540, y: 668),
                Coin(x: 1800, y: 528), Coin(x: 2060, y: 408),
                Coin(x: 2320, y: 808), Coin(x: 2740, y: 648),
                Coin(x: 3040, y: 488), Coin(x: 3200, y: 488), Coin(x: 3320, y: 488),
            ],
            lanterns: [Lantern(x: 470, y: 675), Lantern(x: 1570, y: 635), Lantern(x: 2440, y: 775)],

            spikes: [
                Spike(x: 320, y: 826, w: 40, h: 34), Spike(x: 420, y: 826, w: 40, h: 34),
                Spike(x: 1140, y: 826, w: 40, h: 34), Spike(x: 2280, y: 826, w: 40, h: 34),
                Spike(x: 2380, y: 826, w: 40, h: 34),
            ],
            checkpoints: [
                Checkpoint(x: 1160, y: 860), Checkpoint(x: 2300, y: 860),
            ],
            flag: CGPoint(x: 3200, y: 540)
        ),
        Level(
            id: 9, world: 1,
            name: "Ash Crown",
            blurb: "Three columns, three falls, one final gate.",
            width: 3680, height: 1240, killY: 1220,
            spawn: CGPoint(x: 80, y: 940),
            solids: [
                Solid(x: 0, y: 940, w: 360, h: 280, oneway: false),
                Solid(x: 460, y: 800, w: 180, h: 28, oneway: true),
                Solid(x: 700, y: 660, w: 180, h: 28, oneway: true),
                Solid(x: 940, y: 520, w: 180, h: 28, oneway: true),
                Solid(x: 1220, y: 940, w: 280, h: 280, oneway: false),
                Solid(x: 1580, y: 800, w: 180, h: 28, oneway: true),
                Solid(x: 1840, y: 620, w: 200, h: 28, oneway: true),
                Solid(x: 2120, y: 460, w: 220, h: 28, oneway: true),
                Solid(x: 2420, y: 940, w: 320, h: 280, oneway: false),
                Solid(x: 2820, y: 800, w: 200, h: 28, oneway: true),
                Solid(x: 3100, y: 640, w: 220, h: 28, oneway: true),
                Solid(x: 3380, y: 460, w: 300, h: 28, oneway: true),
            ],
            movers: [
                MoverDef(x: 1860, y: 940, w: 200, h: 22, axis: "x", distance: 130, period: 3.4, phase: 0),
                MoverDef(x: 1720, y: 789, w: 200, h: 22, axis: "y", distance: 129, period: 3.8, phase: .pi / 3),
                MoverDef(x: 3110, y: 940, w: 200, h: 22, axis: "x", distance: 140, period: 3.4, phase: .pi),
                MoverDef(x: 2940, y: 799, w: 200, h: 22, axis: "y", distance: 119, period: 3.6, phase: 0.6),
            ],
            coins: [
                Coin(x: 180, y: 888), Coin(x: 540, y: 748), Coin(x: 780, y: 608),
                Coin(x: 1020, y: 468), Coin(x: 1280, y: 888), Coin(x: 1640, y: 748),
                Coin(x: 1900, y: 568), Coin(x: 2200, y: 408),
                Coin(x: 2480, y: 888), Coin(x: 2880, y: 748), Coin(x: 3160, y: 588),
                Coin(x: 3440, y: 408), Coin(x: 3560, y: 408),
            ],
            lanterns: [Lantern(x: 550, y: 715), Lantern(x: 1670, y: 715), Lantern(x: 2920, y: 715)],

            spikes: [
                Spike(x: 380, y: 906, w: 40, h: 34),
                Spike(x: 1180, y: 906, w: 40, h: 34), Spike(x: 1280, y: 906, w: 40, h: 34),
                Spike(x: 2380, y: 906, w: 40, h: 34), Spike(x: 2480, y: 906, w: 40, h: 34),
                Spike(x: 2580, y: 906, w: 40, h: 34),
            ],
            checkpoints: [
                Checkpoint(x: 1240, y: 940), Checkpoint(x: 2440, y: 940),
            ],
            flag: CGPoint(x: 3460, y: 460)
        ),
    ]

    static func count(in world: Int) -> Int {
        all.filter { $0.world == world }.count
    }
}

struct World {
    let id: Int
    let name: String
    let blurb: String
    /// The free tier. Exactly one world is free, so the paid set is genuinely
    /// additional rather than a way to finish the free one.
    let free: Bool
}

enum Worlds {
    /// Six worlds. One free, five behind the single in-app purchase.
    static let all: [World] = [
        World(id: 0, name: "Mossgate Dusk", blurb: "The wick still burns.", free: true),
        World(id: 1, name: "Ember Caves",  blurb: "A warm light, deeper down.", free: false),
        World(id: 2, name: "Frost Spires", blurb: "Cold stone, and a wind that never stops.", free: false),
        World(id: 3, name: "Void Garden",  blurb: "Nothing grows here. It still glows.", free: false),
        World(id: 4, name: "Sunken Choir", blurb: "The water kept the singing.", free: false),
        World(id: 5, name: "Ashen Crown",  blurb: "The last gate before the dark.", free: false),
    ]

    /// Gates in every world. Fixed, even though the layouts are rebuilt each run:
    /// progress, the "3/6" on the title screen and the "world complete" rule all
    /// depend on the count being stable.
    static let gatesPerWorld = 6
}