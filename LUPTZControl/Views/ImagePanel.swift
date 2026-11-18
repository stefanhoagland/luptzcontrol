import SwiftUI

/// White balance, gain and ND filter.
struct ImagePanel: View {
    @ObservedObject var controller: CameraController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(ImageSetting.all) { setting in
                PanelSection(setting.label) {
                    if controller.unsupportedSettings.contains(setting.code) {
                        Text("Not available on this camera")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(setting.label, selection: binding(for: setting)) {
                            if setting.label(for: controller.settingValues[setting.code]) == nil {
                                Text(controller.settingValues[setting.code].map { "Other (\($0))" } ?? "Unknown")
                                    .tag(controller.settingValues[setting.code] ?? "")
                            }
                            ForEach(setting.choices, id: \.self) { choice in
                                Text(choice.label).tag(choice.value)
                            }
                        }
                        .labelsHidden()
                    }
                    if setting.code == "AW" {
                        HStack {
                            Button("Auto white (AWB)") { controller.whiteBalanceSet() }
                                .help("Point the camera at something white, then press")
                            Button("Auto black (ABB)") { controller.blackBalanceSet() }
                        }
                    }
                }
            }
            Button {
                Task { await controller.loadSettings() }
            } label: {
                Label("Reload from camera", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.link)
        }
    }

    private func binding(for setting: ImageSetting) -> Binding<String> {
        Binding(
            get: {
                let current = controller.settingValues[setting.code] ?? ""
                // Match the camera's spelling (e.g. "0e" vs "0E") to our choice values.
                return setting.choices.first { $0.value.caseInsensitiveCompare(current) == .orderedSame }?.value ?? current
            },
            set: { controller.set(setting, to: $0) }
        )
    }
}
