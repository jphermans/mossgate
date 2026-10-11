import CoreGraphics
import Foundation

/// Builds the gates that are not hand-authored, so a world is not the same six
/// levels every time you play it.
///
/// Every feature is emitted inside a limit the physics can actually clear — a gap
/// no wider than a running jump, a step no higher than one — which makes a
/// generated gate traversable **by construction**.
///
/// That is deliberately a static guarantee rather than a "can the bot finish it"
/// check. The autopilot only solves 1 of the 7 hand-designed gates, so gating
/// generation on its success would delete every feature it cannot handle and
/// collapse the output to flat ground. The constraints below are the guarantee;
/// the bot is a bonus validator, never the gatekeeper.
enum LevelGen {

    // MARK: - The limits

    /// A running jump covers about 178 units before it drops below its launch
    /// height, and clears about 120. These are what a gate is allowed to ask for.
    static let maxGap: CGFloat = 150
    static let maxStepUp: CGFloat = 110
    static let maxDrop: CGFloat = 260
    /// Clear level ground either side of a bramble, so it can be taken from a run.
    static let spikeClearance: CGFloat = 150
    /// The checker re-derives which block a bramble sits on, and that attribution
    /// can land on a neighbouring block. This tolerance exists so the check reports
    /// design violations rather than one-unit disagreements between the generator's
    /// placement arithmetic and the checker's.
    static let clearanceTolerance: CGFloat = 8
    /// How far apart one-way ledges may sit before the hop between them stops
    /// being a jump a player would recognise.
    static let maxLedgeHop: CGFloat = 130

    /// Ground blocks are cut deep so nothing can fall through one.
    private static let groundDepth: CGFloat = 420

    // MARK: - Per-world feel

    struct Profile {
        let width: CGFloat
        let height: CGFloat
        let groundY: CGFloat
        let gapMax: CGFloat
        let stepMax: CGFloat
        let spikeChance: CGFloat
        let moverChance: CGFloat
        let ledgeChance: CGFloat
    }

    /// Difficulty rises with the world index and then stops rising, because past
    /// `maxGap` / `maxStepUp` there is nothing left that is jumpable — the only
    /// thing growing after that would be unfairness.
    static func profile(world: Int) -> Profile {
        let w = CGFloat(max(0, min(world, 5)))
        return Profile(
            width: 2400 + w * 300,
            height: 760 + (world % 2 == 1 ? 160 : 0),
            groundY: 512,
            gapMax: min(maxGap, 96 + w * 11),
            stepMax: min(maxStepUp, 66 + w * 9),
            spikeChance: min(0.42, 0.14 + w * 0.06),
            moverChance: min(0.30, 0.08 + w * 0.045),
            ledgeChance: min(0.26, 0.06 + w * 0.04)
        )
    }

    // MARK: - Names

    private static let gateNames: [[String]] = [
        ["Moss Run", "Fern Hollow", "Wick Bend", "Pale Ledge", "Cairn Walk", "Dusk Span"],
        ["Ember Step", "Slag Run", "Cinder Walk", "Glow Vault", "Ash Bend", "Forge Span"],
        ["Frost Rim", "Rime Walk", "Cold Vault", "Pale Spire", "Hail Run", "Shiver Gate"],
        ["Void Bloom", "Null Walk", "Starless Run", "Hollow Vault", "Dark Span", "Waning Gate"],
        ["Drowned Step", "Choir Vault", "Tide Run", "Salt Span", "Deep Walk", "Echo Hall"],
        ["Ashen Crown", "Last Run", "Final Span", "Pyre Gate", "Dust Walk", "End Vault"],
    ]

    static func name(world: Int, slot: Int) -> String {
        let row = gateNames[max(0, min(world, gateNames.count - 1))]
        return row[((slot % row.count) + row.count) % row.count]
    }

    static let generatedBlurb = "Built fresh each run — the route is never the same twice."

    // MARK: - Generation

