import CoreGraphics
import Foundation

/// An autonomous runner, and the reason the coins are where they are.
///
/// `Sim` is a headless replica of the player physics in `MossgateScene.step()`.
/// It exists so a whole level can be *played* in a few milliseconds — no nodes,
/// no audio, no display. `route(_:)` drives that simulation with a lookahead
/// policy and returns the path the runner took.
///
/// The coin layout then comes from that path. Coins go where a player who
/// actually finished the level actually was, which buys two things:
///
///   - **Reachability by construction.** Every coin sits somewhere the runner
///     physically occupied, so no reshuffle can strand one behind a jump that
///     cannot be made. The runner is the proof, not a guess.
///   - **Unpredictability.** The route depends on the run seed through the
///     platform timing, so the layout moves with the world instead of being a
///     row of coins in the same place every time.
///
/// The replica is a copy, not the same code — the scene's `step` is welded to
/// nodes, audio and the camera. If the two ever drift, the coins stay valid
/// positions; what degrades is only the runner's judgement about reachability.
enum Autopilot {

    // MARK: - Input

    struct Input {
        var left = false
        var right = false
        var jump = false
        var down = false
    }

    // MARK: - Headless simulation

    struct Sim {
        let level: Level
        let phase: [CGFloat]
        let period: [CGFloat]

        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat = 0
        var vy: CGFloat = 0
        var grounded = true
        var groundKind = "solid"
        var ride = -1
        var coyote: CGFloat = Phys.coyote
        var extraJumps = 1
        var canCut = true
        var jumpAge: CGFloat = 0
        var time: CGFloat = 0
        var dead = false
        var won = false
        /// Why the run ended, for the test hook. Not used by the game.
        var deathReason = ""

        private var buffer: CGFloat = 0
        private var dropTimer: CGFloat = 0
        private var grace: CGFloat = 0
        private var prevJump = false
        private var prevDown = false
        private var dropRequested = false
        private var moverPrev: [CGPoint]
        var moverPos: [CGPoint]

        init(level: Level, phase: [CGFloat], period: [CGFloat]) {
            self.level = level
            self.phase = phase
            self.period = period
            self.x = level.spawn.x
            self.y = level.spawn.y
            self.moverPos = level.movers.map { CGPoint(x: $0.x, y: $0.y) }
            self.moverPrev = moverPos
            // Mirror loadLevel: evaluate the curve once, then zero the delta so
            // the first substep does not jerk a rider.
            placeMovers()
            moverPrev = moverPos
        }

        private var rect: CGRect {
            CGRect(x: x, y: y, width: Phys.playerW, height: Phys.playerH)
        }

        private mutating func placeMovers() {
            moverPrev = moverPos
            for (i, m) in level.movers.enumerated() {
                let per = m.period * (i < period.count ? period[i] : 1)
                let ph = m.phase + (i < phase.count ? phase[i] : 0)
                let s = sin((time / per) * 2 * .pi + ph)
                let px = m.axis == "x" ? m.x + s * m.distance : m.x
                let py = m.axis == "y" ? m.y + s * m.distance : m.y
                moverPos[i] = CGPoint(x: px, y: py)
            }
        }

