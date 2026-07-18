import SwiftUI
import Photos

/// A square thumbnail for a single asset. Loads asynchronously from `PhotoImageService`,
/// shows a subtle placeholder while loading, and reloads if the asset changes. Videos get
/// a small badge with their duration.
struct AssetThumbnailView: View {
    let asset: PHAsset
    var side: CGFloat = 72

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(ICColor.cardBackground)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(ICColor.secondaryText)
                    )
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if asset.mediaType == .video {
                Text(ICFormat.duration(asset.duration))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(4)
            }
        }
        .task(id: asset.localIdentifier) {
            image = await PhotoImageService.shared.thumbnail(for: asset,
                                                             side: side,
                                                             scale: displayScale)
        }
        .accessibilityHidden(true) // decorative in the preview grid; described by its container
    }
}