    /// One generated gate. Deterministic for a given (world, slot, seed).
    static func gate(world: Int, slot: Int, seed: Int) -> Level {
        let p = profile(world: world)
        var rng = Split(seed: UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15
                              &+ UInt64(slot &* 2_654_435_761) &+ UInt64(world &* 40_503))

        var solids: [Solid] = []
        var movers: [MoverDef] = []
        var spikes: [Spike] = []
        var checkpoints: [Checkpoint] = []
        var coins: [Coin] = []
        var lanterns: [Lantern] = []

        func slab(_ from: CGFloat, _ width: CGFloat, _ top: CGFloat) -> Solid {
            Solid(x: from, y: top, w: width, h: groundDepth, oneway: false)
        }
        func ledge(_ from: CGFloat, _ width: CGFloat, _ top: CGFloat) -> Solid {
            Solid(x: from, y: top, w: width, h: 20, oneway: true)
        }

        var x: CGFloat = 0
        var gy = p.groundY
        var lastCheckpoint: CGFloat = -10_000
        /// Past this depth the gate stops dropping. Without it a run of step-downs
        /// walks the floor under the kill plane and the player dies standing on it.
        let maxSink = p.groundY + 240

        // Opening run: a safe landing and a look at what is coming.
        solids.append(slab(0, 340, gy))
        x = 340

        while x < p.width - 640 {
            let roll = rng.unit()

            if roll < p.spikeChance {
                // Level ground with brambles in the middle, clear run either side.
                let w = rng.range(440, 720)
                solids.append(slab(x, w, gy))
                for k in 0..<rng.int(1, 2) {
                    let sx = x + spikeClearance + CGFloat(k) * 130
                    if sx + 44 < x + w - spikeClearance {
                        spikes.append(Spike(x: sx, y: gy - 26, w: 30, h: 26))
                        coins.append(Coin(x: sx + 15, y: gy - 76))
                    }
                }
                x += w

            } else if roll < p.spikeChance + p.moverChance {
                // A wide cut with a platform riding across it.
                let gap = rng.range(210, 330)
                let my = gy - rng.range(20, 70)
                movers.append(MoverDef(x: x + 20, y: my, w: rng.range(96, 130), h: 22,
                                       axis: "x", distance: gap - 110,
                                       period: rng.range(2.6, 4.0), phase: rng.unit() * 2 * .pi))
                x += gap
                let w = rng.range(380, 620)
                solids.append(slab(x, w, gy))
                x += w

            } else if roll < p.spikeChance + p.moverChance + p.ledgeChance {
                // A one-way bridge: hop along, or drop straight through.
                let gap = rng.range(240, 330)
                let count = Int(gap / maxLedgeHop)
                let per = gap / CGFloat(max(count, 1))
                for k in 0..<max(count, 1) {
                    solids.append(ledge(x + CGFloat(k) * per, 74, gy - 52))
                }
                x += gap + 60
                let w = rng.range(320, 520)
                solids.append(slab(x, w, gy))
                x += w

            } else if roll < p.spikeChance + p.moverChance + p.ledgeChance + 0.30 {
                // A gap. Nothing else — the plainest feature, and the one that
                // makes the rest readable.
                let gap = min(maxGap, rng.range(88, p.gapMax))
                x += gap
                let w = rng.range(360, 640)
                solids.append(slab(x, w, gy))
                x += w
                coins.append(Coin(x: x - w / 2, y: gy - 96))

            } else if roll < 0.78 {
                // Step up, with a short cut in front of the face so the run has to
                // be turned into a jump rather than just stopped by a wall.
                x += rng.range(26, 54)
                gy -= min(maxStepUp, rng.range(58, p.stepMax))
                let w = rng.range(300, 500)
                solids.append(slab(x, w, gy))
                x += w
                coins.append(Coin(x: x - w / 2, y: gy - 88))

            } else {
                // Step down — unless there is no room left to drop, in which case
                // this becomes a climb. Falling is free, so a drop only ever makes
                // the gate longer; the limit is there to bound the floor.
                let room = maxSink - gy
                if room < 70 {
                    gy -= min(maxStepUp, rng.range(58, p.stepMax))
                } else {
                    gy += min(room, rng.range(90, min(maxDrop, 210)))
                }
                let w = rng.range(320, 560)
                solids.append(slab(x, w, gy))
                x += w
            }

            if x - lastCheckpoint > 900 {
                checkpoints.append(Checkpoint(x: x - 60, y: gy - 40))
                lanterns.append(Lantern(x: x - 200, y: gy - 52))
                lastCheckpoint = x
            }
        }

        // Closing run and the gate.
        let tailStart = x
        let tail = max(360, p.width - tailStart)
        solids.append(slab(tailStart, tail, gy))
        x = tailStart + tail
        let flag = CGPoint(x: x - 130, y: gy - 10)
        // A final clear stretch so the gate is never a surprise landing.
        coins.append(Coin(x: tailStart + 150, y: gy - 92))
        coins.append(Coin(x: flag.x - 170, y: gy - 92))

        // Height and kill plane come from what was actually built, not from a
        // guess made before it was built: the deepest floor must sit well clear of
        // the plane, or the player dies standing on the last step down.
        let tops = solids.filter { !$0.oneway }.map { $0.y }
        let deepest = tops.max() ?? p.groundY
        let height = max(p.height, deepest + 380)
        let killY = deepest + 240

        return Level(
            id: gateKey(world: world, slot: slot),
            world: world,
            name: name(world: world, slot: slot),
            blurb: generatedBlurb,
            width: x,
            height: height,
            killY: killY,
            spawn: CGPoint(x: 88, y: p.groundY - 32),
            solids: solids,
            movers: movers,
            coins: coins,
            lanterns: lanterns,
            spikes: spikes,
            checkpoints: checkpoints,
            flag: flag
        )
    }

