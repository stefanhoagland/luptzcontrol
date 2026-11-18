import Foundation

/// A camera the user has added to the app.
struct Camera: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var host: String
    var model: String
    var username: String = ""

    var displayName: String { name.isEmpty ? host : name }

    var password: String {
        get { Keychain.password(for: id.uuidString) ?? "" }
        nonmutating set { Keychain.setPassword(newValue, for: id.uuidString) }
    }
}

/// Keeps the list of cameras and saves it between launches.
@MainActor
final class CameraStore: ObservableObject {
    @Published private(set) var cameras: [Camera] = []

    private let key = "cameras.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Camera].self, from: data) {
            cameras = saved
        }
    }

    func contains(host: String) -> Bool {
        cameras.contains { $0.host == host }
    }

    @discardableResult
    func add(host: String, model: String, name: String, username: String, password: String) -> Camera {
        if let existing = cameras.first(where: { $0.host == host }) { return existing }
        let camera = Camera(name: name, host: host, model: model, username: username)
        camera.password = password
        cameras.append(camera)
        save()
        return camera
    }

    func update(_ camera: Camera) {
        guard let index = cameras.firstIndex(where: { $0.id == camera.id }) else { return }
        cameras[index] = camera
        save()
    }

    func remove(_ camera: Camera) {
        camera.password = ""
        cameras.removeAll { $0.id == camera.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cameras) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