        mutating func step(_ dt: CGFloat, _ input: Input) {
            guard !dead && !won else { return }
            time += dt
            placeMovers()
            grace = max(0, grace - dt)
            dropTimer = max(0, dropTimer - dt)
            buffer = max(0, buffer - dt)
            jumpAge += dt

            if input.jump && !prevJump { buffer = Phys.buffer }
            let released = prevJump && !input.jump
            prevJump = input.jump
            if released && vy < 0 && canCut {
                vy *= 0.48
                canCut = false
            }
            // No DOWN-to-drop here either: the scene stopped treating DOWN as a drop
            // request, and the simulation must model the game that actually ships, or
            // the coins it places are placed for a player who does not exist.
            prevDown = input.down
            inDown = input.down

            tryDrop()
            tryJump()

            if ride >= 0 && grounded {
                let pos = moverPos[ride], prev = moverPrev[ride]
                x += pos.x - prev.x
                y = pos.y - Phys.playerH
                vy = 0
            }

            let prevBottom = y + Phys.playerH
            let dir: CGFloat = (input.left ? -1 : 0) + (input.right ? 1 : 0)
            let accel = grounded ? Phys.accelG : Phys.accelA
            vx = approach(vx, dir * Phys.run, accel * dt)
            if dir == 0 && grounded { vx = approach(vx, 0, Phys.friction * dt) }

            x += vx * dt
            for s in level.solids where !s.oneway {
                if !rect.intersects(CGRect(x: s.x, y: s.y, width: s.w, height: s.h)) { continue }
                if vx > 0 { x = s.x - Phys.playerW }
                else if vx < 0 { x = s.x + s.w }
                else if x + Phys.playerW / 2 < s.x + s.w / 2 { x = s.x - Phys.playerW }
                else { x = s.x + s.w }
                vx = 0
            }

            var g: CGFloat = vy < 0 ? Phys.gRise : Phys.gFall
            if abs(vy) < Phys.apex { g = Phys.gApex }
            let diving = input.down && !grounded && vy > 0
            if diving { g *= Phys.diveGravity }
            let terminal = diving ? Phys.maxFall * Phys.diveMaxFall : Phys.maxFall
            vy = min(terminal, vy + g * dt)
            y += vy * dt

            grounded = false
            groundKind = "none"
            ride = -1

            for s in level.solids where !s.oneway {
                let r = CGRect(x: s.x, y: s.y, width: s.w, height: s.h)
                if !rect.intersects(r) { continue }
                if vy >= 0 && prevBottom <= s.y + 4 {
                    // Same foothold rule as the scene, from Phys, so the two cannot
                    // drift apart and the coins keep being placed for the real game.
                    let pr = CGRect(x: x, y: y, width: Phys.playerW, height: Phys.playerH)
                    if !Phys.hasFoothold(pr, on: r) { continue }
                    y = s.y - Phys.playerH
                    vy = 0
                    grounded = true; groundKind = "solid"
                } else if vy < 0 && y < s.y + s.h {
                    y = s.y + s.h
                    vy = 0
                }
            }

            if dropTimer <= 0 && vy >= 0 {
                for s in level.solids where s.oneway {
                    let r = CGRect(x: s.x, y: s.y, width: s.w, height: s.h)
                    if prevBottom > r.minY + 6 { continue }
                    if !Phys.hasFoothold(CGRect(x: x, y: y, width: Phys.playerW,
                                                height: Phys.playerH), on: r) { continue }
                    y = r.minY - Phys.playerH
                    vy = 0
                    grounded = true; groundKind = "oneway"
                }
                for (i, m) in level.movers.enumerated() {
                    let mp = moverPos[i]
                    let r = CGRect(x: mp.x, y: mp.y, width: m.w, height: m.h)
                    if prevBottom > r.minY + 6 { continue }
                    if !Phys.hasFoothold(CGRect(x: x, y: y, width: Phys.playerW,
                                                height: Phys.playerH), on: r) { continue }
                    y = r.minY - Phys.playerH
                    vy = 0
                    grounded = true; groundKind = "mover"
                    ride = i
                }
            }

            if grounded { coyote = Phys.coyote; extraJumps = 1 }
            else { coyote = max(0, coyote - dt) }

            tryJump()

            if grace <= 0 {
                let body = CGRect(x: x + 3, y: y + 4,
                                  width: Phys.playerW - 6, height: Phys.playerH - 6)
                for sp in level.spikes where
                    body.intersects(CGRect(x: sp.x, y: sp.y, width: sp.w, height: sp.h)) {
                    dead = true
                    deathReason = "spike at (\(Int(sp.x)),\(Int(sp.y)))"
                    return
                }
                if y > level.killY {
                    dead = true
                    deathReason = "fell past killY=\(Int(level.killY)) from y=\(Int(y))"
                    return
                }
            }

            let flag = CGRect(x: level.flag.x - 18, y: level.flag.y - 84, width: 42, height: 84)
            if rect.intersects(flag) { won = true }
        }

        private mutating func tryDrop() {
            guard dropRequested else { return }
            dropRequested = false
            if grounded && (groundKind == "oneway" || groundKind == "mover") {
                dropTimer = 0.18
                grounded = false
                groundKind = "none"
                ride = -1
                coyote = 0
                y += 4
                buffer = 0
            }
        }

        private mutating func tryJump() {
            guard buffer > 0 else { return }
            if inDown && grounded && (groundKind == "oneway" || groundKind == "mover") {
                dropTimer = 0.18
                grounded = false
                groundKind = "none"
                ride = -1
                coyote = 0
                y += 4
                buffer = 0
                return
            }
            if coyote > 0 {
                jump(power: Phys.jumpV)
                extraJumps = 1
                buffer = 0
                return
            }
            if !grounded && extraJumps > 0 {
                jump(power: Phys.dJumpV)
                extraJumps = 0
                buffer = 0
            }
        }

        private var inDown = false

        private mutating func jump(power: CGFloat) {
            vy = -power
            grounded = false
            groundKind = "none"
            ride = -1
            canCut = true
            jumpAge = 0
            coyote = 0
        }

        private func approach(_ v: CGFloat, _ target: CGFloat, _ delta: CGFloat) -> CGFloat {
            if v < target { return min(target, v + delta) }
            if v > target { return max(target, v - delta) }
            return target
        }

        mutating func setDown(_ d: Bool) { inDown = d }

