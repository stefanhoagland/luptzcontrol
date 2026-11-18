import AppKit
import GameController

/// Sends keyboard and gamepad input to whichever camera is being controlled.
@MainActor
final class InputRouter {
    static let shared = InputRouter()
    weak var active: CameraController?
    private init() {}
}

// MARK: - Keyboard

/// Keyboard shortcuts (also usable from a Stream Deck "Hotkey" button):
///   Arrow keys  pan / tilt while held (hold Shift for full speed)
///   + / -       zoom in / out while held
///   1–9, 0      recall presets 1–10
///   [ / ]       previous / next preset
///   F           push autofocus
///   T           toggle tally
@MainActor
final class KeyboardControl {
    static let shared = KeyboardControl()
    private var monitor: Any?
    private var heldArrows = Set<UInt16>()
    private var fast = false
    private var zoomHeld = 0

    private init() {}

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            let keyCode = event.keyCode
            let characters = event.charactersIgnoringModifiers ?? ""
            let type = event.type
            let isRepeat = type == .keyDown ? event.isARepeat : false
            let shift = event.modifierFlags.contains(.shift)
            let command = event.modifierFlags.contains(.command)
            let consumed = MainActor.assumeIsolated {
                KeyboardControl.shared.handle(type: type, keyCode: keyCode, characters: characters,
                                              isRepeat: isRepeat, shift: shift, command: command)
            }
            return consumed ? nil : event
        }
    }

    private static let shortcutKeys: Set<String> = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "[", "]", "f", "t"]

    private static let arrows: [UInt16: (Double, Double)] = [
        123: (-1, 0), 124: (1, 0), 125: (0, -1), 126: (0, 1),
    ]

    private func handle(type: NSEvent.EventType, keyCode: UInt16, characters: String,
                        isRepeat: Bool, shift: Bool, command: Bool) -> Bool {
        if type == .flagsChanged {
            fast = shift
            if !heldArrows.isEmpty { updatePanTilt() }
            return false
        }
        // Leave typing in text fields and menu shortcuts alone.
        if command { return false }
        if NSApp.keyWindow?.firstResponder is NSText { return false }
        guard let camera = InputRouter.shared.active else { return false }
        let isDown = type == .keyDown

        if Self.arrows[keyCode] != nil {
            if isDown { heldArrows.insert(keyCode) } else { heldArrows.remove(keyCode) }
            fast = shift
            updatePanTilt()
            return true
        }

        switch characters.lowercased() {
        case "=", "+":
            zoomHeld = isDown ? 1 : 0
            camera.setZoom(Double(zoomHeld) * 0.6)
            return true
        case "-", "_":
            zoomHeld = isDown ? -1 : 0
            camera.setZoom(Double(zoomHeld) * 0.6)
            return true
        default:
            break
        }

        let key = characters.lowercased()
        guard Self.shortcutKeys.contains(key) else { return false }
        guard isDown, !isRepeat else { return true }
        switch key {
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            camera.recallPreset(Int(characters) ?? 1)
        case "0":
            camera.recallPreset(10)
        case "[":
            camera.stepPreset(-1)
        case "]":
            camera.stepPreset(1)
        case "f":
            camera.pushAutoFocus()
        case "t":
            camera.toggleTally()
        default:
            return false
        }
        return true
    }

    private func updatePanTilt() {
        var x = 0.0, y = 0.0
        for key in heldArrows {
            if let (dx, dy) = Self.arrows[key] { x += dx; y += dy }
        }
        let scale = fast ? 1.0 : 0.55
        InputRouter.shared.active?.setPanTilt(x: max(-1, min(1, x)) * scale, y: max(-1, min(1, y)) * scale)
    }
}

// MARK: - Gamepad

/// Any controller macOS supports (Xbox, PlayStation, many USB/Bluetooth pads):
///   Left stick      pan / tilt
///   Right stick     zoom (up = in)
///   L2 / R2         focus near / far
///   L1 / R1         previous / next preset
///   D-pad           presets 1–4 (up, right, down, left)
///   A / Cross       push autofocus
///   Y / Triangle    toggle tally
@MainActor
final class GamepadManager {
    static let shared = GamepadManager()
    private var started = false
    private var focusNear: Float = 0
    private var focusFar: Float = 0

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { note in
            guard let controller = note.object as? GCController else { return }
            MainActor.assumeIsolated { GamepadManager.shared.attach(controller) }
        }
        for controller in GCController.controllers() { attach(controller) }
    }

    private func attach(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        controller.handlerQueue = .main

        pad.leftThumbstick.valueChangedHandler = { _, x, y in
            MainActor.assumeIsolated {
                InputRouter.shared.active?.setPanTilt(x: Self.deadZone(x), y: Self.deadZone(y))
            }
        }
        pad.rightThumbstick.valueChangedHandler = { _, _, y in
            MainActor.assumeIsolated { InputRouter.shared.active?.setZoom(Self.deadZone(y)) }
        }
        pad.leftTrigger.valueChangedHandler = { _, value, _ in
            MainActor.assumeIsolated {
                GamepadManager.shared.focusNear = value
                GamepadManager.shared.updateFocus()
            }
        }
        pad.rightTrigger.valueChangedHandler = { _, value, _ in
            MainActor.assumeIsolated {
                GamepadManager.shared.focusFar = value
                GamepadManager.shared.updateFocus()
            }
        }
        pad.leftShoulder.pressedChangedHandler = { _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { InputRouter.shared.active?.stepPreset(-1) }
        }
        pad.rightShoulder.pressedChangedHandler = { _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { InputRouter.shared.active?.stepPreset(1) }
        }
        pad.dpad.up.pressedChangedHandler = Self.preset(1)
        pad.dpad.right.pressedChangedHandler = Self.preset(2)
        pad.dpad.down.pressedChangedHandler = Self.preset(3)
        pad.dpad.left.pressedChangedHandler = Self.preset(4)
        pad.buttonA.pressedChangedHandler = { _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { InputRouter.shared.active?.pushAutoFocus() }
        }
        pad.buttonY.pressedChangedHandler = { _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { InputRouter.shared.active?.toggleTally() }
        }
    }

    private func updateFocus() {
        InputRouter.shared.active?.setFocus(Double(focusFar - focusNear))
    }

    private static func preset(_ number: Int) -> GCControllerButtonValueChangedHandler {
        return { _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { InputRouter.shared.active?.recallPreset(number) }
        }
    }

    /// Ignores small stick drift around the center.
    private nonisolated static func deadZone(_ value: Float) -> Double {
        abs(value) < 0.12 ? 0 : Double(value)
    }
}
