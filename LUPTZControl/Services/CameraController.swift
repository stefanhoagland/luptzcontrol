import Foundation

/// Drives one camera: sends joystick, zoom, focus and iris movement at a safe rate,
/// plus one-off commands such as presets, power and image settings.
@MainActor
final class CameraController: ObservableObject {
    @Published private(set) var camera: Camera
    @Published var lastError: String?
    @Published private(set) var isPoweredOn: Bool?
    @Published private(set) var autoFocus = true
    @Published private(set) var autoIris = true
    @Published private(set) var tallyOn = false
    @Published private(set) var lastPreset: Int?
    /// 0.1...1, scales the joystick's top speed.
    @Published var speedLimit: Double = 0.7

    /// Live lens positions, 0...1. nil until the camera reports them.
    @Published private(set) var focusPosition: Double?
    @Published private(set) var irisPosition: Double?
    /// True while the user drags a slider, so live updates don't fight the drag.
    var isDraggingFocus = false
    var isDraggingIris = false

    /// Current value of each ImageSetting, by code.
    @Published private(set) var settingValues: [String: String] = [:]
    /// Settings this camera answered with an error (not supported on this model).
    @Published private(set) var unsupportedSettings: Set<String> = []

    let client: PanasonicClient
    let video: VideoFeed

    private struct Motion: Equatable {
        var pan = 0, tilt = 0, zoom = 0, focus = 0
    }
    private var wanted = Motion()
    private var sent = Motion()
    private var wantedFocusPosition: Double?
    private var wantedIrisPosition: Double?
    private var loop: Task<Void, Never>?
    private var idleTicks = 0

    /// Panasonic asks for at least 130 ms between commands to the same camera.
    private let commandInterval: UInt64 = 130_000_000

    init(camera: Camera) {
        self.camera = camera
        client = PanasonicClient(host: camera.host, username: camera.username, password: camera.password)
        video = VideoFeed(client: client)
    }

    func start() {
        video.start()
        guard loop == nil else { return }
        loop = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(nanoseconds: self.commandInterval)
            }
        }
    }

    func stop() {
        wanted = Motion()
        let client = self.client
        // Make sure the camera stops moving when we leave.
        if sent != Motion() {
            Task {
                try? await client.panTilt(pan: 0, tilt: 0)
                try? await client.zoom(speed: 0)
                try? await client.focus(speed: 0)
            }
        }
        loop?.cancel()
        loop = nil
        video.stop()
    }

    func refresh() async {
        do {
            isPoweredOn = try await client.isPoweredOn()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        autoFocus = (try? await client.isAutoFocus()) ?? autoFocus
        autoIris = (try? await client.isAutoIris()) ?? autoIris
        focusPosition = (try? await client.focusPosition()) ?? focusPosition
        irisPosition = (try? await client.irisPosition()) ?? irisPosition
        await loadSettings()
    }

    func loadSettings() async {
        for setting in ImageSetting.all {
            do {
                settingValues[setting.code] = try await client.setting(setting.code)
                unsupportedSettings.remove(setting.code)
            } catch PanasonicError.camera(_) {
                unsupportedSettings.insert(setting.code)
            } catch {
                // Network trouble: keep what we had.
            }
        }
    }

    // MARK: Continuous movement (values are -1...1)

    func setPanTilt(x: Double, y: Double) {
        wanted.pan = Self.speed(x, limit: speedLimit)
        wanted.tilt = Self.speed(y, limit: speedLimit)
    }

    func setZoom(_ value: Double) {
        wanted.zoom = Self.speed(value, limit: 1)
    }

    func setFocus(_ value: Double) {
        wanted.focus = Self.speed(value, limit: 0.6)
    }

    /// Absolute focus, 0 = near, 1 = far. Sent at the safe command rate.
    func setFocusPosition(_ value: Double) {
        focusPosition = value
        wantedFocusPosition = value
    }

    /// Absolute iris, 0 = closed, 1 = open.
    func setIrisPosition(_ value: Double) {
        irisPosition = value
        wantedIrisPosition = value
    }

    /// Curved response: fine control near the center, full speed at the edge.
    private static func speed(_ value: Double, limit: Double) -> Int {
        let clamped = min(max(value, -1), 1)
        let curved = (clamped < 0 ? -1 : 1) * pow(abs(clamped), 1.6)
        return Int((curved * 49 * limit).rounded())
    }

    /// Sends at most one command per tick: movement first, then lens positions,
    /// and when idle, reads back the lens positions about once a second.
    private func tick() async {
        let target = wanted
        do {
            if target.pan != sent.pan || target.tilt != sent.tilt {
                try await client.panTilt(pan: target.pan, tilt: target.tilt)
                sent.pan = target.pan
                sent.tilt = target.tilt
            } else if target.zoom != sent.zoom {
                try await client.zoom(speed: target.zoom)
                sent.zoom = target.zoom
            } else if target.focus != sent.focus {
                try await client.focus(speed: target.focus)
                sent.focus = target.focus
            } else if let value = wantedFocusPosition {
                wantedFocusPosition = nil
                try await client.setFocusPosition(value)
            } else if let value = wantedIrisPosition {
                wantedIrisPosition = nil
                try await client.setIrisPosition(value)
            } else {
                idleTicks += 1
                if idleTicks % 8 == 0 { await pollLens(focus: idleTicks % 16 == 0) }
                return
            }
            idleTicks = 0
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func pollLens(focus: Bool) async {
        if focus {
            guard !isDraggingFocus, let value = try? await client.focusPosition() else { return }
            if !isDraggingFocus && wantedFocusPosition == nil { focusPosition = value }
        } else {
            guard !isDraggingIris, let value = try? await client.irisPosition() else { return }
            if !isDraggingIris && wantedIrisPosition == nil { irisPosition = value }
        }
    }

    // MARK: One-off commands

    func recallPreset(_ number: Int) {
        run { try await $0.recallPreset(number) }
        lastPreset = number
    }

    func savePreset(_ number: Int) {
        run { try await $0.savePreset(number) }
        lastPreset = number
    }

    func togglePower() {
        let turnOn = !(isPoweredOn ?? true)
        run { try await $0.setPower(turnOn) }
        isPoweredOn = turnOn
    }

    func toggleTally() {
        let on = !tallyOn
        run { try await $0.setTally(on) }
        tallyOn = on
    }

    func setAutoFocus(_ on: Bool) {
        run { try await $0.setAutoFocus(on) }
        autoFocus = on
    }

    func pushAutoFocus() {
        run { try await $0.pushAutoFocus() }
    }

    func setAutoIris(_ on: Bool) {
        run { try await $0.setAutoIris(on) }
        autoIris = on
    }

    func set(_ setting: ImageSetting, to value: String) {
        let previous = settingValues[setting.code]
        settingValues[setting.code] = value
        let code = setting.code
        Task {
            do {
                try await client.setSetting(code, to: value)
                lastError = nil
            } catch {
                settingValues[code] = previous
                lastError = error.localizedDescription
            }
        }
    }

    func whiteBalanceSet() {
        run { try await $0.whiteBalanceSet() }
    }

    func blackBalanceSet() {
        run { try await $0.blackBalanceSet() }
    }

    private func run(_ action: @escaping (PanasonicClient) async throws -> Void) {
        let client = self.client
        Task {
            do {
                try await action(client)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}
