import SwiftUI

struct ControlPanelView: View {
    @ObservedObject var controller: CameraController
    @State private var storeMode = false
    @State private var tab: Tab = .presets

    enum Tab: String, CaseIterable, Identifiable {
        case presets = "Presets", lens = "Lens", image = "Image"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button { controller.togglePower() } label: {
                        Label(powerLabel, systemImage: "power")
                    }
                    .tint(controller.isPoweredOn == false ? Color.gray : Color.green)
                    Spacer()
                    Toggle(isOn: Binding(get: { controller.tallyOn }, set: { _ in controller.toggleTally() })) {
                        Label("Tally", systemImage: "circle.fill")
                    }
                    .toggleStyle(.button)
                    .tint(.red)
                }

                PanelSection("Pan / Tilt") {
                    JoystickView { x, y in controller.setPanTilt(x: x, y: y) }
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)
                    HStack {
                        Image(systemName: "tortoise").foregroundStyle(.secondary)
                        Slider(value: $controller.speedLimit, in: 0.1...1)
                        Image(systemName: "hare").foregroundStyle(.secondary)
                    }
                    .help("Maximum pan/tilt speed")
                }

                PanelSection("Zoom") {
                    RockerView(leftLabel: "W", rightLabel: "T") { controller.setZoom($0) }
                }

                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch tab {
                case .presets: presets
                case .lens: LensPanel(controller: controller)
                case .image: ImagePanel(controller: controller)
                }
            }
            .padding(16)
        }
    }

    private var presets: some View {
        PanelSection("Presets") {
            Toggle(isOn: $storeMode) {
                Label(storeMode ? "Tap a number to save the current shot" : "Save mode",
                      systemImage: "square.and.arrow.down")
            }
            .toggleStyle(.button)
            .tint(storeMode ? Color.orange : nil)
            PresetGridView(highlighted: controller.lastPreset, storeMode: storeMode) { number in
                if storeMode {
                    controller.savePreset(number)
                    storeMode = false
                } else {
                    controller.recallPreset(number)
                }
            }
        }
    }

    private var powerLabel: String {
        switch controller.isPoweredOn {
        case .some(true): return "On"
        case .some(false): return "Standby"
        case .none: return "Power"
        }
    }
}

struct PanelSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}
