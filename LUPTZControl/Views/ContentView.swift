import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: CameraStore
    @State private var selection: Camera.ID?
    @State private var showingFinder = false
    @AppStorage("layout") private var layout: Layout = .single

    enum Layout: String {
        case single, grid
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(store.cameras) { camera in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(camera.displayName).font(.headline)
                        Text("\(camera.model) · \(camera.host)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(camera.id)
                    .contextMenu {
                        Button("Remove Camera", role: .destructive) {
                            if selection == camera.id { selection = nil }
                            store.remove(camera)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .overlay {
                if store.cameras.isEmpty {
                    Text("No cameras yet").foregroundStyle(.secondary)
                }
            }
            .toolbar {
                ToolbarItem {
                    Button { showingFinder = true } label: {
                        Label("Find Cameras", systemImage: "plus.magnifyingglass")
                    }
                    .help("Scan the network for cameras")
                }
            }
        } detail: {
            if layout == .grid && !store.cameras.isEmpty {
                GridLayoutView(selection: $selection)
            } else if let id = selection, let camera = store.cameras.first(where: { $0.id == id }) {
                CameraDetailView(camera: camera)
                    .id(camera) // rebuilds when the camera's settings change
            } else {
                ContentUnavailableView {
                    Label("No Camera Selected", systemImage: "video")
                } description: {
                    Text("Pick a camera on the left, or find the cameras on your network.")
                } actions: {
                    Button("Find Cameras") { showingFinder = true }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Layout", selection: $layout) {
                    Label("Single", systemImage: "rectangle").tag(Layout.single)
                    Label("Grid", systemImage: "square.grid.2x2").tag(Layout.grid)
                }
                .pickerStyle(.segmented)
                .help("Show one camera, or all cameras in a grid")
            }
        }
        .sheet(isPresented: $showingFinder) {
            FindCamerasView { added in
                if selection == nil { selection = added.first?.id }
            }
            .environmentObject(store)
        }
        .onAppear {
            KeyboardControl.shared.install()
            GamepadManager.shared.start()
            if store.cameras.isEmpty {
                showingFinder = true
            } else if selection == nil {
                selection = store.cameras.first?.id
            }
        }
    }
}
