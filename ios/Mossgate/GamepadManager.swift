import Foundation
import GameController

/// Bridges external game controllers into the game's input path.
///
/// Deliberately two layers: `map(_:)` is a pure function from a pad snapshot to
/// the four inputs the game understands, so the mapping can be exercised
/// headlessly with no controller attached; `install(on:)` is the thin
/// GCController plumbing around it.
final class GamepadManager {
    static let shared = GamepadManager()

    /// What a controller is asking for right now.
    struct Snapshot {
        var stickX: Float = 0
        var stickY: Float = 0
        var dpadLeft = false, dpadRight = false, dpadUp = false, dpadDown = false
        var a = false, b = false, menu = false
    }

    /// The game's four inputs, plus the menu button.
    struct Input: Equatable {
        var left = false, right = false, jump = false, down = false
        var menu = false
        static let neutral = Input()
    }

    /// Thumbstick dead zone. The d-pad is deliberately excluded: it is a digital
    /// control, so "pressed" already means intent.
    static let stickDeadZone: Float = 0.35

    /// Pure mapping from a pad snapshot to game input.
    ///
    /// Jump is on the face button and d-pad up; DOWN — which steps off a
    /// one-way ledge, dives, and pans the view — is on the second face button,
    /// d-pad down, or the stick pulled down. The stick's up axis is NOT jump,
    /// so nudging the stick while running cannot fire a jump.
    static func map(_ s: Snapshot) -> Input {
        var i = Input()
        i.left  = s.dpadLeft  || s.stickX < -stickDeadZone
        i.right = s.dpadRight || s.stickX >  stickDeadZone
        i.jump  = s.a || s.dpadUp
        i.down  = s.b || s.dpadDown || s.stickY < -0.5
        i.menu  = s.menu
        return i
    }

    /// Input changes, on the main thread. Only fires when the state actually
    /// changes, so holding a direction does not spam the scene.
    var onInput: ((Input) -> Void)?
    /// Menu / Start pressed (rising edge).
    var onMenu: (() -> Void)?
    /// The connected-controller list changed. Names are for the Setup screen.
    var onDevicesChanged: (([String]) -> Void)?

    private(set) var devices: [String] = []

    private var observers: [NSObjectProtocol] = []
    private var watching = false
    private var last = Input.neutral
    private var menuHeld = false

    private init() {}

    /// Start watching for controllers. Idempotent.
    func start() {
        guard !watching else { return }
        watching = true
        let nc = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect,
                     Notification.Name.GCControllerDidDisconnect] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.refresh()
            })
        }
        refresh()
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        watching = false
        devices = []
        emit(Input.neutral)
        onDevicesChanged?([])
    }

    /// Re-read the connected controllers and (re)install their handlers. Also
    /// called on connect/disconnect so controllers picked up mid-game work.
    func refresh() {
        let controllers = GCController.controllers()
        controllers.forEach { install(on: $0) }
        // A controller that vanished must not leave a direction stuck on, so
        // re-derive the state from whatever is still physically held.
        let live = Self.liveInput(controllers)
        devices = controllers.map(Self.describe)
        onDevicesChanged?(devices)
        emit(live)
    }

    private static func describe(_ c: GCController) -> String {
        let vendor = c.vendorName?.trimmingCharacters(in: .whitespaces) ?? ""
        let category = c.productCategory.trimmingCharacters(in: .whitespaces)
        switch (vendor.isEmpty, category.isEmpty) {
        case (true, true):   return "Game controller"
        case (true, false):  return category
        case (false, true):  return vendor
        default:             return "\(vendor) · \(category)"
        }
    }

    private static func snapshot(_ pad: GCExtendedGamepad) -> Input {
        map(Snapshot(stickX: pad.leftThumbstick.xAxis.value,
                     stickY: pad.leftThumbstick.yAxis.value,
                     dpadLeft: pad.dpad.left.isPressed,
                     dpadRight: pad.dpad.right.isPressed,
                     dpadUp: pad.dpad.up.isPressed,
                     dpadDown: pad.dpad.down.isPressed,
                     a: pad.buttonA.isPressed,
                     b: pad.buttonB.isPressed,
                     menu: pad.buttonMenu.isPressed || (pad.buttonOptions?.isPressed ?? false)))
    }

    /// Current state of whichever controller is first in the list.
    private static func liveInput(_ controllers: [GCController]) -> Input {
        for c in controllers {
            if let pad = c.extendedGamepad { return snapshot(pad) }
            if let micro = c.microGamepad { return microInput(micro) }
        }
        return .neutral
    }

    /// Siri Remote and similar: d-pad plus face buttons, no sticks. `buttonA` is
    /// optional because the 2nd-generation remote does not have one.
    private static func microInput(_ micro: GCMicroGamepad) -> Input {
        map(Snapshot(dpadLeft: micro.dpad.left.isPressed,
                     dpadRight: micro.dpad.right.isPressed,
                     dpadUp: micro.dpad.up.isPressed,
                     dpadDown: micro.dpad.down.isPressed,
                     a: micro.buttonA.isPressed,
                     menu: micro.buttonMenu.isPressed))
    }

    private func install(on controller: GCController) {
        controller.playerIndex = .index1
        if let pad = controller.extendedGamepad {
            pad.valueChangedHandler = { [weak self] pad, _ in
                self?.emit(Self.snapshot(pad))
            }
        } else if let micro = controller.microGamepad {
            micro.valueChangedHandler = { [weak self] micro, _ in
                self?.emit(Self.microInput(micro))
            }
        }
    }

    private func emit(_ i: Input) {
        guard i != last else { return }
        if i.menu && !menuHeld { onMenu?() }
        menuHeld = i.menu
        last = i
        onInput?(i)
    }
}

/// Mirrors the connected-controller list for SwiftUI.
///
/// `GamepadManager` stays a plain class; this is the single place the list is
/// published, so there is exactly one writer and the Setup screen can observe it.
@MainActor
final class ControllerList: ObservableObject {
    static let shared = ControllerList()
    @Published var names: [String] = []
    private init() {}
}
