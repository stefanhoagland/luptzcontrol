import SwiftUI

/// All cameras in a grid, with the controls for the selected one on the right,
/// like the multi-camera view in PTZ Control Center.
struct GridLayoutView: View {
    @EnvironmentObject private var store: CameraStore
    @Binding var selection: Camera.ID?

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 8)]

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(store.cameras) { camera in
                        GridTile(camera: camera, isSelected: camera.id == selection)
                            .id(camera)
                            .onTapGesture { selection = camera.id }
                    }
                }
                .padding(8)
            }
            .background(Color.black.opacity(0.85))

            Divider()

            if let id = selection, let camera = store.cameras.first(where: { $0.id == id }) {
                GridControls(camera: camera)
                    .id(camera)
                    .frame(width: 300)
            } else {
                Text("Click a camera to control it")
                    .foregroundStyle(.secondary)
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
            }
        }
        .navigationTitle("All Cameras")
    }
}

private struct GridTile: View {
    let camera: Camera
    let isSelected: Bool
    @StateObject private var feed: VideoFeed

    init(camera: Camera, isSelected: Bool) {
        self.camera = camera
        self.isSelected = isSelected
        let client = PanasonicClient(host: camera.host, username: camera.username, password: camera.password)
        _feed = StateObject(wrappedValue: VideoFeed(client: client, preferSmall: true))
    }

    var body: some View {
        VideoView(feed: feed, tallyOn: false)
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(Color.black)
            .overlay(alignment: .bottomLeading) {
                Text(camera.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                    .padding(6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.15),
                                  lineWidth: isSelected ? 3 : 1)
            }
            .contentShape(Rectangle())
            .onAppear { feed.start() }
            .onDisappear { feed.stop() }
    }
}

/// Controls for the selected camera in the grid. Video is already in the tile.
private struct GridControls: View {
    @StateObject private var controller: CameraController

    init(camera: Camera) {
        _controller = StateObject(wrappedValue: CameraController(camera: camera))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.camera.displayName).font(.headline)
                Text(controller.lastError ?? "\(controller.camera.model) · \(controller.camera.host)")
                    .font(.caption)
                    .foregroundStyle(controller.lastError == nil ? Color.secondary : Color.orange)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            ControlPanelView(controller: controller)
        }
        .onAppear { controller.start(withVideo: false) }
        .onDisappear { controller.stop() }
    }
}