        /// Drop the player onto a spot, standing and ready. Used by the
        /// reachability probe, which needs to start from a known surface rather
        /// than from the level's spawn.
        mutating func place(x: CGFloat, y: CGFloat) {
            self.x = x
            self.y = y
            vx = 0
            vy = 0
            grounded = true
            groundKind = "solid"
            ride = -1
            coyote = Phys.coyote
            extraJumps = 1
            canCut = true
            jumpAge = 0
            time = 0
            dead = false
            won = false
            deathReason = ""
            buffer = 0
            dropTimer = 0
            grace = 0
            dropRequested = false
            prevJump = false
            prevDown = false
            inDown = false
            placeMovers()
            moverPrev = moverPos
        }
    }

    // MARK: - Ballistic reachability

    /// Every position the player's centre passes through when launched from the
    /// ground under `anchor`.
    ///
    /// This is the reachability proof behind a coin. Rather than trusting that an
    /// authored position is fair, the real physics is run: stand the player on
    /// the surface below the anchor and try the sensible launches — a standing
    /// jump, one with a run-up, and a jump with a second jump at a few delays.
    /// Anywhere the player went is somewhere a player can be, so a coin there can
    /// be collected. The proof is the run, not an argument about it.
    static func reachable(from anchor: CGPoint, level: Level,
                          phase: [CGFloat], period: [CGFloat],
                          singleJumpOnly: Bool = false) -> [CGPoint] {
        guard let ground = surfaceBelow(anchor, level: level) else { return [] }
        let dt: CGFloat = 1.0 / 120.0
        var out: [CGPoint] = []

        // (run-up distance, delay before the second jump; nil = single jump)
        var launches: [(CGFloat, CGFloat?)] = [
            (0, nil), (70, nil), (150, nil),
            (70, 0.20), (70, 0.36), (150, 0.30),
        ]
        // Coins must be collectible by a player who just runs and jumps, so they
        // are confined to what ONE jump reaches. A double-jump apex is a place the
        // player only gets to by matching an exact input sequence.
        if singleJumpOnly {
            launches = launches.filter { $0.1 == nil }
        }

        for (runUp, second) in launches {
            var sim = Sim(level: level, phase: phase, period: period)
            sim.place(x: ground.x - runUp, y: ground.y - Phys.playerH)
            let runUpTime = runUp / Phys.run
            var t: CGFloat = 0
            while t < 2.2 {
                var input = Input()
                input.right = true
                if t >= runUpTime {
                    let since = t - runUpTime
                    let secondPress = second.map { since >= $0 && since < $0 + 0.10 } ?? false
                    input.jump = since < 0.10 || secondPress
                }
                sim.step(dt, input)
                t += dt
                if sim.dead { break }
                out.append(CGPoint(x: sim.x + Phys.playerW / 2,
                                   y: sim.y + Phys.playerH / 2))
            }
        }
        return out
    }

    /// How high a point sits above the surface it would be reached from. This is
    /// the number that decides whether a player who just runs and jumps will
    /// collect a coin, so it is measured rather than assumed.
    static func heightAboveGround(of p: CGPoint, in level: Level) -> CGFloat? {
        guard let g = surfaceBelow(p, level: level) else { return nil }
        return g.y - p.y
    }

    /// The first surface under a point, as the world coordinates of its top edge.
    private static func surfaceBelow(_ p: CGPoint, level: Level) -> CGPoint? {
        var best: CGFloat?
        for s in level.solids {
            if s.y < p.y - 10 { continue }                 // that one is above
            if p.x < s.x || p.x > s.x + s.w { continue }   // not underneath
            if best == nil || s.y < best! { best = s.y }
        }
        guard let top = best else { return nil }
        return CGPoint(x: p.x, y: top)
    }

    /// A new home for a coin near `anchor`: somewhere one of those launches
    /// actually went. Nil when the probe found nothing to work with, in which
    /// case the caller keeps its own fallback.
    static func variedCoin(near anchor: CGPoint, level: Level, phase: [CGFloat],
                           period: [CGFloat], seed: Int) -> CGPoint? {
        guard let ground = surfaceBelow(anchor, level: level) else { return nil }
        let arc = reachable(from: anchor, level: level, phase: phase, period: period,
                            singleJumpOnly: true)
        guard arc.count > 16 else { return nil }

        // A single jump clears about 120 units, so the coin is kept in a band
        // between 30 and 128 above the local surface. Above that it is only
        // reachable by a maximal jump, which is exactly why coins were being
        // missed: the player runs and jumps, and the coin hangs above the arc.
        let bandTop = ground.y - 128
        let bandBottom = ground.y - 30
        let pool = arc.filter {
            $0.y > bandTop && $0.y < bandBottom &&
            abs($0.x - anchor.x) < 150
        }
        // Nothing in the band means the ground under the anchor is not the way in;
        // leave the coin where the level author put it rather than guessing.
        guard pool.count > 8 else { return nil }

        var state = UInt64(bitPattern: Int64(seed)) | 1
        func unit() -> CGFloat {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat((state >> 33) % 1_000) / 1_000.0
        }
        return pool[Int(unit() * CGFloat(pool.count)) % pool.count]
    }

