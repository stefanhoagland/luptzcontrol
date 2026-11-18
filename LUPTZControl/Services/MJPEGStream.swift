import Foundation
import ImageIO
import CoreGraphics

/// Reads a Motion-JPEG stream over HTTP and hands back each frame as a CGImage.
/// Frames are found by their JPEG start (FFD8) and end (FFD9) markers, so it works
/// whatever multipart boundary the camera uses.
final class MJPEGStream: NSObject, URLSessionDataDelegate {
    var onFrame: ((CGImage) -> Void)?
    var onFailure: ((Error) -> Void)?

    private let username: String
    private let password: String
    private var session: URLSession?
    private var buffer = Data()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()

    private static let startMarker = Data([0xFF, 0xD8])
    private static let endMarker = Data([0xFF, 0xD9])

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func start(url: URL) {
        stop()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        self.session = session
        session.dataTask(with: url).resume()
    }

    func stop() {
        session?.invalidateAndCancel()
        session = nil
        queue.addOperation { [weak self] in self?.buffer.removeAll() }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            completionHandler(.cancel)
            onFailure?(http.statusCode == 401 ? PanasonicError.loginRequired : PanasonicError.http(http.statusCode))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        var latest: Data?
        while let frame = nextFrame() { latest = frame }
        // Only decode the newest frame so we never fall behind live.
        if let latest,
           let source = CGImageSourceCreateWithData(latest as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            onFrame?(image)
        }
        if buffer.count > 8_000_000 { buffer.removeAll() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard session === self.session else { return }
        onFailure?(error ?? URLError(.networkConnectionLost))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        let isLogin = method == NSURLAuthenticationMethodHTTPDigest || method == NSURLAuthenticationMethodHTTPBasic
        if isLogin, !username.isEmpty, challenge.previousFailureCount == 0 {
            completionHandler(.useCredential, URLCredential(user: username, password: password, persistence: .forSession))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    private func nextFrame() -> Data? {
        guard let start = buffer.range(of: Self.startMarker) else {
            // Keep a trailing 0xFF in case the next chunk starts with 0xD8.
            if let last = buffer.last, last == 0xFF { buffer = Data([0xFF]) } else { buffer.removeAll() }
            return nil
        }
        guard let end = buffer.range(of: Self.endMarker, in: start.upperBound..<buffer.endIndex) else {
            if start.lowerBound > buffer.startIndex { buffer = Data(buffer[start.lowerBound...]) }
            return nil
        }
        let frame = Data(buffer[start.lowerBound..<end.upperBound])
        buffer = Data(buffer[end.upperBound...])
        return frame
    }
}
