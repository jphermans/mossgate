import SpriteKit
import UIKit

/// The main game scene. Mirrors the canvas engine in `engine.ts`:
/// - Custom AABB physics (one-way platforms, movers, coyote time, jump buffer).
/// - Touch state + keyboard support (for hardware keyboards in landscape).
/// - Camera follows the player with the same look-ahead rule.
/// - HUD updates flow back to SwiftUI through the `onPhaseChange` callback.
final class MossgateScene: SKScene {

    // ── Game state ────────────────────────────────────────────────
    private(set) var level: Level = Levels.all[0]
    private(set) var levelIndex: Int = 0
    private var state: GameState = .title

    // Player
    private var playerX: CGFloat = 0
    private var playerY: CGFloat = 0
    private var playerVx: CGFloat = 0
    private var playerVy: CGFloat = 0
    private var facing: CGFloat = 1
    private var grounded: Bool = false
    private var groundKind: String = "none"
    private var ride: Int = -1
    private var coyote: CGFloat = 0
    private var extraJumps: Int = 1
    private var buffer: CGFloat = 0
    private var canCut: Bool = false
    private var dropTimer: CGFloat = 0
    private var grace: CGFloat = 0
    private var jumpAge: CGFloat = 1
    private var squash: CGFloat = 0

    // Movers (computed each frame)
    private var moverPositions: [CGPoint] = []
    private var moverPrev: [CGPoint] = []
    private var time: CGFloat = 0

    // Progress
    private var coinsGot: Set<Int> = []
    private var cp: Int = -1
    private var spawnPoint: CGPoint = .zero
    private var checkpointSnap: (point: CGPoint, coins: [Int], cp: Int)?

    // Touch state
    private var touchLeft = false
    private var touchRight = false
    private var touchJump = false
    private var touchDown = false
    private var touchDrop = false
    private var prevJump = false

    // Camera
    private var camX: CGFloat = 0
    private var camY: CGFloat = 0
    private var trauma: CGFloat = 0

    // Hint system
    private var hint: String = ""
    private var sawRun = false
    private var sawDouble = false
    private var sawRide = false

    // Visual nodes
    private var worldNode = SKNode()
    private var hudNode = SKNode()
    private var playerNode: SKSpriteNode!
    private var coinNodes: [SKSpriteNode] = []
    private var spikeNodes: [SKSpriteNode] = []
    private var solidNodes: [SKSpriteNode] = []
    private var moverNodes: [SKSpriteNode] = []
    private var checkpointNodes: [SKSpriteNode] = []
    private var flagNode: SKSpriteNode!
    private var particleLayer = SKNode()

    // Camera + scaling
    private let cameraNode = SKCameraNode()
    private var viewScale: CGFloat = 1.0  // world units per point

    // Texture cache
    private var idleFrames: [SKTexture] = []
    private var runFrames: [SKTexture] = []
    private var jumpFrames: [SKTexture] = []
    private var coinFrames: [SKTexture] = []
    private var flagFrames: [SKTexture] = []
    private var spikeTexture: SKTexture!
    private var checkpointTexture: SKTexture!
    private var blockTexture: SKTexture!
    private var ledgeTexture: SKTexture!

    // Callbacks to SwiftUI
    var onPhaseChange: ((GameState, HudInfo) -> Void)?
    var onCoinsChange: ((Int) -> Void)?

    struct HudInfo {
        let phase: GameState
        let levelName: String
        let coins: Int
        let total: Int
        let cleared: Bool
        let jumps: Int
    }

    // ── Lifecycle ─────────────────────────────────────────────────

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(named: "MossgateDusk") ?? UIColor(red: 12/255, green: 28/255, blue: 31/255, alpha: 1)
        view.ignoresSiblingOrder = true
        scaleMode = .resizeFill
        camera = cameraNode
        // addChild is idempotent — re-attach safely if SwiftUI re-presents this scene.
        if cameraNode.parent !== self { addChild(cameraNode) }
        if worldNode.parent !== self { addChild(worldNode) }
        if particleLayer.parent !== self { addChild(particleLayer) }

