import Foundation
import Darwin

struct FoundCamera: Identifiable, Hashable {
    var id: String { host }
    let host: String
    let model: String
    let name: String
    let needsLogin: Bool
}

/// Scans a /24 network for Panasonic cameras by asking each address for its model name.
@MainActor
final class CameraScanner: ObservableObject {
    @Published var subnet: String
    @Published private(set) var subnets: [String]
    @Published private(set) var found: [FoundCamera] = []
    @Published private(set) var isScanning = false
    @Published private(set) var progress: Double = 0

    init() {
        let local = Self.localSubnets()
        subnets = local
        subnet = local.first ?? "192.168.0"
    }

    func scan(username: String, password: String) async {
        guard !isScanning else { return }
        isScanning = true
        found = []
        progress = 0
        let prefix = subnet.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let hosts = (1...254).map { "\(prefix).\($0)" }
        let batchSize = 64
        var checked = 0

        for start in stride(from: 0, to: hosts.count, by: batchSize) {
            let batch = Array(hosts[start..<min(start + batchSize, hosts.count)])
            let results = await withTaskGroup(of: FoundCamera?.self) { group -> [FoundCamera] in
                for host in batch {
                    group.addTask { await Self.probe(host: host, username: username, password: password) }
                }
                var hits: [FoundCamera] = []
                for await result in group {
                    if let result { hits.append(result) }
                }
                return hits
            }
            checked += batch.count
            progress = Double(checked) / Double(hosts.count)
            found = (found + results).sorted { Self.lastOctet($0.host) < Self.lastOctet($1.host) }
        }
        isScanning = false
    }

    /// Asks one address whether it is a Panasonic camera.
    nonisolated static func probe(host: String, username: String, password: String) async -> FoundCamera? {
        let client = PanasonicClient(host: host, username: username, password: password, timeout: 1.5)
        do {
            let model = try await client.modelName()
            guard !model.isEmpty else { return nil }
            let name = (try? await client.title()) ?? ""
            return FoundCamera(host: host, model: model, name: name, needsLogin: false)
        } catch PanasonicError.loginRequired {
            return FoundCamera(host: host, model: "Needs login", name: "", needsLogin: true)
        } catch {
            return nil
        }
    }

    private static func lastOctet(_ host: String) -> Int {
        Int(host.split(separator: ".").last ?? "") ?? 0
    }

    /// The first three numbers of each IPv4 address this computer has, e.g. ["192.168.10"].
    static func localSubnets() -> [String] {
        var result: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = pointer.pointee.ifa_flags
            guard let addr = pointer.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET),
                  flags & UInt32(IFF_UP) != 0,
                  flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostBuffer, socklen_t(hostBuffer.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: hostBuffer)
            let parts = ip.split(separator: ".")
            guard parts.count == 4, !ip.hasPrefix("169.254.") else { continue }
            let prefix = parts[0..<3].joined(separator: ".")
            if !result.contains(prefix) { result.append(prefix) }
        }
        return result
    }
}
