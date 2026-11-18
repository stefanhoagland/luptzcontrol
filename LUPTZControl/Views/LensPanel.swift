import SwiftUI

/// Focus and iris controls.
struct LensPanel: View {
    @ObservedObject var controller: CameraController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PanelSection("Focus") {
                HStack {
                    Toggle("Auto focus", isOn: Binding(get: { controller.autoFocus },
                                                      set: { controller.setAutoFocus($0) }))
                    Spacer()
                    Button("Push AF") { controller.pushAutoFocus() }
                        .disabled(controller.autoFocus)
                        .help("Focus once automatically, then stay in manual focus")
                }
                RockerView(leftLabel: "Near", rightLabel: "Far") { controller.setFocus($0) }
                    .disabled(controller.autoFocus)
                    .opacity(controller.autoFocus ? 0.4 : 1)
                PositionSlider(value: controller.focusPosition,
                               leftLabel: "Near", rightLabel: "Far",
                               enabled: !controller.autoFocus,
                               onDragging: { controller.isDraggingFocus = $0 },
                               onChange: { controller.setFocusPosition($0) })
            }

            PanelSection("Iris") {
                Toggle("Auto iris", isOn: Binding(get: { controller.autoIris },
                                                 set: { controller.setAutoIris($0) }))
                PositionSlider(value: controller.irisPosition,
                               leftLabel: "Close", rightLabel: "Open",
                               enabled: !controller.autoIris,
                               onDragging: { controller.isDraggingIris = $0 },
                               onChange: { controller.setIrisPosition($0) })
            }
        }
    }
}

/// A slider that shows the camera's live lens position and lets the user set it.
struct PositionSlider: View {
    var value: Double?
    var leftLabel: String
    var rightLabel: String
    var enabled: Bool
    var onDragging: (Bool) -> Void
    var onChange: (Double) -> Void

    var body: some View {
        VStack(spacing: 2) {
            Slider(value: Binding(get: { value ?? 0.5 }, set: { onChange($0) }), in: 0...1,
                   onEditingChanged: { editing in onDragging(editing) })
            .disabled(!enabled || value == nil)
            HStack {
                Text(leftLabel)
                Spacer()
                Text(value.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                    .monospacedDigit()
                Spacer()
                Text(rightLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
