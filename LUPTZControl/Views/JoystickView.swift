import SwiftUI

/// On-screen joystick. Reports x (right +) and y (up +), each -1...1, and springs back to center.
struct JoystickView: View {
    var onChange: (Double, Double) -> Void
    @State private var knob: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let knobSize = size * 0.3
            let travel = (size - knobSize) / 2
            ZStack {
                Circle().fill(Color.secondary.opacity(0.12))
                Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                Path { path in
                    path.move(to: CGPoint(x: size / 2, y: 12))
                    path.addLine(to: CGPoint(x: size / 2, y: size - 12))
                    path.move(to: CGPoint(x: 12, y: size / 2))
                    path.addLine(to: CGPoint(x: size - 12, y: size / 2))
                }
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(radius: 3)
                    .offset(knob)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        var dx = value.location.x - size / 2
                        var dy = value.location.y - size / 2
                        let distance = sqrt(dx * dx + dy * dy)
                        if distance > travel, distance > 0 {
                            dx *= travel / distance
                            dy *= travel / distance
                        }
                        knob = CGSize(width: dx, height: dy)
                        guard travel > 0 else { return }
                        onChange(dx / travel, -dy / travel)
                    }
                    .onEnded { _ in
                        withAnimation(.spring(duration: 0.2)) { knob = .zero }
                        onChange(0, 0)
                    }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
