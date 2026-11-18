import Foundation

enum PanasonicError: LocalizedError {
    case loginRequired
    case http(Int)
    case camera(String)

    var errorDescription: String? {
        switch self {
        case .loginRequired: return "This camera needs a user name and password."
        case .http(let code): return "The camera answered with HTTP error \(code)."
        case .camera(let reply): return "The camera rejected the command (\(reply))."
        }
    }
}

/// Answers login challenges from the camera (Panasonic uses HTTP digest auth).
final class CredentialDelegate: NSObject, URLSessionTaskDelegate {
    let username: String
    let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        let isLogin = method == NSURLAuthenticationMethodHTTPDigest || method == NSURLAuthenticationMethodHTTPBasic
        if isLogin, !username.isEmpty, challenge.previousFailureCount == 0 {
            completionHandler(.useCredential, URLCredential(user: username, password: password, persistence: .forSession))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// Talks to one Panasonic PTZ camera over its HTTP CGI interface.
/// The same commands work on the AW-UE150, UE100, UE80, UE50/40, HE130, HE40 and most other AW models.
final class PanasonicClient {
    let host: String
    let username: String
    let password: String
    private let session: URLSession

    init(host: String, username: String = "", password: String = "", timeout: TimeInterval = 2) {
        self.host = host
        self.username = username
        self.password = password
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.httpMaximumConnectionsPerHost = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config,
                             delegate: CredentialDelegate(username: username, password: password),
                             delegateQueue: nil)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    /// Pan, tilt, zoom, focus, iris, presets, power: `/cgi-bin/aw_ptz`
    @discardableResult
    func ptz(_ command: String) async throws -> String {
        try await send(path: "/cgi-bin/aw_ptz", command: command)
    }

    /// Camera settings and info: `/cgi-bin/aw_cam`
    @discardableResult
    func cam(_ command: String) async throws -> String {
        try await send(path: "/cgi-bin/aw_cam", command: command)
    }

    /// Fetches one JPEG still from the camera.
    func snapshot(width: Int = 640) async throws -> Data {
        try await get("http://\(host)/cgi-bin/camera?resolution=\(width)&quality=1")
    }

    private func send(path: String, command: String) async throws -> String {
        let encoded = command.replacingOccurrences(of: "#", with: "%23")
        let data = try await get("http://\(host)\(path)?cmd=\(encoded)&res=1")
        let reply = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if reply.lowercased().hasPrefix("er") {
            throw PanasonicError.camera(reply)
        }
        return reply
    }

    private func get(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw PanasonicError.loginRequired }
            guard (200..<300).contains(http.statusCode) else { throw PanasonicError.http(http.statusCode) }
        }
        return data
    }
}

// MARK: - Commands

extension PanasonicClient {
    /// Two-digit speed code. 50 = stop, 01 = full speed one way, 99 = full speed the other way.
    static func speedCode(_ offset: Int) -> String {
        String(format: "%02d", min(max(50 + offset, 1), 99))
    }

    /// Model name, for example "AW-UE150".
    func modelName() async throws -> String {
        try await cam("QID").replacingOccurrences(of: "OID:", with: "")
    }

    /// The camera title set in its web settings, for example "CAM 1".
    func title() async throws -> String {
        try await cam("QTN").replacingOccurrences(of: "OTN:", with: "")
    }

    /// pan and tilt are -49...49. Positive pan = right, positive tilt = up.
    func panTilt(pan: Int, tilt: Int) async throws {
        try await ptz("#PTS\(Self.speedCode(pan))\(Self.speedCode(tilt))")
    }

    /// -49...49. Positive = tele (zoom in), negative = wide.
    func zoom(speed: Int) async throws {
        try await ptz("#Z\(Self.speedCode(speed))")
    }

    /// -49...49. Positive = far, negative = near.
    func focus(speed: Int) async throws {
        try await ptz("#F\(Self.speedCode(speed))")
    }

    func setAutoFocus(_ on: Bool) async throws {
        try await ptz("#D1\(on ? 1 : 0)")
    }

    func isAutoFocus() async throws -> Bool {
        try await ptz("#D1") == "d11"
    }

    /// Preset numbers shown to the user start at 1. The camera counts from 00.
    func recallPreset(_ number: Int) async throws {
        try await ptz("#R\(String(format: "%02d", number - 1))")
    }

    func savePreset(_ number: Int) async throws {
        try await ptz("#M\(String(format: "%02d", number - 1))")
    }

    func setPower(_ on: Bool) async throws {
        try await ptz("#O\(on ? 1 : 0)")
    }

    /// true = on, false = standby.
    func isPoweredOn() async throws -> Bool {
        try await ptz("#O") == "p1"
    }

    /// Red tally lamp.
    func setTally(_ on: Bool) async throws {
        try await ptz("#DA\(on ? 1 : 0)")
    }
}

// MARK: - Lens and image

extension PanasonicClient {
    /// Panasonic absolute lens positions are 3 hex digits from 555 to FFF.
    static func lensCode(_ value: Double) -> String {
        let clamped = min(max(value, 0), 1)
        return String(format: "%03X", 0x555 + Int((clamped * Double(0xFFF - 0x555)).rounded()))
    }

    static func parseLens(_ reply: String, prefix: String) -> Double? {
        guard reply.hasPrefix(prefix) else { return nil }
        guard let raw = Int(reply.dropFirst(prefix.count).prefix(3), radix: 16) else { return nil }
        return min(max(Double(raw - 0x555) / Double(0xFFF - 0x555), 0), 1)
    }

    /// 0 = near, 1 = far.
    func focusPosition() async throws -> Double? {
        Self.parseLens(try await ptz("#GF"), prefix: "gf")
    }

    func setFocusPosition(_ value: Double) async throws {
        try await ptz("#AXF\(Self.lensCode(value))")
    }

    /// One-push autofocus while in manual focus.
    func pushAutoFocus() async throws {
        try await cam("OSE:69:1")
    }

    func setAutoIris(_ on: Bool) async throws {
        try await ptz("#D3\(on ? 1 : 0)")
    }

    func isAutoIris() async throws -> Bool {
        try await ptz("#D3") == "d31"
    }

    /// 0 = closed, 1 = open.
    func irisPosition() async throws -> Double? {
        Self.parseLens(try await ptz("#GI"), prefix: "gi")
    }

    func setIrisPosition(_ value: Double) async throws {
        try await ptz("#AXI\(Self.lensCode(value))")
    }

    /// Reads a camera setting such as "AW" (white balance). "OAW:1" comes back as "1".
    func setting(_ code: String) async throws -> String {
        let reply = try await cam("Q\(code)")
        guard let colon = reply.firstIndex(of: ":") else { return reply }
        return String(reply[reply.index(after: colon)...])
    }

    func setSetting(_ code: String, to value: String) async throws {
        try await cam("O\(code):\(value)")
    }

    /// Runs auto white balance (AWB) once.
    func whiteBalanceSet() async throws {
        try await cam("OWS")
    }

    /// Runs auto black balance (ABB) once.
    func blackBalanceSet() async throws {
        try await cam("OAS")
    }
}
