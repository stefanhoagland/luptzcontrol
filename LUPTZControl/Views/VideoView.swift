import SwiftUI

struct VideoView: View {
    @ObservedObject var feed: VideoFeed
    var tallyOn: Bool

    var body: some View {
        ZStack {
            if let image = feed.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
            }
            if !feed.status.isEmpty {
                VStack(spacing: 10) {
                    if feed.status.hasSuffix("…") { ProgressView().controlSize(.small) }
                    Text(feed.status)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .overlay {
            if tallyOn {
                Rectangle().strokeBorder(Color.red, lineWidth: 5)
            }
        }
    }
}
