import SwiftUI
import Photos
import AVKit

/// One item the full-screen viewer can show.
///
/// Two kinds: a deletion **candidate** (which gets a tick control), and the **keeper** of a
/// duplicate group, which isn't deletable from here but still needs to be viewable — you
/// can't confirm a group really is duplicates without looking at the copy being kept.
struct FullScreenTarget: Identifiable {
    let asset: PHAsset
    let caption: String
    /// Present when the item can be ticked for deletion; `nil` for a group's keeper.
    let candidate: Candidate?

    var id: String { asset.localIdentifier }

    init(candidate: Candidate) {
        self.asset = candidate.asset
        self.caption = candidate.reason
        self.candidate = candidate
    }

    init(keeper asset: PHAsset, caption: String) {
        self.asset = asset
        self.caption = caption
        self.candidate = nil
    }
}

/// What to open in the viewer: a set of items, and which one to start on.
///
/// For a duplicate group this is the keeper followed by its copies, so the user can swipe
/// between them and judge the deletion by direct comparison rather than memory.
struct FullScreenSelection: Identifiable {
    /// Used when the items are fixed (a single item from a non-duplicate category).
    let fixedTargets: [FullScreenTarget]
    /// When set, the pages are derived from this group *live*, so choosing a different copy
    /// to keep updates the viewer in place instead of leaving stale captions behind.
    let groupID: UUID?
    let startID: String

    var id: String { startID }

    init(single target: FullScreenTarget) {
        self.fixedTargets = [target]
        self.groupID = nil
        self.startID = target.id
    }

    init(groupID: UUID, startID: String) {
        self.fixedTargets = []
        self.groupID = groupID
        self.startID = startID
    }
}

/// Full-screen viewer, laid out as a **column**: controls above and below, photo in between.
///
/// The controls deliberately do not float over the image — with two action buttons and a
/// caption they'd cover a good part of what you're trying to judge. Giving the photo its own
/// region means it's always fully visible.
struct FullScreenAssetView: View {
    let selection: FullScreenSelection
    @ObservedObject var viewModel: CleanupViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: String

    init(selection: FullScreenSelection, viewModel: CleanupViewModel) {
        self.selection = selection
        self.viewModel = viewModel
        _currentID = State(initialValue: selection.startID)
    }

    /// The pages to show. For a duplicate group this is rebuilt from the view model on every
    /// update — keeper first, then its copies — so a change of keeper is reflected at once.
    private var targets: [FullScreenTarget] {
        guard let groupID = selection.groupID,
              let group = viewModel.duplicateGroups.first(where: { $0.id == groupID }) else {
            return selection.fixedTargets
        }
        return [FullScreenTarget(keeper: group.keeper,
                                 caption: ICFormat.fileSize(group.keeperBytes))]
            + group.extras.map(FullScreenTarget.init(candidate:))
    }

