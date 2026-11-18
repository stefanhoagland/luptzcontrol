import Foundation

/// Drives one camera: sends joystick, zoom and focus movement at a safe rate,
/// plus one-off commands such as presets and power.
@MainActor
final class CameraController: ObservableObject {
    @Published private(set) var camera: Camera
    @Published var lastError: String?
    @Published private(set) var isPoweredOn: Bool?
    @Published private(set) var autoFocus = true
    @Published private(set) var tallyOn = false
    @Published private(set) var lastPreset: Int?
    /// 0.1...1, scales the joystick's top speed.
    @Published var speedLimit: Double = 0.7

    let client: PanasonicClient
    let video: VideoFeed

    private struct Motion: Equatable {
        var pan = 0, tilt = 0, zoom = 0, focus = 0
    }
    private var wanted = Motion()
    private var sent = Motion()
    private var loop: Task<Void, Never>?

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
            while !Task.isCancelled {
                guard let self else { return }
                await self.sendPendingMotion()
                try? await Task.sleep(nanoseconds: self.commandInterval)
            }
        }
        Task { await refresh() }
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
            autoFocus = try await client.isAutoFocus()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
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

    /// Curved response: fine control near the center, full speed at the edge.
    private static func speed(_ value: Double, limit: Double) -> Int {
        let clamped = min(max(value, -1), 1)
        let curved = (clamped < 0 ? -1 : 1) * pow(abs(clamped), 1.6)
        return Int((curved * 49 * limit).rounded())
    }

    private func sendPendingMotion() async {
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
            } else {
                return
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
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
