import SwiftUI

/// Spring-loaded slider for zoom and focus. Reports -1...1 and returns to 0 when released.
struct RockerView: View {
    let leftLabel: String
    let rightLabel: String
    var onChange: (Double) -> Void
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let knobWidth: CGFloat = 44
            let travel = max((width - knobWidth) / 2, 1)
            ZStack {
                Capsule().fill(Color.secondary.opacity(0.12))
                HStack {
                    Text(leftLabel)
                    Spacer()
                    Text(rightLabel)
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: knobWidth)
                    .padding(.vertical, 3)
                    .offset(x: offset)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(value.location.x - width / 2, -travel), travel)
                        offset = x
                        onChange(x / travel)
                    }
                    .onEnded { _ in
                        withAnimation(.spring(duration: 0.2)) { offset = 0 }
                        onChange(0)
                    }
            )
        }
        .frame(height: 34)
    }
}
