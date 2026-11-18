import Foundation
import CoreGraphics
import ImageIO

/// Live picture for one camera. Tries the camera's MJPEG streams first, then falls back
/// to fetching JPEG stills as fast as the camera allows.
@MainActor
final class VideoFeed: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var status: String = "Connecting…"
    @Published private(set) var sourceDescription: String = ""

    private let client: PanasonicClient
    private var stream: MJPEGStream?
    private var watchdog: Task<Void, Never>?
    private var poller: Task<Void, Never>?
    private var candidateIndex = 0
    private var receivedFrame = false
    private var running = false

    /// MJPEG addresses used by Panasonic AW cameras, best first.
    private var candidates: [(String, String)] {
        let h = client.host
        return [
            ("MJPEG 1280×720", "http://\(h)/cgi-bin/mjpeg?resolution=1280x720&quality=1"),
            ("MJPEG 640×360", "http://\(h)/cgi-bin/mjpeg?resolution=640x360&quality=1"),
            ("MJPEG stream 1", "http://\(h)/cgi-bin/mjpeg?stream=1"),
        ]
    }

    init(client: PanasonicClient) {
        self.client = client
    }

    func start() {
        guard !running else { return }
        running = true
        candidateIndex = 0
        tryNextCandidate()
    }

    func stop() {
        running = false
        watchdog?.cancel()
        poller?.cancel()
        stream?.stop()
        stream = nil
    }

    func restart() {
        stop()
        image = nil
        status = "Connecting…"
        start()
    }

    private func tryNextCandidate() {
        guard running else { return }
        guard candidateIndex < candidates.count else {
            startPolling()
            return
        }
        let (label, urlString) = candidates[candidateIndex]
        guard let url = URL(string: urlString) else { advance(); return }
        receivedFrame = false
        stream?.stop()
        let stream = MJPEGStream(username: client.username, password: client.password)
        let attempt = candidateIndex
        stream.onFrame = { [weak self] frame in
            Task { @MainActor in self?.show(frame, from: label, attempt: attempt) }
        }
        stream.onFailure = { [weak self] error in
            Task { @MainActor in self?.failed(error, attempt: attempt) }
        }
        self.stream = stream
        stream.start(url: url)

        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.timedOut(attempt: attempt)
        }
    }

    private func show(_ frame: CGImage, from label: String, attempt: Int) {
        guard running, attempt == candidateIndex else { return }
        receivedFrame = true
        image = frame
        status = ""
        sourceDescription = label
    }

    private func failed(_ error: Error, attempt: Int) {
        guard running, attempt == candidateIndex else { return }
        if let panasonicError = error as? PanasonicError, case .loginRequired = panasonicError {
            stop()
            status = "This camera needs a login. Click the gear button to enter it."
            return
        }
        if receivedFrame {
            // Stream dropped after working: reconnect the same one.
            status = "Reconnecting…"
            stream?.stop()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.tryNextCandidate()
            }
        } else {
            advance()
        }
    }

    private func timedOut(attempt: Int) {
        guard running, attempt == candidateIndex, !receivedFrame else { return }
        advance()
    }

    private func advance() {
        candidateIndex += 1
        tryNextCandidate()
    }

    private func startPolling() {
        stream?.stop()
        stream = nil
        sourceDescription = "JPEG stills"
        poller?.cancel()
        poller = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let data = try await self.client.snapshot()
                    if let source = CGImageSourceCreateWithData(data as CFData, nil),
                       let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                        self.image = frame
                        self.status = ""
                        failures = 0
                    }
                } catch PanasonicError.loginRequired {
                    self.status = "This camera needs a login. Click the gear button to enter it."
                    return
                } catch {
                    failures += 1
                    if failures >= 3 { self.status = "No video from the camera. Is it powered on and reachable?" }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
}
