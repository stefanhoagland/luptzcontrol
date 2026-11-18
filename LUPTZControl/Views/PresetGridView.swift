import SwiftUI

struct PresetGridView: View {
    var highlighted: Int?
    var storeMode: Bool
    var count = 24
    var onTap: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(1...count, id: \.self) { number in
                Button { onTap(number) } label: {
                    Text("\(number)")
                        .font(.body.monospacedDigit().weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(background(for: number), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(number == highlighted && !storeMode ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func background(for number: Int) -> Color {
        if storeMode { return Color.orange.opacity(0.25) }
        return number == highlighted ? Color.accentColor : Color.secondary.opacity(0.15)
    }
}