    /// A gate's stable address. Progress is stored against this, not against a
    /// position in a list, because the list is rebuilt every run.
    static func gateKey(world: Int, slot: Int) -> Int {
        world * Worlds.gatesPerWorld + slot
    }

    // MARK: - Checking

    /// What a generated gate asks of the player, so it can be checked against the
    /// limits instead of trusted.
    struct Report {
        var widestGap: CGFloat = 0
        var tallestStep: CGFloat = 0
        var brambles: Int = 0
        var bramblesTooTight: Int = 0
        /// The tightest clearance found, so a violation comes with numbers rather
        /// than just a count.
        var worstClearance: CGFloat = .greatestFiniteMagnitude
        var segments: Int = 0
        var ok: Bool { widestGap <= maxGap && tallestStep <= maxStepUp && bramblesTooTight == 0 }
    }

    /// Walks the sorted ground tops and measures every jump the gate demands.
    static func inspect(_ level: Level) -> Report {
        var r = Report()
        let ground = level.solids
            .filter { !$0.oneway }
            .sorted { $0.x < $1.x }
        guard ground.count > 1 else { return r }

        for i in 1..<ground.count {
            let prev = ground[i - 1], cur = ground[i]
            r.segments += 1
            let gapStart = prev.x + prev.w
            let gap = cur.x - gapStart
            let step = prev.y - cur.y          // positive = up, negative = down
            if gap > 0 {
                // A gap is only a demand on the player if nothing bridges it. A
                // mover or a run of one-way ledges means it is crossed, not jumped,
                // so measuring the raw distance would report a level as impossible
                // when it is merely a different kind of level.
                let bridged = level.movers.contains { $0.x + $0.w > gapStart && $0.x < cur.x }
                    || level.solids.contains { $0.oneway && $0.x + $0.w > gapStart && $0.x < cur.x }
                if !bridged { r.widestGap = max(r.widestGap, gap) }
            }
            if step > 0 { r.tallestStep = max(r.tallestStep, step) }
        }

        // Brambles need clear ground either side of them to be jumped from.
        for sp in level.spikes {
            r.brambles += 1
            let host = ground.first { sp.x >= $0.x - 1 && sp.x <= $0.x + $0.w }
            guard let host = host else { r.bramblesTooTight += 1; continue }
            let before = sp.x - host.x
            let after = (host.x + host.w) - (sp.x + sp.w)
            r.worstClearance = min(r.worstClearance, min(before, after))
            let need = spikeClearance - clearanceTolerance
            if before < need || after < need { r.bramblesTooTight += 1 }
        }
        return r
    }
}

/// A small deterministic generator. Local to this file on purpose: the sky, the
/// pickups and the coins already draw from other streams, and generation must not
/// be able to perturb them.
struct Split {
    private var state: UInt64
    init(seed: UInt64) { state = seed | 1 }
    private mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 17
    }
    mutating func unit() -> CGFloat { CGFloat(next() % 10_000) / 10_000.0 }
    mutating func range(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        guard hi > lo else { return lo }
        return lo + unit() * (hi - lo)
    }
    mutating func int(_ lo: Int, _ hi: Int) -> Int {
        guard hi > lo else { return lo }
        return lo + Int(next() % UInt64(hi - lo + 1))
    }
}
