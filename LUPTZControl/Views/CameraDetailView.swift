import SwiftUI

/// Live video on the left, controls on the right, like PTZ Control Center.
struct CameraDetailView: View {
    @EnvironmentObject private var store: CameraStore
    @StateObject private var controller: CameraController
    @State private var showingSettings = false

    init(camera: Camera) {
        _controller = StateObject(wrappedValue: CameraController(camera: camera))
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VideoView(feed: controller.video, tallyOn: controller.tallyOn)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                StatusBar(controller: controller)
            }
            Divider()
            ControlPanelView(controller: controller)
                .frame(width: 300)
        }
        .navigationTitle(controller.camera.displayName)
        .navigationSubtitle("\(controller.camera.model) · \(controller.camera.host)")
        .toolbar {
            ToolbarItem {
                Button { controller.video.restart() } label: {
                    Label("Reconnect Video", systemImage: "arrow.clockwise")
                }
                .help("Reconnect video")
            }
            ToolbarItem {
                Button { showingSettings = true } label: {
                    Label("Camera Settings", systemImage: "gearshape")
                }
                .help("Name, address and login")
            }
        }
        .sheet(isPresented: $showingSettings) {
            CameraSettingsView(camera: controller.camera)
                .environmentObject(store)
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
    }
}

private struct StatusBar: View {
    @ObservedObject var controller: CameraController
    @ObservedObject var feed: VideoFeed

    init(controller: CameraController) {
        self.controller = controller
        self.feed = controller.video
    }

    var body: some View {
        HStack {
            Circle()
                .fill(controller.lastError == nil ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(controller.lastError ?? "Connected")
                .lineLimit(1)
            Spacer()
            Text(feed.sourceDescription).foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

/// Edit a camera's name, address and login.
struct CameraSettingsView: View {
    @EnvironmentObject private var store: CameraStore
    @Environment(\.dismiss) private var dismiss
    @State private var camera: Camera
    @State private var password: String

    init(camera: Camera) {
        _camera = State(initialValue: camera)
        _password = State(initialValue: camera.password)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Camera Settings").font(.title2.bold())
            Form {
                TextField("Name", text: $camera.name)
                TextField("IP address", text: $camera.host)
                TextField("User name", text: $camera.username)
                SecureField("Password", text: $password)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    camera.password = password
                    store.update(camera)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
