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
    /// Fixed physics timestep and its accumulator — matches engine.ts
    /// (STEP_DT = 1/120, guard at 8 substeps per frame).
    static let stepDt: CGFloat = 1.0 / 120.0
    private var acc: CGFloat = 0

    // Progress
    private var coinsGot: Set<Int> = []
    private var lanternsGot: Set<Int> = []
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
    /// Extra downward camera offset while DOWN is held on solid ground.
    private var peekY: CGFloat = 0

    /// `-PlaceAt x,y` test rig: where to put the player after every level load.
    ///
    /// Applied inside `loadLevel` rather than once at startup, because the
    /// hosting view can call `startLevel` again on a layout pass and would
    /// otherwise put the player straight back at the spawn.
    private let placeAtOverride: CGPoint? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-PlaceAt"), i + 1 < args.count else { return nil }
        let parts = args[i + 1].split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGPoint(x: parts[0], y: parts[1])
    }()
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
    private var lanternNodes: [SKSpriteNode] = []
    private var spikeNodes: [SKSpriteNode] = []
    private var solidNodes: [SKSpriteNode] = []
    private var moverNodes: [SKSpriteNode] = []
    private var checkpointNodes: [SKSpriteNode] = []
    private var flagNode: SKSpriteNode!
    private var particleLayer = SKNode()

    // Camera + scaling
    private let cameraNode = SKCameraNode()
    private var viewScale: CGFloat = 1.0  // scene points per world unit (= scene.width / 720)

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
    private var skyTexture: SKTexture?
    private var moonTexture: SKTexture?
    /// Sky textures keyed by "<world>-<height>", so switching levels doesn't
    /// rebuild the same gradient image.
    private var skyCache: [String: SKTexture] = [:]
    private var lanternTexture: SKTexture?

    // Callbacks to SwiftUI
    var onPhaseChange: ((GameState, HudInfo) -> Void)?
    var onCoinsChange: ((Int) -> Void)?

    /// True once loadLevel has completed at least once. Render() bails out before this
    /// is set, avoiding crashes during view transitions where arrays are briefly inconsistent.
    private var isLoaded = false

    private func debugWrite(_ s: String) {
        let path = NSTemporaryDirectory() + "mossgate-debug.log"
        let payload = s + "\n"
        if let data = payload.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        debugWrite("=== init(coder) ===")
    }

    override init(size: CGSize) {
        super.init(size: size)
        debugWrite("=== init(size:\(size)) ===\nself=\(Unmanaged.passUnretained(self).toOpaque())")
    }

    struct HudInfo {
        let phase: GameState
        let levelName: String
        let coins: Int
        let total: Int
        let cleared: Bool
        let jumps: Int
        /// Lanterns collected this level / total in the level.
        let lanterns: Int
        let lanternsTotal: Int
        /// Remaining light (lives) and the cap.
        let lives: Int
        let maxLives: Int
    }

    // ── Lifecycle ─────────────────────────────────────────────────

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(named: "MossgateDusk") ?? UIColor(red: 12/255, green: 28/255, blue: 31/255, alpha: 1)
        view.ignoresSiblingOrder = true
        scaleMode = .resizeFill
        // Top-left origin so scene (0, 0) is the top-left corner of the buffer
        // (matches canvas convention used in the original HTML/JS engine).
        // Default `anchorPoint = (0, 0)` would put origin at the BOTTOM-LEFT,
        // flipping the y axis and putting everything above y=360 off-screen.
        anchorPoint = CGPoint(x: 0, y: 1)
        // No SKCameraNode — the worldNode translation IS the camera.
        camera = nil
        // Flip the worldNode vertically so the world's y axis matches the
        // top-down canvas convention used in the original HTML/JS engine.
        // With yScale = -1, a node at world (x, y) appears at scene (x*scale, -y*scale).
        // Combined with anchorPoint (0, 1) at view top-left, world y=0 ends up
        // at the top of the view, and y grows downward as expected.
        worldNode.yScale = -1
        // addChild is idempotent — re-attach safely if SwiftUI re-presents this scene.
        if worldNode.parent !== self { addChild(worldNode) }
        if particleLayer.parent !== self { addChild(particleLayer) }

        loadTextures()
        addChild(hudNode)
        recomputeViewScale()
        // DEBUG: write state to file so we can read it back from the simulator
        let debugPath = NSTemporaryDirectory() + "mossgate-debug.log"
        let info = """
        === didMove ===
        sceneSize: \(size)
        viewScale: \(viewScale)
        camY: \(camY)
        worldNode.parent: \(String(describing: worldNode.parent))
        worldNode.position: \(worldNode.position)
        children of self: \(children.count)
        children of worldNode: \(worldNode.children.count)
        """
        try? info.write(toFile: debugPath, atomically: true, encoding: .utf8)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        recomputeViewScale()
        // Re-place at current scale so sprites snap to new positions on rotation.
        if isLoaded { loadLevel(index: levelIndex, toState: state) }
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

        // Moon + lantern pickup art. The sky is generated per level (it depends
        // on the level height, so it can't be cached across levels).
        moonTexture = makeMoonTexture()
        lanternTexture = makeLanternTexture()
    }

    // MARK: - Procedural lantern pickup

    /// A small lit lantern you can pick up. The wick glows with the same warm
    /// amber as the player's lantern so the player feels like they're
    /// "gathering light" for the journey ahead.
    private func makeLanternTexture() -> SKTexture {
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
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
        let tex = SKTexture(image: image)
        tex.filteringMode = .linear
        return tex
    }

    // MARK: - Procedural sky

    /// Builds the sky texture for one level: a vertical gradient plus scattered
    /// stars, generated at `512 x height` so a single tile spans the level's
    /// full height and the gradient never visibly repeats.
    /// `ember = true` shifts the palette to the warm lava world look.
    private func makeSkyTexture(seed: UInt64, ember: Bool = false, height: CGFloat = 760) -> SKTexture {
        let size = CGSize(width: 512, height: max(256, height))
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let top, mid1, mid2, bottom: UIColor
            if ember {
                // Ember Caves: warm, smoky, lava-glow near the horizon.
                top    = UIColor(red: 0.07, green: 0.04, blue: 0.04, alpha: 1)
                mid1   = UIColor(red: 0.22, green: 0.08, blue: 0.04, alpha: 1)
                mid2   = UIColor(red: 0.34, green: 0.14, blue: 0.05, alpha: 1)
                bottom = UIColor(red: 0.10, green: 0.05, blue: 0.03, alpha: 1)
            } else {
                // Mossgate Dusk: deep teal night sky, amber-lit green low down.
                top    = UIColor(red: 0.020, green: 0.058, blue: 0.086, alpha: 1)
                mid1   = UIColor(red: 0.043, green: 0.118, blue: 0.165, alpha: 1)
                mid2   = UIColor(red: 0.075, green: 0.180, blue: 0.176, alpha: 1)
                bottom = UIColor(red: 0.055, green: 0.098, blue: 0.094, alpha: 1)
            }
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [top.cgColor, mid1.cgColor, mid2.cgColor, bottom.cgColor] as CFArray
            let stops: [CGFloat] = [0, 0.40, 0.78, 1.0]
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: stops)!
            cg.drawLinearGradient(gradient,
                                  start: CGPoint(x: 0, y: 0),
                                  end:   CGPoint(x: 0, y: size.height),
                                  options: [])

            // Stars / embers — deterministic per seed so the same level always
            // shows the same pattern. Density scales with the canvas height.
            var rng = SplitMix64(state: seed)
            let count = Int(size.height / 6)
            for _ in 0..<count {
                let x = CGFloat(rng.next() % UInt64(size.width))
                let y = CGFloat(rng.next() % UInt64(size.height * 3 / 4)) // upper sky
                let r = ember
                    ? CGFloat(rng.next() % 3) + 1.0
                    : CGFloat(rng.next() % 3) + 0.8
                let a = ember
                    ? CGFloat(0.40 + Double(rng.next() % 40) / 100.0)
                    : CGFloat(0.45 + Double(rng.next() % 45) / 100.0)
                let color: UIColor = ember
                    ? UIColor(red: 1.0, green: 0.62, blue: 0.28, alpha: a)
                    : UIColor(red: 1.0, green: 0.96, blue: 0.82, alpha: a)
                color.setFill()
                cg.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .linear
        return tex
    }

    /// Builds a soft, glowing moon as a circular radial-gradient sprite.
    private func makeMoonTexture() -> SKTexture {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let inner = UIColor(red: 1.00, green: 0.95, blue: 0.78, alpha: 1.0).cgColor
            let mid   = UIColor(red: 0.95, green: 0.78, blue: 0.40, alpha: 0.55).cgColor
            let outer = UIColor(red: 0.95, green: 0.78, blue: 0.40, alpha: 0.0).cgColor
            let colors = [inner, mid, outer] as CFArray
            let stops: [CGFloat] = [0, 0.4, 1.0]
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: stops)!
            cg.drawRadialGradient(gradient,
                                  startCenter: CGPoint(x: size.width/2, y: size.height/2),
                                  startRadius: 0,
                                  endCenter:   CGPoint(x: size.width/2, y: size.height/2),
                                  endRadius:   size.width/2,
                                  options: [])

            // Crescent shadow to make it look like a real moon
            cg.setBlendMode(.clear)
            cg.fillEllipse(in: CGRect(x: size.width * 0.55, y: size.height * 0.18,
                                      width: size.width * 0.55, height: size.height * 0.55))
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .linear
        return tex
    }

    /// Build and add the sky to the worldNode (scrolls with the camera).
    /// `worldId == 0` is Mossgate Dusk (teal), `1` is Ember Caves (warm).
    ///
    /// The gradient is generated at the level's full height so a single row of
    /// columns covers the sky with no vertically repeating bands; only the
    /// horizontal direction needs tiling.
    private func addSky() {
        let isEmber = (level.world == 1)

        // Cache one sky per (world, height) — levels in the same world usually
        // share a height, so this avoids regenerating the image every load.
        let key = "\(level.world)-\(Int(level.height))"
        if let cached = skyCache[key] {
            skyTexture = cached
        } else {
            let tex = makeSkyTexture(seed: isEmber ? 0x45_6D_62 : 0x4D_6F_73,
                                     ember: isEmber,
                                     height: level.height)
            skyCache[key] = tex
            skyTexture = tex
        }
        guard let bgTex = skyTexture else { return }

        // One row: each column spans the whole level height.
        let tileWorldW: CGFloat = 512
        let cols = Int(ceil(level.width / tileWorldW)) + 1
        let skyH = level.height * viewScale
        let skyCenterY = (level.height / 2) * viewScale

        for col in 0..<cols {
            let tile = SKSpriteNode(texture: bgTex)
            tile.size = CGSize(width: tileWorldW * viewScale, height: skyH)
            tile.position = CGPoint(x: (CGFloat(col) * tileWorldW + tileWorldW/2) * viewScale,
                                    y: skyCenterY)
            tile.zPosition = -1000          // behind every other world child
            addWorldChild(tile)
        }

        // Moon — only in Mossgate Dusk. Placed where the opening camera actually
        // looks (below the top of the view, above the ground line), so it's on
        // screen at the start of a level rather than stranded out of frame.
        if !isEmber, let moon = moonTexture {
            let moonNode = SKSpriteNode(texture: moon)
            moonNode.size = CGSize(width: 120 * viewScale, height: 120 * viewScale)
            let moonWorldY = max(110, level.height * 0.44)
            moonNode.position = CGPoint(x: 320 * viewScale, y: moonWorldY * viewScale)
            moonNode.zPosition = -900
            moonNode.blendMode = .add   // warm glow against the teal sky
            addWorldChild(moonNode)
        }
    }

    // MARK: - World hierarchy helper

    /// Adds a node to the world, counter-flipping SKSpriteNodes vertically.
    ///
    /// `worldNode` carries `yScale = -1` so the engine's y-down world maps onto
    /// SpriteKit's y-up scene coordinates. That flip also mirrors every sprite
    /// image, so each sprite gets an equal and opposite `yScale = -1` (net +1 →
    /// upright) while its *position* still benefits from the world mapping.
    /// SKShapeNodes (particles) are symmetric squares and need no flip.
    @discardableResult
    private func addWorldChild(_ node: SKNode) -> SKNode {
        if let sprite = node as? SKSpriteNode {
            sprite.yScale = -1
        }
        worldNode.addChild(node)
        return node
    }

    // ── Level setup ───────────────────────────────────────────────

    func startLevel(_ index: Int) {
        loadLevel(index: index, toState: .play)
        runMoverTestIfRequested()
        runDeathTestHookIfRequested()
        runDownTestHookIfRequested()
        runDropTestHookIfRequested()
        runSfxTestHookIfRequested()
    }

    /// Test hook: `-PlaceAt x,y` is handled by `placeAtOverride` inside
    /// `loadLevel` (see the property), so a re-entrant `startLevel` can't wipe it.

    /// Test hook: `-TestMovers 1` walks every level's movers across a full
    /// period using the same curve `placeMovers()` applies, and reports any
    /// rect that intersects the land or another mover. This validates the level
    /// data through the engine's own maths rather than a reimplementation of it.
    private func runMoverTestIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-TestMovers") else { return }
        var totalLand = 0, totalPair = 0
        for (li, lv) in Levels.all.enumerated() {
            var land = 0, pair = 0
            let steps = 600
            for s in 0...steps {
                let t = CGFloat(s) / CGFloat(steps) * 24.0     // ~16 periods of a 3.4 s mover
                let rects = lv.movers.map { m -> CGRect in
                    let k = sin((t / m.period) * 2 * .pi + m.phase)
                    return CGRect(x: m.axis == "x" ? m.x + k * m.distance : m.x,
                                  y: m.axis == "y" ? m.y + k * m.distance : m.y,
                                  width: m.w, height: m.h)
                }
                // Inset so merely touching an edge is not counted as a collision,
                // matching the margin the level data was tuned against.
                for r in rects.map({ $0.insetBy(dx: 0.5, dy: 0.5) }) {
                    for sol in lv.solids where !sol.oneway {
                        let sr = CGRect(x: sol.x, y: sol.y, width: sol.w, height: sol.h)
                                  .insetBy(dx: -0.5, dy: -0.5)
                        if r.intersects(sr) { land += 1; break }
                    }
                }
                for i in rects.indices {
                    for j in rects.indices where j > i {
                        if rects[i].insetBy(dx: 1, dy: 1).intersects(rects[j]) { pair += 1 }
                    }
                }
            }
            totalLand += land; totalPair += pair
            print("[Mossgate:MOVERS] level \(li) \"\(lv.name)\" movers=\(lv.movers.count) "
                  + "landOverlaps=\(land) moverOverlaps=\(pair)")
        }
        print("[Mossgate:MOVERS] TOTAL land=\(totalLand) moverOverlaps=\(totalPair) "
              + "(0/0 means every mover stays in its gap for its whole travel)")
    }

    /// Test hook: `-TestSfx 1` fires every sound effect in turn and logs the
    /// engine state for each, so audio can be checked without a human listening.
    private func runSfxTestHookIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-TestSfx") else { return }
        let seq: [(String, () -> Void)] = [
            ("tap",        { AudioEngine.shared.tap() }),
            ("jump",       { AudioEngine.shared.jump(false) }),
            ("doubleJump", { AudioEngine.shared.jump(true) }),
            ("coin",       { AudioEngine.shared.coin() }),
            ("checkpoint", { AudioEngine.shared.checkpoint() }),
            ("land",       { AudioEngine.shared.land() }),
            ("die",        { AudioEngine.shared.die() }),
            ("win",        { AudioEngine.shared.win() }),
        ]
        for (i, item) in seq.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(i) * 0.6) {
                print("[Mossgate:AUDIO] firing \(item.0)")
                item.1()
            }
        }
    }

    /// Test hook: `-TestDrop 1` parks the player on the level's first one-way
    /// ledge, waits for them to settle, then taps DOWN and logs whether
    /// `tryDrop()` actually fired. Lets a headless run prove the DOWN pad works
    /// without a human on the simulator.
    private func runDropTestHookIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-TestDrop"),
              let ow = level.solids.first(where: { $0.oneway }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            // Drop the player onto the ledge and let them land.
            self.playerX = ow.x + ow.w / 2 - Phys.playerW / 2
            self.playerY = ow.y - Phys.playerH - 2
            self.playerVy = 0
            self.playerVx = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let yBefore = self.playerY
                let kindBefore = self.groundKind
                let grounded = self.grounded
                self.setTouch(down: true)    // the DOWN pad press
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.setTouch(down: false)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("[Mossgate] TESTDROP onLedge=\(kindBefore) grounded=\(grounded) yBefore=\(Int(yBefore)) yAfter=\(Int(self.playerY)) kindAfter=\(self.groundKind) fell=\(Int(self.playerY - yBefore))")
                }
            }
        }
    }

    func retryLevel() { loadLevel(index: levelIndex, toState: .play) }

    /// Test hook: `-TestDown 1` measures what the DOWN pad actually changes —
    /// the fall distance in the air with and without it, and the camera pan
    /// while standing on solid ground.
    func runDownTestHookIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-TestDown") else { return }
        let window = 0.3
        func fall(diving: Bool, then: @escaping (CGFloat) -> Void) {
            playerX = level.spawn.x
            playerY = level.spawn.y - 300        // into clear air above the spawn
            playerVy = 0
            touchDown = diving
            let y0 = playerY
            DispatchQueue.main.asyncAfter(deadline: .now() + window) { [weak self] in
                guard let self else { then(0); return }
                self.touchDown = false
                then(self.playerY - y0)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            fall(diving: false) { plain in
                fall(diving: true) { dive in
                    print("[Mossgate:DOWN] air fall over \(window)s: "
                          + "\(Int(plain)) units normally, \(Int(dive)) with DOWN held")
                    // Grounded DOWN should pan the camera down. Use placePlayer,
                    // which offsets for the player's height — assigning spawn.y
                    // directly drops them *inside* the ground block and straight
                    // through it.
                    self.placePlayer(at: self.level.spawn)
                    self.playerVx = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        let before = self.camY + self.peekY
                        self.touchDown = true
                        print("[Mossgate:DOWN] settle: grounded=\(self.grounded) "
                              + "kind=\(self.groundKind) playerY=\(Int(self.playerY)) camY=\(Int(before))")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            let during = self.camY + self.peekY
                            self.touchDown = false
                            print("[Mossgate:DOWN] camera camY \(Int(before)) -> \(Int(during)) "
                                  + "with DOWN held while grounded=\(self.grounded) "
                                  + "groundKind=\(self.groundKind)")
                        }
                    }
                }
            }
        }
    }

    /// Test hook: `-TestDeath 1` kills the player repeatedly and logs the light
    /// counter and state after each death, so the lose-light → game-over flow
    /// can be checked headlessly instead of by hand.
    func runDeathTestHookIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-TestDeath") else { return }
        // Wait for the scene to actually be presented before the first kill,
        // otherwise the opening teleport lands before the view is live and the
        // level load overwrites it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.deathTestStep(0) }
    }

    private func deathTestStep(_ n: Int) {
        guard n < 5 else { return }
        let before = SettingsStore.shared.lives
        playerY = level.killY + 40          // below the kill line: dies next frame
        playerVy = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            print("[Mossgate:DEATH] death \(n + 1): lives \(before) -> \(SettingsStore.shared.lives)"
                  + "  state=\(String(describing: self.state))"
                  + "  isOutOfLight=\(SettingsStore.shared.isOutOfLight)")
            // Stop on game over so the screen stays up (and stays photographable)
            // instead of being retried away.
            if SettingsStore.shared.isOutOfLight {
                print("[Mossgate:DEATH] out of light — run over, leaving the game-over screen up")
                // Exercise the "Start over" action (refill + restart) exactly as
                // the game-over panel's primary button does.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    SettingsStore.shared.refillLives()
                    self?.retryLevel()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                        print("[Mossgate:DEATH] after Start over: lives=\(SettingsStore.shared.lives)"
                              + "  state=\(String(describing: self?.state))"
                              + "  isOutOfLight=\(SettingsStore.shared.isOutOfLight)")
                    }
                }
                return
            }
            self.retryLevel()               // stand back up for the next round
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.deathTestStep(n + 1) }
        }
    }
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
        if let v = down {
            // The DOWN pad is a one-shot "step off the ledge you are standing on"
            // in the original game: mossgate.tsx wires its pointer-down to
            // setTouch("drop", true), and engine.ts turn that into
            // `touch.drop = true` (consumed by tryDrop()). Mirror that here by
            // firing the one-shot on the rising edge, otherwise a plain tap of
            // DOWN only sets the *held* state, which is read solely inside
            // tryJump() — and that bails out unless a jump was queued.
            if v && !touchDown { touchDrop = true }
            touchDown = v
        }
        if let v = drop { if v { touchDrop = true } }
    }

    private func loadLevel(index: Int, toState: GameState) {
        levelIndex = index
        level = Levels.all[index]
        // Each world gets its own looping track.
        if toState == .play {
            AudioEngine.shared.playMusic(level.world == 1 ? .ember : .dusk)
        }
        // Clear arrays BEFORE clearing worldNode, otherwise old node refs leak
        // across multiple loadLevel calls (didMove + startLevel).
        solidNodes.removeAll(keepingCapacity: true)
        moverNodes.removeAll(keepingCapacity: true)
        spikeNodes.removeAll(keepingCapacity: true)
        checkpointNodes.removeAll(keepingCapacity: true)
        worldNode.removeAllChildren()
        coinsGot = []
        lanternsGot = []
        cp = -1
        checkpointSnap = nil

        // Sky must be added FIRST so it sits behind everything else (zPosition
        // on the tiles is -100, but order of addChild also matters).
        addSky()
        time = 0
        acc = 0
        // Match engine.ts loadLevel: seed positions, evaluate the mover curve at
        // t = 0, then zero the delta so the first substep doesn't jerk the rider.
        moverPositions = level.movers.map { CGPoint(x: $0.x, y: $0.y) }
        placeMovers()
        moverPrev = moverPositions

        // Solids
        for s in level.solids {
            let tex = s.oneway ? ledgeTexture : blockTexture
            let node = SKSpriteNode(texture: tex, color: .white,
                                    size: CGSize(width: s.w * viewScale, height: s.h * viewScale))
            node.position = CGPoint(x: (s.x + s.w/2) * viewScale,
                                    y: (s.y + s.h/2) * viewScale)
            node.colorBlendFactor = 0
            addWorldChild(node)
            solidNodes.append(node)
        }

        // Movers
        for m in level.movers {
            let node = SKSpriteNode(texture: ledgeTexture, color: .white,
                                    size: CGSize(width: m.w * viewScale, height: m.h * viewScale))
            node.position = CGPoint(x: (m.x + m.w/2) * viewScale,
                                    y: (m.y + m.h/2) * viewScale)
            addWorldChild(node)
            moverNodes.append(node)
        }

        // Spikes
        for sp in level.spikes {
            let node = SKSpriteNode(texture: spikeTexture, color: .white,
                                    size: CGSize(width: sp.w * viewScale, height: sp.h * viewScale))
            node.position = CGPoint(x: (sp.x + sp.w/2) * viewScale,
                                    y: (sp.y + sp.h/2) * viewScale)
            addWorldChild(node)
            spikeNodes.append(node)
        }

        // Checkpoints
        for c in level.checkpoints {
            let node = SKSpriteNode(texture: checkpointTexture, color: .white,
                                    size: CGSize(width: 48 * viewScale, height: 72 * viewScale))
            node.position = CGPoint(x: c.x * viewScale, y: (c.y - 36) * viewScale)
            addWorldChild(node)
            checkpointNodes.append(node)
        }

        // Flag
        flagNode = SKSpriteNode(texture: flagFrames.first, color: .white,
                                size: CGSize(width: 42 * viewScale, height: 92 * viewScale))
        flagNode.position = CGPoint(x: level.flag.x * viewScale, y: level.flag.y * viewScale)
        addWorldChild(flagNode)

        // Coins
        coinNodes = []
        for c in level.coins {
            let node = SKSpriteNode(texture: coinFrames.first, color: .white,
                                    size: CGSize(width: 26 * viewScale, height: 26 * viewScale))
            node.position = CGPoint(x: c.x * viewScale, y: c.y * viewScale)
            node.alpha = 1
            addWorldChild(node)
            coinNodes.append(node)
        }

        // Lanterns — the pickups you collect to refill your light.
        lanternNodes = []
        for l in level.lanterns {
            let node = SKSpriteNode(texture: lanternTexture, color: .white,
                                    size: CGSize(width: 34 * viewScale, height: 34 * viewScale))
            node.position = CGPoint(x: l.x * viewScale, y: l.y * viewScale)
            addWorldChild(node)
            lanternNodes.append(node)
        }

        // Player
        let pSize = CGSize(width: Phys.playerW * 1.6 * viewScale,
                           height: Phys.playerH * 1.6 * viewScale)
        playerNode = SKSpriteNode(texture: idleFrames.first, color: .white, size: pSize)
        addWorldChild(playerNode)
        // Test rig: -PlaceAt overrides the spawn (applied here, not once at
        // startup, so a re-entrant startLevel from the hosting view can't undo it).
        let start = placeAtOverride ?? level.spawn
        placePlayer(at: start)

        camX = clamp(start.x - 180, 0, max(0, level.width - 720))
        camY = clamp(start.y - 280, 0, max(0, level.height - 360))
        isLoaded = true
        // DEBUG: append loadLevel state to file
        let loadInfo = """
        === loadLevel idx=\(levelIndex) ===
        solids=\(solidNodes.count) movers=\(moverNodes.count) spikes=\(spikeNodes.count)
        coins=\(coinNodes.count) chkpts=\(checkpointNodes.count)
        flag=\(flagNode == nil ? "nil" : "ok") player=\(playerNode == nil ? "nil" : "ok")
        viewScale=\(viewScale) camY=\(camY) size=\(size)
        worldNode.parent=\(String(describing: worldNode.parent))
        worldNode.position=\(worldNode.position)
        moverPos=\(moverPositions.map { "(\(Int($0.x)),\(Int($0.y)))" }.joined(separator: " "))
        moverNodePos=\(moverNodes.map { "(\(Int($0.position.x)),\(Int($0.position.y)))" }.joined(separator: " "))
        """
        let path = NSTemporaryDirectory() + "mossgate-debug.log"
        if let data = (loadInfo + "\n").data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
        print("[Mossgate] loadLevel: solids=\(solidNodes.count) movers=\(moverNodes.count) spikes=\(spikeNodes.count) coins=\(coinNodes.count) checkpoints=\(checkpointNodes.count) flag=\(flagNode != nil) player=\(playerNode != nil) viewScale=\(viewScale) camY=\(camY) moverWorld=\(moverPositions.map { "(\(Int($0.x)),\(Int($0.y)))" }.joined(separator: " ")) moverNode=\(moverNodes.map { "(\(Int($0.position.x)),\(Int($0.position.y)))" }.joined(separator: " "))")
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
        guard isLoaded else { return }

        switch state {
        case .play:
            // Fixed-substep accumulator, matching engine.ts:
            //   acc += dt; while (acc >= STEP_DT && guard++ < 8) { step(STEP_DT); acc -= STEP_DT }
            // placeMovers() lives INSIDE step(), so mover deltas are per-substep —
            // calling it once per frame here made the ride delta apply 3x and slid
            // the player off every platform they stood on.
            acc += dt
            var guardCount = 0
            while acc >= Self.stepDt && guardCount < 8 {
                step(Self.stepDt)
                acc -= Self.stepDt
                guardCount += 1
                if state != .play { break }
            }
        default:
            time += dt
            placeMovers()
        }
        positionWorld()
        render()
    }

    // ── Physics step (port of engine.ts `step`) ──────────────────

    private func step(_ dt: CGFloat) {
        time += dt
        // placeMovers belongs here (engine.ts step() line 1). Mover positions —
        // and therefore `moverPrev` — must advance once per substep, otherwise
        // the ride delta (px - prevX) is applied several times per frame and the
        // player slides off any platform they are standing on.
        placeMovers()
        grace = max(0, grace - dt)
        dropTimer = max(0, dropTimer - dt)
        buffer = max(0, buffer - dt)
        jumpAge += dt

        // Camera follow — match the original canvas engine's look-ahead rule.
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
        let k = 1 - exp(-7 * dt)
        camX += (desiredX - camX) * k
        camY += (desiredY - camY) * k
        camX = max(0, min(camX, max(0, level.width - 720)))
        camY = max(0, min(camY, max(0, level.height - 360)))

        // DOWN while standing pans the view down. Applied as an offset on top of
        // the dead-zone follow rather than through focusY, so the pan is always
        // the same size instead of depending on where the player happens to sit
        // inside the dead zone. Gives the pad a visible job on solid ground, and
        // a way to see what waits below before dropping through a ledge.
        let peekTarget: CGFloat = (touchDown && grounded) ? Phys.lookDown : 0
        peekY += (peekTarget - peekY) * (1 - exp(-9 * dt))

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
        // DOWN held while descending = dive. Gated on `playerVy > 0` so it
        // only ever speeds the fall up; it never shortens a jump.
        let diving = touchDown && !grounded && playerVy > 0
        if diving { g *= Phys.diveGravity }
        let terminal = diving ? Phys.maxFall * Phys.diveMaxFall : Phys.maxFall
        playerVy = min(terminal, playerVy + g * dt)
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

        // Lanterns — collecting one refills a unit of light (capped at max).
        for (i, l) in level.lanterns.enumerated() where !lanternsGot.contains(i) {
            if hypot(feetX - l.x, midY - l.y) < 46 {
                lanternsGot.insert(i)
                SettingsStore.shared.gainLife()
                AudioEngine.shared.checkpoint()
                burst(at: CGPoint(x: l.x, y: l.y), count: 14,
                      color: UIColor(red: 1.0, green: 0.84, blue: 0.48, alpha: 1), speed: 95)
                notifyPhase()
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
            // Show that the pad did something: a puff of moss at the feet and a
            // soft thud, instead of silently sinking through the ledge.
            burst(at: CGPoint(x: playerX + Phys.playerW/2, y: playerY + Phys.playerH),
                  count: 8, color: UIColor(red: 0.55, green: 0.62, blue: 0.42, alpha: 1),
                  speed: 50)
            AudioEngine.shared.land()
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
        // Losing the wick costs a unit of light. Running out ends the run.
        let left = SettingsStore.shared.loseLife()
        setState(left <= 0 ? .gameOver : .dead)
        notifyPhase()
    }

    private func win() {
        AudioEngine.shared.win()
        burst(at: CGPoint(x: level.flag.x, y: level.flag.y - 40),
              count: 22, color: UIColor(red: 240/255, green: 160/255, blue: 64/255, alpha: 1), speed: 120)
        SettingsStore.shared.markCleared(level: levelIndex, coins: coinsGot.count)
        // Clearing a gate rewards a unit of light (capped at max).
        SettingsStore.shared.gainLife()
        let allCoins = coinsGot.count == level.coins.count
        let totalCoins = SettingsStore.shared.bestCoins.reduce(0, +)
        Achievements.levelCleared(level,
                                  coins: coinsGot.count,
                                  totalCoins: totalCoins,
                                  allCoinsCollected: allCoins)
        setState(.win)
        notifyPhase()
    }

    /// Advances every mover along its curve for the current `time`.
    ///
    /// Pure position maths — deliberately touches no nodes, because it is also
    /// called from `loadLevel` *before* the mover sprites are built, and from
    /// `step()` once per substep. The rider delta (`pos - prev`) therefore has
    /// exactly one frame's worth of motion per frame, no matter how many
    /// substeps run.
    private func placeMovers() {
        guard moverPositions.count == level.movers.count else { return }
        moverPrev = moverPositions   // snapshot before advancing
        for (i, m) in level.movers.enumerated() {
            let s = sin((time / m.period) * 2 * .pi + m.phase)
            // Store TOP-LEFT world coordinates, matching the engine's Rect
            // convention (`px = x + sin(...) * distance`, `py = y`). The
            // collision rect and the ride-snap use these directly; the sprite
            // centre (+w/2, +h/2) is applied only when positioning the node.
            let px = m.axis == "x" ? m.x + s * m.distance : m.x
            let py = m.axis == "y" ? m.y + s * m.distance : m.y
            moverPositions[i] = CGPoint(x: px, y: py)
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
    //
    // We don't use a SKCameraNode. Instead, each frame we translate `worldNode` by
    // (-camX * viewScale, -camY * viewScale), so the world region [camX, camX+720]
    // x [camY, camY+360] maps onto the scene buffer [0, scene.width] x [0, scene.height]
    // where viewScale = scene.width / 720.
    //
    // Camera FOLLOW logic (move camX/camY based on player position) lives in
    // `step()`. This function only applies the camera transform + screen shake.

    private func positionCamera(immediately: Bool, dt: CGFloat = 1/60) {
        _ = immediately; _ = dt
        // Kept as a thin shim; follow logic lives in step().
    }

    /// Apply camera follow smoothing + screen shake + world translation.
    private func positionWorld() {
        trauma = max(0, trauma - dtForShake * 1.5)
        let shake = trauma * trauma
        let shakeX = (sin(time * 47) * 0.5 + sin(time * 23) * 0.5) * 10 * shake
        let shakeY = (cos(time * 41) * 0.5 + sin(time * 19) * 0.5) * 7 * shake
        // With yScale = -1 on the worldNode, the y translation is inverted too.
        // A child at local (x, y) lands at scene (x*scale + tx, -y*scale + ty).
        // We want world (camX, camY) to appear at scene (0, 0) (view top-left),
        // so ty = camY * viewScale, and the y-flip makes the world y=0 land at
        // the top of the view as expected from a top-down canvas convention.
        worldNode.position = CGPoint(x: -camX * viewScale + shakeX,
                                     y: (camY + peekY) * viewScale + shakeY)
        // DEBUG
        if Int(time * 4) != lastDebugFrame {
            lastDebugFrame = Int(time * 4)
            print("[Mossgate] frame: sceneSize=\(size) viewScale=\(viewScale) camY=\(camY)")
        }
    }
    private var lastDebugFrame: Int = -1

    private var dtForShake: CGFloat = 1/60

    // ── Render ────────────────────────────────────────────────────

    private func render() {
        // Bail early if the level isn't fully loaded.
        guard isLoaded else { return }
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
        playerNode.position = CGPoint(
            x: (playerX + Phys.playerW/2) * viewScale,
            y: (playerY + Phys.playerH/2) * viewScale
        )
        playerNode.xScale = facing
        playerNode.yScale = -1   // keep the counter-flip from addWorldChild

        // Coin spin & bob. The old code showed the uncollected coins and then
        // ran `for node in coinNodes where !node.isHidden { node.isHidden = true }`,
        // which matched every coin the previous pass had just revealed and hid
        // them again — so no coin was ever drawn.
        for (i, node) in coinNodes.enumerated() {
            if coinsGot.contains(i) {
                node.isHidden = true
                continue
            }
            node.isHidden = false
            let frame = (coinFrames.isEmpty ? 0 : Int(time * 8) % coinFrames.count)
            node.texture = coinFrames[safe: frame] ?? node.texture
            let bob = sin(time * 3.2 + CGFloat(i)) * 3
            if i < level.coins.count {
                let c = level.coins[i]
                node.position = CGPoint(x: c.x * viewScale, y: (c.y + bob) * viewScale)
            }
        }

        // Lanterns — gentle pulse + bob so they read as the pickups they are,
        // and hidden once collected (previously they stayed on screen forever).
        for (i, node) in lanternNodes.enumerated() {
            if lanternsGot.contains(i) {
                node.isHidden = true
                continue
            }
            node.isHidden = false
            let phase = time * 2.6 + CGFloat(i) * 1.3
            let pulse = 1.0 + 0.12 * sin(phase)
            let s = 40 * viewScale * pulse
            node.size = CGSize(width: s, height: s)
            node.alpha = 0.82 + 0.18 * sin(phase)
            if i < level.lanterns.count {
                let l = level.lanterns[i]
                let bob = sin(time * 1.8 + CGFloat(i)) * 4
                node.position = CGPoint(x: l.x * viewScale, y: (l.y + bob) * viewScale)
            }
        }

        // Flag
        if !flagFrames.isEmpty {
            let idx = Int(time * 6) % flagFrames.count
            flagNode.texture = flagFrames[idx]
        }
        flagNode.position = CGPoint(x: level.flag.x * viewScale, y: level.flag.y * viewScale)

        // Checkpoints
        for (i, node) in checkpointNodes.enumerated() {
            if i < level.checkpoints.count {
                let c = level.checkpoints[i]
                node.position = CGPoint(x: c.x * viewScale, y: (c.y - 36) * viewScale)
            }
            let lit = i <= cp
            node.color = lit ? .white : .gray
            node.colorBlendFactor = lit ? 0 : 0.6
        }

        // Movers — positions are TOP-LEFT; the sprite is centre-anchored.
        for (i, m) in level.movers.enumerated() {
            if i < moverPositions.count, i < moverNodes.count {
                let p = moverPositions[i]
                moverNodes[i].position = CGPoint(x: (p.x + m.w/2) * viewScale,
                                                 y: (p.y + m.h/2) * viewScale)
            }
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
            jumps: jumps,
            lanterns: lanternsGot.count,
            lanternsTotal: level.lanterns.count,
            lives: SettingsStore.shared.lives,
            maxLives: SettingsStore.maxLives
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

/// Tiny deterministic PRNG so the star pattern in the sky is identical across
/// launches of the same level. SplitMix64 — fast, well-distributed, good enough
/// for visual noise.
private struct SplitMix64 {
    private var state: UInt64
    init(state: UInt64) { self.state = state &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }
}