    private var current: FullScreenTarget? { targets.first { $0.id == currentID } }
    private var currentIndex: Int { targets.firstIndex { $0.id == currentID } ?? 0 }
    private var canSwipe: Bool { targets.count > 1 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                pager
                bottomBar
            }
        }
        .statusBarHidden()
    }

    // MARK: Pieces

    private var pager: some View {
        TabView(selection: $currentID) {
            ForEach(targets) { target in
                FullScreenAssetPage(target: target)
                    .tag(target.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            if canSwipe {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(currentIndex + 1) of \(targets.count)")
                        .icStyle(.bodyBold)
                        .foregroundStyle(.white)
                    // The hint lives up here rather than in the bottom bar, where it would
                    // cost a whole row of the space the photo needs.
                    Text("Swipe to compare")
                        .icStyle(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Photo \(currentIndex + 1) of \(targets.count). Swipe to compare.")
            }

            Spacer()

            Button { dismiss() } label: {
                Text("Done")
                    .icStyle(.button)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 50)
                    .background(.white.opacity(0.18), in: Capsule())
            }
            .accessibilityLabel("Done. Close full screen view")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let target = current {
            VStack(spacing: 10) {
                Text(target.caption)
                    .icStyle(.bodyBold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let candidate = target.candidate {
                    let isTicked = viewModel.selection.isSelected(candidate.id)

                    // Deliberately *not* worded "Keep This One": that read almost identically
                    // to "Keep This One Instead" below, and the two do very different things.
                    ICButton(title: isTicked ? "Don't Delete This One" : "Tick for Deletion",
                             systemImage: isTicked ? "arrow.uturn.backward" : "trash",
                             role: isTicked ? .secondary : .destructive) {
                        viewModel.toggle(candidate)
                    }

                    // Only inside a duplicate group: which copy is kept is a suggestion.
                    if candidate.duplicateGroupID != nil {
                        ICButton(title: "Keep This One Instead",
                                 systemImage: "checkmark.seal",
                                 role: .secondary) {
                            viewModel.makeKeeper(candidate)
                        }
                    }
                } else {
                    Label("This copy is being kept", systemImage: "checkmark.seal.fill")
                        .icStyle(.bodyBold)
                        .foregroundStyle(ICColor.success)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .animation(.none, value: currentID)   // controls shouldn't cross-fade while swiping
        }
    }
}

/// A single page: loads and displays one asset, with its own zoom state.
private struct FullScreenAssetPage: View {
    let target: FullScreenTarget

    @Environment(\.displayScale) private var displayScale

    /// Shown immediately from the thumbnail cache so a swipe never lands on a blank screen;
    /// replaced by `fullImage` once the larger version arrives.
    @State private var previewImage: UIImage?
    @State private var fullImage: UIImage?
    @State private var player: AVPlayer?
    @State private var loadFailed = false

    // Zoom / pan. `@GestureState` resets automatically if a gesture is interrupted.
    @State private var scale: CGFloat = 1
    @GestureState private var pinchScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero

    private var isVideo: Bool { target.asset.mediaType == .video }
    private var displayed: UIImage? { fullImage ?? previewImage }

    var body: some View {
        content
            .task(id: target.id) { await load() }
            .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var content: some View {
        if isVideo, let player {
            VideoPlayer(player: player)
        } else if let displayed {
            zoomableImage(displayed)
        } else if loadFailed {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .icIconSize(48)
                Text("This item couldn't be loaded.")
                    .icStyle(.body)
            }
            .foregroundStyle(.white)
        } else {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
        }
    }

    /// Pan is applied as a **high-priority** gesture only while zoomed in. At normal zoom the
    /// drag must reach the pager so swiping between copies works; once zoomed, dragging
    /// should move the image instead of flicking to the next photo.
    @ViewBuilder
    private func zoomableImage(_ image: UIImage) -> some View {
        let base = Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale * pinchScale)
            .offset(x: offset.width + dragTranslation.width,
                    y: offset.height + dragTranslation.height)
            .gesture(zoomGesture)
            .onTapGesture(count: 2, perform: toggleZoom)
            .accessibilityLabel("Full screen photo. \(target.caption)")

        if scale > 1 {
            base.highPriorityGesture(panGesture)
        } else {
            base
        }
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
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onEnded { value in
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
        guard !isVideo else {
            if let item = await PhotoImageService.shared.playerItem(for: target.asset) {
                player = AVPlayer(playerItem: item)
            } else {
                loadFailed = true
            }
            return
        }

        // Cheap cached version first — this is what makes swiping feel immediate.
        if fullImage == nil {
            previewImage = await PhotoImageService.shared.thumbnail(for: target.asset,
                                                                    side: 500,
                                                                    scale: displayScale)
        }
        let full = await PhotoImageService.shared.fullScreenImage(for: target.asset)
        if let full {
            fullImage = full
        } else if previewImage == nil {
            loadFailed = true
        }
    }
}
