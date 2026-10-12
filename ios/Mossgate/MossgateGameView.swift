import SwiftUI
import SpriteKit

/// SwiftUI wrapper around the SpriteKit game scene. The SKScene dynamically
/// matches the SKView's actual size — viewScale converts world units (designed
/// for a 720×360 logical canvas) to scene points. That way the game looks the
/// same on every iPhone, regardless of screen size.
struct MossgateGameView: UIViewRepresentable {
    static let worldWidth: CGFloat = 720
    static let worldHeight: CGFloat = 360

    let levelIndex: Int
    let session: GameSession
    @Binding var hud: MossgateScene.HudInfo

    /// SKView subclass that updates the scene's size every time its bounds change.
    /// This is the standard SpriteKit pattern; without it, the scene renders into
    /// a 0×0 buffer because SwiftUI doesn't update bounds during `layoutIfNeeded()`.
    final class ResizableSKView: SKView {
        weak var sceneRef: SKScene?
        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.size.width > 0, bounds.size.height > 0 else { return }
            if let s = sceneRef, s.size != bounds.size {
                s.size = bounds.size
            }
        }
    }

    func makeUIView(context: Context) -> SKView {
        let view = ResizableSKView(frame: .zero)
        view.backgroundColor = UIColor(named: "MossgateDusk") ?? .black
        view.preferredFramesPerSecond = 60
        view.showsFPS = false
        view.showsNodeCount = false
        view.ignoresSiblingOrder = true

        let scene = MossgateScene(size: CGSize(width: 720, height: 360))
        scene.scaleMode = .resizeFill
        scene.onPhaseChange = { _, info in
            DispatchQueue.main.async { hud = info }
        }
        context.coordinator.scene = scene
        session.scene = scene
        view.sceneRef = scene
        view.presentScene(scene)
        scene.startLevel(levelIndex)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        guard let scene = context.coordinator.scene else { return }
        session.scene = scene
        if uiView.bounds.size.width > 0,
           scene.size != uiView.bounds.size {
            scene.size = uiView.bounds.size
            scene.startLevel(levelIndex)
        }
        if scene.levelIndex != levelIndex {
            scene.startLevel(levelIndex)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var scene: MossgateScene?
    }
}

/// Shared object between RootView and MossgateGameView.
@MainActor
final class GameSession: ObservableObject {
    weak var scene: MossgateScene?
}

/// Touch input bridge.
final class TouchState: ObservableObject {
    @Published var left = false
    @Published var right = false
    @Published var jump = false
    @Published var down = false
    /// Look up — the counterpart to `down`. DOWN pans the camera to show what waits below;
    /// without this there is no way to see what is above you. Asked for as "there is a button
    /// to look down, but not to look up, how can I go back up when I can not see what's
    /// there?"
    @Published var up = false

    func push(to scene: MossgateScene?) {
        scene?.setTouch(left: left, right: right, jump: jump, down: down, up: up)
    }
}