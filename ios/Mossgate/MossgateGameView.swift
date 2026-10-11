import SwiftUI
import SpriteKit

/// SwiftUI wrapper around the SpriteKit game scene. Owns the SKView lifetime
/// and pipes phase/HUD info back to the parent view via callbacks.
struct MossgateGameView: UIViewRepresentable {
    let levelIndex: Int
    @Binding var hud: MossgateScene.HudInfo

    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.backgroundColor = UIColor(named: "MossgateDusk") ?? .black
        view.preferredFramesPerSecond = 60
        view.showsFPS = false
        view.showsNodeCount = false
        view.ignoresSiblingOrder = true

        let scene = MossgateScene(size: view.bounds.size)
        scene.scaleMode = .resizeFill
        scene.onPhaseChange = { _, info in
            DispatchQueue.main.async { hud = info }
        }
        scene.startLevel(levelIndex)
        context.coordinator.scene = scene
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        guard let scene = context.coordinator.scene else { return }
        if scene.levelIndex != levelIndex {
            scene.startLevel(levelIndex)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var scene: MossgateScene?
    }
}

/// Touch input bridge — exposes four booleans the scene polls each frame.
final class TouchState: ObservableObject {
    @Published var left = false
    @Published var right = false
    @Published var jump = false
    @Published var down = false

    func push(to scene: MossgateScene?) {
        scene?.setTouch(left: left, right: right, jump: jump, down: down)
    }
}