        loadTextures()
        addChild(hudNode)
        loadLevel(index: 0, toState: .title)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        recomputeViewScale()
        positionCamera(immediately: true)
    }

    // The world is wider than tall — scale so the camera shows ~720 wide.
    private func recomputeViewScale() {
        guard size.width > 0 else { return }
        let worldWidth: CGFloat = 720
        viewScale = size.width / worldWidth
    }

    // ── Texture loading ───────────────────────────────────────────

    private func loadTextures() {
        idleFrames = (1...4).map { SKTexture(imageNamed: "idle-\($0)") }
        runFrames = (1...4).map { SKTexture(imageNamed: "run-\($0)") }
        jumpFrames = (1...4).map { SKTexture(imageNamed: "jump-\($0)") }
        coinFrames = (1...4).map { SKTexture(imageNamed: "coin-\($0)") }
        flagFrames = (1...4).map { SKTexture(imageNamed: "flag-\($0)") }
        spikeTexture = SKTexture(imageNamed: "spike")
        checkpointTexture = SKTexture(imageNamed: "checkpoint")
        blockTexture = SKTexture(imageNamed: "block")
        ledgeTexture = SKTexture(imageNamed: "ledge")

        for t in idleFrames + runFrames + jumpFrames + coinFrames + flagFrames {
            t.filteringMode = .nearest
        }
        spikeTexture.filteringMode = .nearest
        checkpointTexture.filteringMode = .nearest
        blockTexture.filteringMode = .nearest
        ledgeTexture.filteringMode = .nearest
    }

    // ── Level setup ───────────────────────────────────────────────

    func startLevel(_ index: Int) {
        AudioEngine.shared.unlock()
        loadLevel(index: index, toState: .play)
    }

    func retryLevel() { loadLevel(index: levelIndex, toState: .play) }
    func respawnAtCheckpoint() {
        guard let snap = checkpointSnap else { retryLevel(); return }
        coinsGot = Set(snap.coins)
        cp = snap.cp
        placePlayer(at: snap.point)
        setState(.play)
    }
    func pause() { if state == .play { setState(.pause) } }
    func resume() { if state == .pause {
        prevJump = touchJump
        setState(.play)
    } }
    func toTitle() { loadLevel(index: levelIndex, toState: .title) }
    func toLevelSelect() {
        setState(.levelSelect)
        notifyPhase()
    }
    func nextLevel() {
        let next = levelIndex + 1
        if next < Levels.all.count {
            loadLevel(index: next, toState: .play)
        } else {
            toTitle()
        }
    }

    func setTouch(left: Bool? = nil, right: Bool? = nil, jump: Bool? = nil, down: Bool? = nil, drop: Bool? = nil) {
        if let v = left { touchLeft = v }
        if let v = right { touchRight = v }
        if let v = jump { touchJump = v }
        if let v = down { touchDown = v }
        if let v = drop { if v { touchDrop = true } }
    }

    private func loadLevel(index: Int, toState: GameState) {
        levelIndex = index
        level = Levels.all[index]
        worldNode.removeAllChildren()
        coinsGot = []
        cp = -1
        checkpointSnap = nil
        time = 0
        moverPositions = level.movers.map { CGPoint(x: $0.x, y: $0.y) }
        moverPrev = moverPositions

        // Solids
        for s in level.solids {
            let tex = s.oneway ? ledgeTexture : blockTexture
            let node = SKSpriteNode(texture: tex, color: .white, size: CGSize(width: s.w, height: s.h))
            node.position = CGPoint(x: s.x + s.w/2, y: s.y + s.h/2)
            node.colorBlendFactor = 0
            worldNode.addChild(node)
            solidNodes.append(node)
        }

        // Movers
        for m in level.movers {
            let node = SKSpriteNode(texture: ledgeTexture, color: .white,
                                    size: CGSize(width: m.w, height: m.h))
            node.position = CGPoint(x: m.x + m.w/2, y: m.y + m.h/2)
            worldNode.addChild(node)
            moverNodes.append(node)
        }

        // Spikes
        for sp in level.spikes {
            let node = SKSpriteNode(texture: spikeTexture, color: .white,
                                    size: CGSize(width: sp.w, height: sp.h))
            node.position = CGPoint(x: sp.x + sp.w/2, y: sp.y + sp.h/2)
            worldNode.addChild(node)
            spikeNodes.append(node)
        }

        // Checkpoints
        for c in level.checkpoints {
            let node = SKSpriteNode(texture: checkpointTexture, color: .white,
                                    size: CGSize(width: 48, height: 72))
            node.position = CGPoint(x: c.x, y: c.y - 36)
            worldNode.addChild(node)
            checkpointNodes.append(node)
        }

        // Flag
        flagNode = SKSpriteNode(texture: flagFrames.first, color: .white,
                                size: CGSize(width: 42, height: 92))
        flagNode.position = CGPoint(x: level.flag.x, y: level.flag.y)
        worldNode.addChild(flagNode)

        // Coins
        coinNodes = []
        for c in level.coins {
            let node = SKSpriteNode(texture: coinFrames.first, color: .white,
                                    size: CGSize(width: 26, height: 26))
            node.position = CGPoint(x: c.x, y: c.y)
            node.alpha = 1
            worldNode.addChild(node)
            coinNodes.append(node)
        }

        // Player
        let pSize = CGSize(width: Phys.playerW * 1.6, height: Phys.playerH * 1.6)
        playerNode = SKSpriteNode(texture: idleFrames.first, color: .white, size: pSize)
        worldNode.addChild(playerNode)
        placePlayer(at: level.spawn)

        camX = clamp(level.spawn.x - 180, 0, max(0, level.width - 720))
        camY = clamp(level.spawn.y - 280, 0, max(0, level.height - 360))
        setState(toState)
        notifyPhase()
    }

    private func setState(_ s: GameState) { state = s }

    private func placePlayer(at p: CGPoint) {
        playerX = p.x - Phys.playerW / 2
        playerY = p.y - Phys.playerH
        playerVx = 0; playerVy = 0
        grounded = true
        groundKind = "solid"
        ride = -1
        coyote = Phys.coyote
        extraJumps = 1
        canCut = false
        jumpAge = 1
        grace = 0.25
        facing = 1
    }

    // ── Update loop ───────────────────────────────────────────────

    private var lastTime: TimeInterval = 0

    override func update(_ currentTime: TimeInterval) {
        let dt: CGFloat = lastTime == 0 ? 1/60 : CGFloat(min(0.05, currentTime - lastTime))
        lastTime = currentTime

        switch state {
        case .play:
            for _ in 0..<3 { step(dt / 3) }   // fixed-substep like the engine
        default:
            time += dt
        }
        placeMovers()
        positionCamera(immediately: false, dt: dt)
        render()
    }

    // ── Physics step (port of engine.ts `step`) ──────────────────

    private func step(_ dt: CGFloat) {
        time += dt
        grace = max(0, grace - dt)
        dropTimer = max(0, dropTimer - dt)
        buffer = max(0, buffer - dt)
        jumpAge += dt

        let jumpDown = touchJump
        if jumpDown && !prevJump { buffer = Phys.buffer }
        let released = prevJump && !jumpDown
        prevJump = jumpDown

        if released && playerVy < 0 && canCut {
            playerVy *= 0.48
            canCut = false
        }

        tryDrop()
        tryJump()

        // Ride mover
        if ride >= 0 && grounded {
            if let pos = moverPositions[safe: ride], let prev = moverPrev[safe: ride] {
                playerX += pos.x - prev.x
                playerY = pos.y - Phys.playerH
                playerVy = 0
            }
        }

        let prevBottom = playerY + Phys.playerH
        let dir = moveXDirection()
        if dir < 0 { facing = -1 } else if dir > 0 { facing = 1 }
        let accel = grounded ? Phys.accelG : Phys.accelA
        playerVx = approach(playerVx, dir * Phys.run, accel * dt)
        if dir == 0 && grounded { playerVx = approach(playerVx, 0, Phys.friction * dt) }

        playerX += playerVx * dt
        for s in level.solids where !s.oneway {
            if overlaps(playerRect, CGRect(x: s.x, y: s.y, width: s.w, height: s.h)) {
                if playerVx > 0 { playerX = s.x - Phys.playerW }
                else if playerVx < 0 { playerX = s.x + s.w }
                else if playerX + Phys.playerW/2 < s.x + s.w/2 { playerX = s.x - Phys.playerW }
                else { playerX = s.x + s.w }
                playerVx = 0
            }
        }

        var g: CGFloat = playerVy < 0 ? Phys.gRise : Phys.gFall
        if abs(playerVy) < Phys.apex { g = Phys.gApex }
        playerVy = min(Phys.maxFall, playerVy + g * dt)
        playerY += playerVy * dt

        grounded = false
        groundKind = "none"
        ride = -1

        // Solid landings
        for s in level.solids where !s.oneway {
            if !overlaps(playerRect, CGRect(x: s.x, y: s.y, width: s.w, height: s.h)) { continue }
            if playerVy >= 0 && prevBottom <= s.y + 4 {
                playerY = s.y - Phys.playerH
                playerVy = 0
                grounded = true; groundKind = "solid"
            } else if playerVy < 0 && playerY < s.y + s.h {
                playerY = s.y + s.h
                playerVy = 0
            }
        }

        // Oneway / mover landings
        if dropTimer <= 0 && playerVy >= 0 {
            for s in level.solids where s.oneway {
                let r = CGRect(x: s.x, y: s.y, width: s.w, height: s.h)
                if prevBottom > r.minY + 6 { continue }
                if !overlaps(playerRect, r) { continue }
                playerY = r.minY - Phys.playerH
                playerVy = 0
                grounded = true; groundKind = "oneway"
            }
            for (i, m) in level.movers.enumerated() {
                let mp = moverPositions[i]
                let r = CGRect(x: mp.x, y: mp.y, width: m.w, height: m.h)
                if prevBottom > r.minY + 6 { continue }
                if !overlaps(playerRect, r) { continue }
                playerY = r.minY - Phys.playerH
                playerVy = 0
                grounded = true; groundKind = "mover"
                ride = i
            }
        }

        if grounded { coyote = Phys.coyote; extraJumps = 1 } else { coyote = max(0, coyote - dt) }

        // Land effects
        if grounded && playerVy == 0 {
            // first-frame landing: skip for simplicity
        }

        tryJump() // retry after re-grounding

        // Spikes & kill plane
        if grace <= 0 {
            let body = CGRect(x: playerX + 3, y: playerY + 4, width: Phys.playerW - 6, height: Phys.playerH - 6)
            for sp in level.spikes where overlaps(body, CGRect(x: sp.x, y: sp.y, width: sp.w, height: sp.h)) {
                die(); return
            }
            if playerY > level.killY { die(); return }
        }

        // Coins
        let feetX = playerX + Phys.playerW / 2
        let midY = playerY + Phys.playerH * 0.45
        for (i, c) in level.coins.enumerated() where !coinsGot.contains(i) {
            if hypot(feetX - c.x, midY - c.y) < 40 {
                coinsGot.insert(i)
                AudioEngine.shared.coin()
                burst(at: CGPoint(x: c.x, y: c.y), count: 8, color: UIColor(red: 240/255, green: 160/255, blue: 64/255, alpha: 1), speed: 70)
            }
        }

        // Checkpoints
        for (i, c) in level.checkpoints.enumerated() where i > cp {
            let r = CGRect(x: c.x - 24, y: c.y - 72, width: 48, height: 72)
            if overlaps(playerRect, r) {
                cp = i
                checkpointSnap = (CGPoint(x: c.x, y: c.y), Array(coinsGot), cp)
                AudioEngine.shared.checkpoint()
                burst(at: CGPoint(x: c.x, y: c.y - 48), count: 12,
                      color: UIColor(red: 240/255, green: 160/255, blue: 64/255, alpha: 1), speed: 80)
            }
        }

        // Flag
        let flag = CGRect(x: level.flag.x - 18, y: level.flag.y - 84, width: 42, height: 84)
        if overlaps(playerRect, flag) { win() }

        hint = computeHint()
    }

    private var playerRect: CGRect {
        CGRect(x: playerX, y: playerY, width: Phys.playerW, height: Phys.playerH)
    }

    private func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && a.maxX > b.minX && a.minY < b.maxY && a.maxY > b.minY
    }

    private func approach(_ v: CGFloat, _ target: CGFloat, _ delta: CGFloat) -> CGFloat {
        if v < target { return min(target, v + delta) }
        if v > target { return max(target, v - delta) }
        return target
    }

    private func moveXDirection() -> CGFloat {
        var x: CGFloat = 0
        if touchLeft { x -= 1 }
        if touchRight { x += 1 }
        return max(-1, min(1, x))
    }

    private func tryDrop() {
        guard touchDrop else { return }
        touchDrop = false
        if grounded && (groundKind == "oneway" || groundKind == "mover") {
            dropTimer = 0.18
            grounded = false
            groundKind = "none"
            ride = -1
            coyote = 0
            playerY += 4
            buffer = 0
        }
    }

    private func tryJump() {
        if buffer <= 0 { return }
        if touchDown {
            if grounded && (groundKind == "oneway" || groundKind == "mover") {
                dropTimer = 0.18
                grounded = false; groundKind = "none"; ride = -1; coyote = 0
                playerY += 4; buffer = 0
                return
            }
        }
        if coyote > 0 {
            doJump(power: Phys.jumpV, double: false)
            extraJumps = 1
            buffer = 0
            return
        }
        if !grounded && extraJumps > 0 {
            doJump(power: Phys.dJumpV, double: true)
            extraJumps = 0
            buffer = 0
            return
        }
    }

    private func doJump(power: CGFloat, double: Bool) {
        playerVy = -power
        grounded = false
        groundKind = "none"
        ride = -1
        canCut = true
        jumpAge = 0
        coyote = 0
        AudioEngine.shared.jump(double)
        burst(at: CGPoint(x: playerX + Phys.playerW/2, y: playerY + Phys.playerH),
              count: double ? 10 : 6,
              color: double ? UIColor(red: 244/255, green: 234/255, blue: 212/255, alpha: 1)
                            : UIColor(red: 240/255, green: 160/255, blue: 64/255, alpha: 1),
              speed: double ? 90 : 60)
        trauma = min(1, trauma + (double ? 0.18 : 0.10))
        if double { sawDouble = true }
    }

    private func die() {
        AudioEngine.shared.die()
        burst(at: CGPoint(x: playerX + Phys.playerW/2, y: playerY + Phys.playerH/2),
              count: 18, color: UIColor(red: 240/255, green: 160/255, blue: 64/255, alpha: 1), speed: 140)
        setState(.dead)
        notifyPhase()
    }

    private func win() {
        AudioEngine.shared.win()
        burst(at: CGPoint(x: level.flag.x, y: level.flag.y - 40),
              count: 22, color: UIColor(red: 240/255, green: 160/255, blue: 64/255, alpha: 1), speed: 120)
        SettingsStore.shared.markCleared(level: levelIndex, coins: coinsGot.count)
        Achievements.levelCleared(level)
        setState(.win)
        notifyPhase()
    }

    private func placeMovers() {
        moverPrev = moverPositions
        for (i, m) in level.movers.enumerated() {
            let s = sin((time / m.period) * 2 * .pi + m.phase)
            if m.axis == "x" {
                let px = m.x + s * m.distance + m.w/2
                moverPositions[i] = CGPoint(x: px, y: m.y + m.h/2)
            } else {
                let py = m.y + s * m.distance + m.h/2
                moverPositions[i] = CGPoint(x: m.x + m.w/2, y: py)
            }
            moverNodes[i].position = moverPositions[i]
        }
    }

    private func computeHint() -> String {
        if state != .play { return "" }
        if !sawRun {
            if abs(playerVx) > 40 { sawRun = true }
            else if levelIndex == 0 { return "Hold right" }
        }
        if levelIndex == 0 && !sawRide {
            if ride >= 0 { sawRide = true }
            else if playerX > 500 && playerX < 820 { return "Step onto the stone" }
        }
        if !sawDouble && !grounded && extraJumps > 0 && jumpAge > 0.12 { return "Jump again" }
        return ""
    }

    // ── Camera ────────────────────────────────────────────────────

    private func positionCamera(immediately: Bool, dt: CGFloat = 1/60) {
        let focusX = playerX + Phys.playerW/2 + facing * 36
        let focusY = playerY + Phys.playerH * 0.42
        let left = 720 * (facing >= 0 ? 0.36 : 0.36)
        let right = 720 * (facing >= 0 ? 0.56 : 0.56)
        let top = 360 * 0.38
        let bottom = 360 * 0.66
        var desiredX = camX
        var desiredY = camY
        let sx = focusX - camX
        let sy = focusY - camY
        if sx < left { desiredX = focusX - left } else if sx > right { desiredX = focusX - right }
        if sy < top { desiredY = focusY - top } else if sy > bottom { desiredY = focusY - bottom }
        let k = immediately ? 1.0 : (1 - exp(-7 * dt))
        camX += (desiredX - camX) * k
        camY += (desiredY - camY) * k
        camX = max(0, min(camX, max(0, level.width - 720)))
        camY = max(0, min(camY, max(0, level.height - 360)))

        trauma = max(0, trauma - dt * 1.5)
        let shake = trauma * trauma
        let shakeX = (sin(time * 47) * 0.5 + sin(time * 23) * 0.5) * 10 * shake
        let shakeY = (cos(time * 41) * 0.5 + sin(time * 19) * 0.5) * 7 * shake

        cameraNode.position = CGPoint(x: camX + 360 + shakeX, y: camY + 180 + shakeY)
    }

    // ── Render ────────────────────────────────────────────────────

    private func render() {
        // Player
        let frames = (!grounded && !jumpFrames.isEmpty) ? jumpFrames
                    : (abs(playerVx) > 28 && grounded && !runFrames.isEmpty) ? runFrames
                    : idleFrames
        if !frames.isEmpty {
            let idx: Int
            if !grounded && frames.count == 4 {
                idx = jumpAge < 0.07 ? 0 : (playerVy < -120 ? 1 : (playerVy < 150 ? 2 : 3))
            } else {
                idx = Int(time * 10) % frames.count
            }
            playerNode.texture = frames[idx]
        }
        playerNode.position = CGPoint(x: playerX + Phys.playerW/2, y: playerY + Phys.playerH/2)
        playerNode.xScale = facing
        playerNode.yScale = 1

        // Coin spin & bob
        for (i, node) in coinNodes.enumerated() where !coinsGot.contains(i) {
            let frame = Int(time * 8) % coinFrames.count
            node.texture = coinFrames[frame]
            let bob = sin(time * 3.2 + CGFloat(i)) * 3
            node.position.y = level.coins[i].y + bob
            node.isHidden = false
        }
        for (i, node) in coinNodes.enumerated() where coinsGot.contains(i) {
            node.isHidden = true
        }

        // Flag
        if !flagFrames.isEmpty {
            let idx = Int(time * 6) % flagFrames.count
            flagNode.texture = flagFrames[idx]
        }

        // Checkpoints glow
        for (i, node) in checkpointNodes.enumerated() {
            let lit = i <= cp
            node.color = lit ? .white : .gray
            node.colorBlendFactor = lit ? 0 : 0.6
        }
    }

    // ── Particles ─────────────────────────────────────────────────

    private func burst(at p: CGPoint, count: Int, color: UIColor, speed: CGFloat) {
        for _ in 0..<count {
            let a = CGFloat.random(in: 0...(2 * .pi))
            let s = speed * CGFloat.random(in: 0.35...1.35)
            let node = SKShapeNode(rectOf: CGSize(width: 2, height: 2))
            node.fillColor = color
            node.strokeColor = .clear
            node.position = p
            node.alpha = 1
            let dur: TimeInterval = 0.5
            let dx = cos(a) * s * CGFloat(dur)
            let dy = sin(a) * s * CGFloat(dur)
            node.run(.group([
                .sequence([
                    .moveBy(x: dx, y: dy, duration: dur),
                    .removeFromParent(),
                ]),
                .fadeOut(withDuration: dur),
            ]))
            particleLayer.addChild(node)
        }
    }

    private func notifyPhase() {
        let jumps = (grounded || coyote > 0) ? 2 : (extraJumps > 0 ? 1 : 0)
        let info = HudInfo(
            phase: state,
            levelName: level.name,
            coins: coinsGot.count,
            total: level.coins.count,
            cleared: SettingsStore.shared.cleared.indices.contains(levelIndex) ? SettingsStore.shared.cleared[levelIndex] : false,
            jumps: jumps
        )
        onPhaseChange?(state, info)
        onCoinsChange?(coinsGot.count)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
/// Mirror of the canvas engine's `clamp(v, a, b)` helper.
@inline(__always)
func clamp<T: Comparable>(_ v: T, _ a: T, _ b: T) -> T {
    return Swift.max(a, Swift.min(b, v))
}
