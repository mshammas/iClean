import SwiftUI
import Photos
import AVKit

/// Full-screen look at a single item before deciding on it.
///
/// Photos can be pinched or double-tapped to zoom; videos can be played, since you can't
/// judge a large video from a still. The tick control is repeated here so the decision can
/// be made while actually looking at the item, and "Done" is always visible.
struct FullScreenAssetView: View {
    let candidate: Candidate
    /// Observed directly (rather than passed as a snapshot `Bool`) so the tick button
    /// updates immediately when tapped from inside this screen.
    @ObservedObject var viewModel: CleanupViewModel

    @Environment(\.dismiss) private var dismiss

    private var isSelected: Bool { viewModel.selection.isSelected(candidate.id) }

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isLoading = true

    // Zoom / pan state. `@GestureState` resets automatically if a gesture is interrupted.
    @State private var scale: CGFloat = 1
    @GestureState private var pinchScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero

    private var isVideo: Bool { candidate.asset.mediaType == .video }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            content

            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .task(id: candidate.id) { await load() }
        .onDisappear { player?.pause() }
        .statusBarHidden()
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if isVideo, let player {
            VideoPlayer(player: player)
                .ignoresSafeArea()
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale * pinchScale)
                .offset(x: offset.width + dragTranslation.width,
                        y: offset.height + dragTranslation.height)
                .gesture(zoomGesture)
                .simultaneousGesture(panGesture)
                .onTapGesture(count: 2, perform: toggleZoom)
                .accessibilityLabel("Full screen photo. \(candidate.reason)")
        } else if isLoading {
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
                Text("Loading…")
                    .icStyle(.body)
                    .foregroundStyle(.white)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                Text("This item couldn't be loaded.")
                    .icStyle(.body)
            }
            .foregroundStyle(.white)
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Text("Done")
                    .icStyle(.button)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 50)
                    .background(.black.opacity(0.55), in: Capsule())
            }
            .accessibilityLabel("Done. Close full screen view")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Text(candidate.reason)
                .icStyle(.bodyBold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            ICButton(title: isSelected ? "Keep This One" : "Tick for Deletion",
                     systemImage: isSelected ? "arrow.uturn.backward" : "trash",
                     role: isSelected ? .secondary : .destructive) {
                viewModel.toggle(candidate)
            }
        }
        .padding(20)
        .background(.black.opacity(0.55))
    }

    // MARK: Gestures

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in state = value }
            .onEnded { value in
                scale = min(max(scale * value, 1), 5)
                if scale == 1 { offset = .zero }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                // Only pan when zoomed in; otherwise the image shouldn't move at all.
                state = scale > 1 ? value.translation : .zero
            }
            .onEnded { value in
                guard scale > 1 else { return }
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    private func toggleZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if scale > 1 {
                scale = 1
                offset = .zero
            } else {
                scale = 2.5
            }
        }
    }

    // MARK: Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        if isVideo {
            if let item = await PhotoImageService.shared.playerItem(for: candidate.asset) {
                player = AVPlayer(playerItem: item)
            }
        } else {
            image = await PhotoImageService.shared.fullScreenImage(for: candidate.asset)
        }
    }
}
