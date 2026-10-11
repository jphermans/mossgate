import SwiftUI
import SpriteKit

/// SwiftUI wrapper around the SpriteKit game scene. Owns the SKView lifetime,
/// pipes phase/HUD info back to the parent view via callbacks, and exposes the
/// live scene through `GameSession` so RootView can drive touch input directly.
struct MossgateGameView: UIViewRepresentable {
    let levelIndex: Int
    let session: GameSession
    @Binding var hud: MossgateScene.HudInfo

    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.backgroundColor = UIColor(named: "MossgateDusk") ?? .black
        view.preferredFramesPerSecond = 60
        view.showsFPS = false
        view.showsNodeCount = false
        view.ignoresSiblingOrder = true

        // Fixed 720×360 logical scene; resizeFill scales it to the device's actual
        // size so every world unit = 1 scene point, regardless of iPhone model.
        let scene = MossgateScene(size: CGSize(width: 720, height: 360))
        scene.scaleMode = .resizeFill
        scene.onPhaseChange = { _, info in
            DispatchQueue.main.async { hud = info }
        }
        scene.startLevel(levelIndex)
        context.coordinator.scene = scene
        session.scene = scene
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        guard let scene = context.coordinator.scene else { return }
        session.scene = scene
        if scene.levelIndex != levelIndex {
            scene.startLevel(levelIndex)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var scene: MossgateScene?
    }
}

/// Shared object between RootView and MossgateGameView. The view writes the
/// live scene into `scene` once it's created; RootView reads it to push touch
/// state and trigger pause/resume/retry. Using a shared object beats walking
/// the UIViewController tree to find the SKView, which is unreliable under the
/// SwiftUI hosting hierarchy.
@MainActor
final class GameSession: ObservableObject {
    weak var scene: MossgateScene?
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