import SwiftUI

@main
struct LUPTZControlApp: App {
    @StateObject private var store = CameraStore()

    var body: some Scene {
        WindowGroup("LU PTZ Control") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1000, minHeight: 640)
        }
    }
}