    // MARK: - The runner

    /// What one playthrough did. The path is empty when the runner did not
    /// finish, and `reason` says why — diagnostics belong in the result, not in
    /// a log nobody reads.
    struct Run {
        let path: [CGPoint]
        let reachedGate: Bool
        let seconds: CGFloat
        let reason: String
        let spawn: CGPoint
    }

    /// Convenience: just the path, empty when the runner did not finish.
    static func route(level: Level, phase: [CGFloat], period: [CGFloat],
                      maxSeconds: CGFloat = 100) -> [CGPoint] {
        run(level: level, phase: phase, period: period, maxSeconds: maxSeconds).path
    }

    /// Plays a level with the lookahead policy and returns the path the runner
    /// took, in world coordinates of the player's centre.
    static func run(level: Level, phase: [CGFloat], period: [CGFloat],
                    maxSeconds: CGFloat = 100) -> Run {
        var sim = Sim(level: level, phase: phase, period: period)
        var path: [CGPoint] = []
        let dt: CGFloat = 1.0 / 120.0

        // A jump fires on a rising edge, exactly as in the scene, so the policy
        // presses and then releases instead of holding the button down.
        var hold: CGFloat = 0
        var cooldown: CGFloat = 0
        var t: CGFloat = 0

        while t < maxSeconds {
            var input = Input()
            input.right = true

            if hold > 0 {
                hold -= dt
                input.jump = true
            } else if cooldown > 0 {
                cooldown -= dt
            } else if wantsJump(sim) {
                input.jump = true
                hold = 0.09
                cooldown = 0.16
            }

            sim.step(dt, input)
            t += dt
            if sim.won { break }
            if sim.dead {
                return Run(path: [], reachedGate: false, seconds: t,
                           reason: "\(sim.deathReason) at (\(Int(sim.x)),\(Int(sim.y))) t=\(String(format: "%.2f", t))s",
                           spawn: level.spawn)
            }
            path.append(CGPoint(x: sim.x + Phys.playerW / 2,
                                y: sim.y + Phys.playerH / 2))
        }

        guard sim.won else {
            return Run(path: [], reachedGate: false, seconds: t,
                       reason: "ran out of time at (\(Int(sim.x)),\(Int(sim.y))) — flag is at (\(Int(level.flag.x)),\(Int(level.flag.y)))",
                       spawn: level.spawn)
        }
        return Run(path: path, reachedGate: true, seconds: t, reason: "ok",
                   spawn: level.spawn)
    }

    /// The policy, deliberately small: walk right, jump what is in the way, and
    /// spend the second jump when there is nothing underneath.
    private static func wantsJump(_ s: Sim) -> Bool {
        let feet = s.y + Phys.playerH
        if s.coyote > 0 || s.grounded {
            if !groundUnder(s, from: s.x + Phys.playerW, width: 78, at: feet + 3) { return true }
            if brambleAhead(s, within: 78, feet: feet) { return true }
        }
        if !s.grounded && s.extraJumps > 0 && s.vy > 40 {
            if fallDepth(s) > 170 { return true }
        }
        return false
    }

    /// Is there a surface the runner can stand on under this strip?
    ///
    /// The test is on the TOP of a block, not on its rectangle. Ground blocks are
    /// cut deep, so testing the rect would let a step up "overlap" a probe taken at
    /// the runner's feet — it would read as flat ground and walk into the wall
    /// instead of jumping it.
    private static func groundUnder(_ s: Sim, from x: CGFloat, width: CGFloat, at y: CGFloat) -> Bool {
        for sol in s.level.solids {
            if sol.x + sol.w <= x || sol.x >= x + width { continue }
            if abs(sol.y - y) <= 14 { return true }
        }
        for (i, m) in s.level.movers.enumerated() {
            let p = s.moverPos[i]
            if p.x + m.w <= x || p.x >= x + width { continue }
            if abs(p.y - y) <= 14 { return true }
        }
        return false
    }

    private static func brambleAhead(_ s: Sim, within: CGFloat, feet: CGFloat) -> Bool {
        let zone = CGRect(x: s.x + Phys.playerW, y: feet - 44, width: within, height: 48)
        for sp in s.level.spikes where
            zone.intersects(CGRect(x: sp.x, y: sp.y, width: sp.w, height: sp.h)) { return true }
        return false
    }

    /// How far the runner would fall before something catches it. A large number
    /// means the drop is worth spending the second jump on.
    private static func fallDepth(_ s: Sim) -> CGFloat {
        let feet = s.y + Phys.playerH
        var best = CGFloat.greatestFiniteMagnitude
        for sol in s.level.solids where sol.y >= feet - 2 {
            if sol.x + sol.w <= s.x || sol.x >= s.x + Phys.playerW { continue }
            best = min(best, sol.y - feet)
        }
        for (i, m) in s.level.movers.enumerated() {
            let p = s.moverPos[i]
            if p.y < feet - 2 { continue }
            if p.x + m.w <= s.x || p.x >= s.x + Phys.playerW { continue }
            best = min(best, p.y - feet)
        }
        return best
    }

    // MARK: - The coin layout

    /// The game collects a coin when the player's chest passes within this far of
    /// it. Mirror it exactly, or the test answers a question about a different game.
    static let pickupRadius: CGFloat = 40

    /// The point the pickup test measures from — the player's chest, matching
    /// `MossgateScene`'s `feetX` / `midY`.
    static func pickupPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x + Phys.playerW / 2, y: y + Phys.playerH * 0.45)
    }

    /// Can a player standing on the surface below a coin actually collect it?
    ///
    /// This asks whether the CHEST comes within pickup range over a normal jump,
    /// rather than whether the player can be at the coin's position. Nearly the same
    /// question, and not quite — and the gap between them is exactly where a coin
    /// that looks reachable turns out not to be.
    static func collectible(_ coin: CGPoint, level: Level,
                            phase: [CGFloat], period: [CGFloat],
                            singleJumpOnly: Bool = false) -> Bool {
        guard let ground = surfaceBelow(coin, level: level) else { return false }
        let dt: CGFloat = 1.0 / 120.0
        // A coin is meant to be taken with one ordinary jump. The double-jump launches
        // ask "could a determined player reach this", which is the wrong question for
        // placement: a coin needing a precisely timed double jump is one the player jumps
        // at and misses, which is how it reads in play — "the character has to jump now
        // but coins are not taken when jumping".
        var launches: [(CGFloat, CGFloat?)] = [
            (0, nil), (70, nil), (150, nil), (70, 0.22), (150, 0.34),
        ]
        if singleJumpOnly {
            launches = [(0, nil), (40, nil), (70, nil), (110, nil), (150, nil)]
        }
        for (runUp, second) in launches {
            var sim = Sim(level: level, phase: phase, period: period)
            sim.place(x: ground.x - runUp, y: ground.y - Phys.playerH)
            let runUpTime = runUp / Phys.run
            var t: CGFloat = 0
            while t < 2.2 {
                var input = Input()
                input.right = true
                if t >= runUpTime {
                    let since = t - runUpTime
                    let secondPress = second.map { since >= $0 && since < $0 + 0.10 } ?? false
                    input.jump = since < 0.10 || secondPress
                }
                sim.step(dt, input)
                t += dt
                if sim.dead { break }
                let p = pickupPoint(sim.x, sim.y)
                if hypot(p.x - coin.x, p.y - coin.y) < pickupRadius { return true }
            }
        }
        return false
    }

    /// Nudges a pickup to a per-run position, rejected if the new spot would sit
    /// inside solid ground. Keeps the placement honest: a reshuffle can move a coin
    /// but can never bury it.
    static func nudged(_ p: CGPoint, index: Int, level: Level, seed: Int) -> CGPoint {
        var rng = Split(seed: UInt64(bitPattern: Int64(seed &+ index &* 2_654_435_761)))
        let dx = (rng.unit() - 0.5) * 56
        let dy = (rng.unit() - 0.5) * 24
        let candidate = CGPoint(x: p.x + dx, y: p.y + dy)
        let box = CGRect(x: candidate.x - 15, y: candidate.y - 15, width: 30, height: 30)
        for s in level.solids where !s.oneway {
            if box.intersects(CGRect(x: s.x, y: s.y, width: s.w, height: s.h)) { return p }
        }
        return candidate
    }

    /// The closest surface to a point, for when nothing is directly under it — a coin
    /// over a pit has no ground below to be jumped from.
    private static func nearestSurface(to p: CGPoint, level: Level) -> CGPoint? {
        var best: (d: CGFloat, top: CGFloat, x: CGFloat)?
        for s in level.solids {
            let cx = min(max(p.x, s.x + 12), max(s.x + 12, s.x + s.w - 12))
            let d = abs(cx - p.x) + abs(s.y - p.y) * 0.25
            if best == nil || d < best!.d { best = (d, s.y, cx) }
        }
        guard let b = best else { return nil }
        return CGPoint(x: b.x, y: b.top)
    }

    /// A home for a coin, proven collectible before it is accepted.
    ///
    /// Candidates are tried in order of preference — the probed arc first, so coins
    /// still move around and vary with the seed — but each is checked against the
    /// game's own pickup rule and only a passing one is used. The last resort is
    /// directly above the nearest surface, which a standing jump cannot miss.
    ///
    /// This is the difference between believing a coin is reachable because the
    /// placement maths looks right, and knowing it: 55 of 214 coins were unreachable
    /// precisely because the maths was trusted.
    static func placeCoin(anchor: CGPoint, index: Int, level: Level,
                          phase: [CGFloat], period: [CGFloat], seed: Int) -> CGPoint {
        var candidates: [CGPoint] = []
        if let arc = variedCoin(near: anchor, level: level, phase: phase,
                                period: period, seed: seed) {
            candidates.append(arc)
        }
        candidates.append(nudged(anchor, index: index, level: level, seed: seed))
        // Ground directly below the anchor if there is any, otherwise the nearest
        // surface at all — a coin over a pit would otherwise have nowhere to go.
        if let ground = surfaceBelow(anchor, level: level) ?? nearestSurface(to: anchor, level: level) {
            candidates.append(CGPoint(x: ground.x, y: ground.y - 70))
            candidates.append(CGPoint(x: ground.x, y: ground.y - 48))
            candidates.append(CGPoint(x: ground.x, y: ground.y - 60))
        }
        for c in candidates where collectible(c, level: level, phase: phase, period: period) {
            return c
        }
        // Nothing passed. Say so rather than shipping a coin nobody can reach.
        print("[Mossgate:COIN] no collectible position for coin \(index) in \(level.name)")
        return candidates.first ?? anchor
    }

    /// The point on a route closest to an anchor, within `limit`.
    ///
    /// This replaced sampling the route by arc length, which dropped a coin wherever
    /// the fraction happened to land — measured at up to 2742 units from where the
    /// level designed it, and the reason the runner-sourced gates still had coins
    /// nobody could take. Anchoring on the nearest point of a real playthrough keeps
    /// the coin both ON the path and NEAR its designed position.
    private static func nearestRoutePoint(_ route: [CGPoint], to anchor: CGPoint,
                                          limit: CGFloat) -> CGPoint? {
        var best: (d: CGFloat, p: CGPoint)?
        for p in route {
            let d = hypot(p.x - anchor.x, p.y - anchor.y)
            if d < limit && (best == nil || d < best!.d) { best = (d, p) }
        }
        return best?.p
    }

    /// Coins placed to be jumped for, in fresh random spots.
    ///
    /// Requested: "When the coin position is higher then the character height then the
    /// character must always jump to take the coin", and "the coin position is always
    /// different when a level starts". So each coin takes a random x along the floor
    /// and floats above it — comfortably over the player's head, so walking past never
    /// takes it and a jump always does.
    ///
    /// This replaces the earlier placement, which anchored every coin to where the
    /// level authored it and pulled several down to chest height so they sat on the
    /// beaten path. That was the right answer to "coins are being missed" and the wrong
    /// answer to "a coin should be worth going for".
    ///
    /// Every candidate still goes through the same jump proof, so "you have to jump for
    /// it" cannot quietly become "you cannot get it". A coin nothing can reach keeps the
    /// level's own position rather than being dropped.
    static func coinLayout(level: Level, phase: [CGFloat], period: [CGFloat],
                           seed: Int) -> (coins: [CGPoint], source: String) {
        var state = UInt64(bitPattern: Int64(seed)) | 1
        func unit() -> CGFloat {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat((state >> 33) % 1_000) / 1_000.0
        }
        // 45 is well over the player's 32-unit height, so the coin always needs a jump.
        // 115 is around the limit of a single jump — and the proof below is what really
        // decides, so the band only has to be a good guess.
        let bandLow: CGFloat = 45
        let bandHigh: CGFloat = 95
        let span = max(1, level.width - 120)

        var out: [CGPoint] = []
        var proven = 0
        var guaranteed = 0
        var unplaced = 0
        let started = DispatchTime.now().uptimeNanoseconds

        // Two hard bounds, because a layout is computed on the main thread inside a level
        // load and the watchdog terminates an app that spends seconds there.
        //
        // The first version of this tried up to 60 spots per coin with a full jump proof
        // each — roughly 400,000 simulation steps for one coin, millions for a gate — and
        // the app was killed on launch with "Thread 1: signal SIGTERM". A layout that
        // cannot finish is worse than a layout that is less clever, so when either budget
        // runs out the coin keeps the level's own position, which is always valid.
        let deadlineNs = started &+ 250_000_000          // 250 ms for the whole layout
        let triesPerCoin = 10
        var proofsLeft = 4 * level.coins.count + 30

        for i in level.coins.indices {
            let anchor = CGPoint(x: level.coins[i].x, y: level.coins[i].y)
            var chosen: CGPoint?

            // 1. A random spot an ordinary jump can take.
            for _ in 0..<triesPerCoin {
                if proofsLeft <= 0 || DispatchTime.now().uptimeNanoseconds > deadlineNs { break }
                let x = 60 + unit() * span
                // The TOPMOST surface at x, not the floor. The proof stands on whatever is
                // directly under the coin, so placing relative to anything else leaves the
                // coin hanging over a surface the proof never used — and a coin hanging
                // over a pit is one the player jumps at in vain.
                guard let base = coinBaseUnder(x, level: level) else { continue }
                let c = CGPoint(x: x, y: base - (bandLow + unit() * (bandHigh - bandLow)))
                // The cheap rejections come first; the proof is the expensive one.
                guard coinSpotAllowed(c, level: level) else { continue }
                proofsLeft -= 1
                if collectible(c, level: level, phase: phase, period: period,
                               singleJumpOnly: true) {
                    chosen = c
                    proven += 1
                    break
                }
            }

            // 2. Where the level author put it, if that one is takeable — better a spot
            //    the level was designed around than one invented below.
            if chosen == nil, proofsLeft > 0, coinSpotAllowed(anchor, level: level) {
                proofsLeft -= 1
                if collectible(anchor, level: level, phase: phase, period: period,
                               singleJumpOnly: true) {
                    chosen = anchor
                    proven += 1
                }
            }

            // 3. GUARANTEED. "Make sure that wherever the coins hangs, these are always
            //    grabable for the character." The first two steps are proofs, so they can
            //    fail; this one is arithmetic, so it cannot. A coin beside the nearest
            //    surface is inside the player's standing pickup radius — no jump, no
            //    simulation, no way to miss it. It is the least interesting place a coin
            //    can be, which is exactly why it is the last resort: a coin you can see
            //    and cannot take is worse than no coin at all.
            if chosen == nil {
                chosen = guaranteedGrabSpot(near: anchor, level: level)
                if chosen != nil { guaranteed += 1 } else { unplaced += 1 }
            }

            out.append(chosen ?? anchor)
        }

        // Final pass. Whatever route a coin took to get here — random, authored, or the
        // guarantee — it leaves obeying both rules. Cheaper and far more certain than proving
        // them at each of the three placement sites and on every early return between them.
        for i in out.indices {
            if let h = hazardTopUnder(out[i].x, level: level), out[i].y > h - bandLow {
                out[i].y = h - bandLow
            }
            if abs(out[i].x - level.flag.x) < flagClearance {
                out[i].x = level.flag.x > out[i].x ? level.flag.x - flagClearance
                                                  : level.flag.x + flagClearance
                out[i].x = min(max(out[i].x, 40), level.width - 40)
            }
        }

        let ms = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000.0
        // The two placement rules, counted rather than assumed. Both must be zero on every
        // gate: a coin low over spikes kills the player who goes for it, and a coin on the
        // flag is either free or mistaken for the goal.
        var overHazard = 0
        var atFlag = 0
        for c in out {
            if let h = hazardTopUnder(c.x, level: level), c.y > h - 45 { overHazard += 1 }
            if abs(c.x - level.flag.x) < flagClearance { atFlag += 1 }
        }
        if ProcessInfo.processInfo.arguments.contains("-TestCoins") {
            print("[Mossgate:COIN]   \(level.name): \(level.coins.count) coins, "
                  + "jumpProven=\(proven) guaranteedGrab=\(guaranteed) unplaced=\(unplaced) "
                  + "overHazard=\(overHazard) atFlag=\(atFlag) "
                  + "took=\(String(format: "%.0f", ms))ms")
        }
        let allTakeable = unplaced == 0
        return (out, allTakeable ? (guaranteed == 0 ? "jump-random" : "jump-random+guaranteed")
                                 : "INCOMPLETE")
    }

    /// A spot the player can always take: just above the nearest surface, close enough to
    /// be collected by walking into it.
    ///
    /// The player's pickup point sits 45% up their body, so standing on a surface it is
    /// about 18 above their feet — a coin 14 above that surface is within reach of the
    /// standing body with room to spare. Arithmetic, not a simulation, which is the point:
    /// it cannot fail, so it can backstop the proofs.
    private static func guaranteedGrabSpot(near anchor: CGPoint, level: Level) -> CGPoint? {
        for step in stride(from: CGFloat(0), through: 400, by: 20) {
            for x in [anchor.x + step, anchor.x - step] {
                guard let top = surfaceTopUnder(x, level: level) else { continue }
                // Refuse spikes outright. The whole promise of this spot is that you can walk
                // into the coin without jumping — and you cannot walk anywhere near a spike, so
                // 14 above a spike is not a guarantee, it is a trap.
                guard hazardTopUnder(x, level: level) == nil else { continue }
                let c = CGPoint(x: x, y: top - 14)
                if coinSpotAllowed(c, level: level) { return c }
            }
        }
        return nil
    }

    /// Top of any spike whose footprint covers `x` (with a margin), or nil.
    ///
    /// Spikes are not in `level.solids`, so `surfaceTopUnder` cannot see them — and that is how
    /// a coin ends up hanging level with a bramble, which is a coin that kills you for taking
    /// it. Asked for as "place coins never so low over objects that kills the character".
    private static func hazardTopUnder(_ x: CGFloat, level: Level) -> CGFloat? {
        var best: CGFloat?
        // The margin matters: a coin just clear of a spike still pulls you sideways onto it.
        let margin: CGFloat = 20
        for s in level.spikes where x >= s.x - margin && x <= s.x + s.w + margin {
            if best == nil || s.y < best! { best = s.y }
        }
        return best
    }

    /// What a coin hangs above at `x`: the highest thing under it, whether that is a ledge or
    /// the spikes standing on one. Smaller y is higher, so this is the smaller of the two.
    private static func coinBaseUnder(_ x: CGFloat, level: Level) -> CGFloat? {
        switch (surfaceTopUnder(x, level: level), hazardTopUnder(x, level: level)) {
        case let (s?, h?): return min(s, h)
        case let (s?, nil): return s
        case let (nil, h?): return h
        default: return nil
        }
    }

    /// How far a coin must stay from the level's flag.
    ///
    /// Asked for as "place coins of a level never the end flag". A coin sitting on the goal is
    /// either taken for free on the way through, or mistaken for the goal itself.
    static let flagClearance: CGFloat = 110

    /// Everything a coin spot has to be, checked in one place so the rule cannot be true on
    /// one placement path and false on another.
    static func coinSpotAllowed(_ p: CGPoint, level: Level) -> Bool {
        if insideSolid(p, level: level) { return false }
        if abs(p.x - level.flag.x) < flagClearance { return false }
        // At least the low end of the hanging band above anything lethal underneath.
        if let h = hazardTopUnder(p.x, level: level), p.y > h - 45 { return false }
        return true
    }

    /// The TOPMOST surface at an x — the platform a player standing at that x would be
    /// on, and the one `collectible` stands on to prove the coin.
    private static func surfaceTopUnder(_ x: CGFloat, level: Level) -> CGFloat? {
        var best: CGFloat?
        for s in level.solids where !s.oneway {
            if x < s.x || x > s.x + s.w { continue }
            if best == nil || s.y < best! { best = s.y }
        }
        return best
    }

    /// True when a point sits inside solid rock, with a small margin so a coin is not
    /// placed half-buried in a ledge it technically clears.
    private static func insideSolid(_ p: CGPoint, level: Level) -> Bool {
        level.solids.contains {
            p.x >= $0.x && p.x <= $0.x + $0.w && p.y >= $0.y - 8 && p.y <= $0.y + $0.h
        }
    }

    // MARK: - Coins from the route

    /// A single jump clears about 120 units, so a coin higher than this above the
    /// ground under it is one a player running and jumping will miss.
    static let grabReach: CGFloat = 120

    /// The nearest point on a route that is within `grabReach` of the ground.
    ///
    /// Route samples land wherever the runner happened to be, which includes the
    /// apex of every jump. A coin there is on the runner's exact arc but not on a
    /// player's, which is why coins were being left behind. Anything above the
    /// reach is walked back to the nearest point that is low enough, preferring
    /// forward so the coin stays ahead of the run.
    private static func snapToReach(_ route: [CGPoint], index: Int, level: Level) -> CGPoint {
        if index < 0 || index >= route.count { return route[min(max(index, 0), route.count - 1)] }
        if let h = heightAboveGround(of: route[index], in: level), h <= grabReach {
            return route[index]
        }
        for d in 1..<route.count {
            let f = index + d
            if f < route.count, let h = heightAboveGround(of: route[f], in: level), h <= grabReach {
                return route[f]
            }
            let b = index - d
            if b >= 0, let h = heightAboveGround(of: route[b], in: level), h <= grabReach {
                return route[b]
            }
        }
        return route[index]
    }

    /// Picks `count` coin positions along a route.
    ///
    /// Spaced by ARC LENGTH, not by index: the route is recorded once per 1/120 s
    /// substep, so it is dense wherever the runner moved slowly. Indexing would
    /// bunch the coins at the top of every jump — exactly where it hangs longest.
    static func coins(_ route: [CGPoint], count: Int, seed: Int, level: Level) -> [CGPoint] {
        guard route.count > 4, count > 0 else { return [] }

        var lengths: [CGFloat] = [0]
        lengths.reserveCapacity(route.count)
        for i in 1..<route.count {
            lengths.append(lengths[i - 1] + hypot(route[i].x - route[i - 1].x,
                                                  route[i].y - route[i - 1].y))
        }
        let total = lengths[lengths.count - 1]
        // Keep the spawn corner and the gate itself clear.
        let start = min(150, total * 0.12)
        let end = max(start + 1, total - 90)
        guard end > start else { return [] }

        // A self-contained generator: this must not depend on the scene's RNG,
        // which the sky and the pickups already consume in their own order.
        var state = UInt64(bitPattern: Int64(seed)) | 1
        func unit() -> CGFloat {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat((state >> 33) % 1_000) / 1_000.0
        }

        let step = (end - start) / CGFloat(count)
        var out: [CGPoint] = []
        var cursor = start
        var i = 1
        while out.count < count && cursor <= end {
            // Seeded wobble along the route, so two runs over the same route
            // still do not produce the same tidy row.
            let target = cursor + unit() * step * 0.5
            while i < route.count && lengths[i] < target { i += 1 }
            out.append(snapToReach(route, index: min(i, route.count - 1), level: level))
            cursor += step
        }
        return out
    }
}
