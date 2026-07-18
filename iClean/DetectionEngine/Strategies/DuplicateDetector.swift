import UIKit
import Photos
import Vision

/// Finds near-identical copies using Vision feature prints.
///
/// Three stages:
/// 1. **Fingerprint** every photo (`VNGenerateImageFeaturePrintRequest`) on a small copy.
/// 2. **Compare** only plausible pairs — same aspect ratio, taken close together in time.
///    Comparing everything against everything is O(n²) and hopeless at 12,000+ photos.
/// 3. **Cluster** matches into groups and pick which copy to keep.
///
/// This is the one detector whose results are **pre-ticked for deletion**, so it errs hard
/// toward missing duplicates rather than inventing them: a strict distance threshold (see
/// `DetectionThresholds.duplicateMaxDistance`) and favourites are never pre-ticked.
enum DuplicateDetector {

    /// One photo, fingerprinted and ready to compare.
    private struct Fingerprint {
        let asset: PHAsset
        let print: VNFeaturePrintObservation
        let creationDate: Date
        let aspectRatio: Double
        let pixelCount: Int
        let bytes: Int64
        var isFavorite: Bool { asset.isFavorite }
    }

    struct Result {
        var groups: [DuplicateGroup] = []
        var fingerprinted = 0
        var couldNotLoad = 0
        /// Distances of accepted matches, for calibration in Debug builds.
        var matchDistances: [Float] = []
    }

    // MARK: Entry point

    /// - Parameter onProgress: `(processed, total, sub-step wording)`.
    static func findGroups(in assets: [PHAsset],
                           allowsICloudDownload: Bool,
                           onProgress: @Sendable @escaping (Int, Int, String) -> Void) async throws -> Result {
        var result = Result()
        guard !assets.isEmpty else { return result }

        // Publish immediately: without this the UI sits on the previous pass's final state
        // for as long as the first batch takes, which reads as a freeze.
        onProgress(0, assets.count, "looking at each photo")

        let fingerprints = try await fingerprintAll(assets,
                                                    allowsICloudDownload: allowsICloudDownload,
                                                    couldNotLoad: &result.couldNotLoad,
                                                    onProgress: onProgress)
        result.fingerprinted = fingerprints.count
        guard fingerprints.count > 1 else { return result }

        let clusters = try await cluster(fingerprints,
                                         matchDistances: &result.matchDistances,
                                         onProgress: onProgress)
        result.groups = clusters.compactMap(makeGroup)
        return result
    }

    // MARK: 1 — Fingerprinting

    private static func fingerprintAll(_ assets: [PHAsset],
                                       allowsICloudDownload: Bool,
                                       couldNotLoad: inout Int,
                                       onProgress: @Sendable @escaping (Int, Int, String) -> Void)
    async throws -> [Fingerprint] {

        let total = assets.count
        var fingerprints: [Fingerprint] = []
        var processed = 0
        var failed = 0
        let startedAt = Date()

        try await withThrowingTaskGroup(of: Fingerprint?.self) { group in
            var next = assets.makeIterator()

            for _ in 0..<min(DetectionThresholds.duplicateMaxConcurrent, total) {
                guard let asset = next.next() else { break }
                group.addTask { await fingerprint(asset, allowsICloudDownload: allowsICloudDownload) }
            }

            while let outcome = try await group.next() {
                try Task.checkCancellation()
                processed += 1
                if let outcome {
                    fingerprints.append(outcome)
                } else {
                    failed += 1
                }
                if processed % DetectionThresholds.duplicateProgressInterval == 0 || processed == total {
                    onProgress(processed, total, "looking at each photo")
                }
                #if DEBUG
                // Live heartbeat: distinguishes "slow" from "hung" without guesswork.
                if processed % 250 == 0 || processed == total {
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let rate = elapsed > 0 ? Double(processed) / elapsed : 0
                    print(String(format: "[iClean] fingerprinting %d/%d · %.0fs elapsed · %.1f/sec",
                                 processed, total, elapsed, rate))
                }
                #endif
                if let asset = next.next() {
                    group.addTask { await fingerprint(asset, allowsICloudDownload: allowsICloudDownload) }
                }
            }
        }

        couldNotLoad = failed
        return fingerprints
    }

    /// Vision work runs here rather than on Swift's cooperative thread pool.
    ///
    /// `VNImageRequestHandler.perform` is **synchronous and blocking**. Running several of
    /// them directly inside async tasks occupies every cooperative thread, and the PhotoKit
    /// continuations waiting to resume then have nowhere to run — the scan stalls with no
    /// progress at all. Handing the blocking call to a dedicated queue keeps the pool free.
    private static let visionQueue = DispatchQueue(label: "com.iclean.vision",
                                                   qos: .userInitiated,
                                                   attributes: .concurrent)

    private static func featurePrint(for cgImage: CGImage) async -> VNFeaturePrintObservation? {
        await withCheckedContinuation { continuation in
            visionQueue.async {
                let request = VNGenerateImageFeaturePrintRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    continuation.resume(returning: request.results?.first as? VNFeaturePrintObservation)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func fingerprint(_ asset: PHAsset, allowsICloudDownload: Bool) async -> Fingerprint? {
        let dimension = CGFloat(DetectionThresholds.duplicateAnalysisDimension)
        guard let image = await PhotoImageService.shared.analysisImage(
            for: asset,
            maxDimension: dimension,
            allowsNetworkAccess: allowsICloudDownload
        ), let cgImage = image.cgImage else { return nil }

        guard let observation = await featurePrint(for: cgImage) else { return nil }

        let height = max(asset.pixelHeight, 1)
        return Fingerprint(asset: asset,
                           print: observation,
                           creationDate: asset.creationDate ?? .distantPast,
                           aspectRatio: Double(asset.pixelWidth) / Double(height),
                           pixelCount: asset.pixelWidth * asset.pixelHeight,
                           bytes: AssetResourceInfo.estimatedFileSize(for: asset))
    }

    // MARK: 2 & 3 — Compare and cluster

    /// Groups matching fingerprints using union-find over pairs that pass both the cheap
    /// pre-filters (aspect ratio, time proximity) and the distance threshold.
    ///
    /// Reports progress and honours cancellation throughout: this stage can run for a long
    /// time on a large library, and without either it looks like the app has frozen and
    /// "Stop" does nothing.
    private static func cluster(_ fingerprints: [Fingerprint],
                                matchDistances: inout [Float],
                                onProgress: @Sendable @escaping (Int, Int, String) -> Void)
    async throws -> [[Fingerprint]] {

        let sorted = fingerprints.sorted { $0.creationDate < $1.creationDate }
        let total = sorted.count
        var union = UnionFind(count: total)

        onProgress(0, total, "comparing photos")

        #if DEBUG
        let comparisonStart = Date()
        #endif

        for i in 0..<total {
            if i % 50 == 0 {
                try Task.checkCancellation()
                onProgress(i, total, "comparing photos")
                await Task.yield()
                #if DEBUG
                if i % 1000 == 0 {
                    print(String(format: "[iClean] comparing %d/%d · %.0fs elapsed",
                                 i, total, Date().timeIntervalSince(comparisonStart)))
                }
                #endif
            }

            let a = sorted[i]
            var j = i + 1
            var compared = 0
            while j < total, compared < DetectionThresholds.duplicateMaxNeighbourComparisons {
                let b = sorted[j]
                // Sorted by date, so once we're past the window nothing later can match.
                guard b.creationDate.timeIntervalSince(a.creationDate)
                        <= DetectionThresholds.duplicateTimeWindow else { break }

                if abs(a.aspectRatio - b.aspectRatio) <= DetectionThresholds.duplicateAspectTolerance {
                    compared += 1
                    if let distance = distance(a.print, b.print),
                       distance <= DetectionThresholds.duplicateMaxDistance {
                        union.union(i, j)
                        matchDistances.append(distance)
                    }
                }
                j += 1
            }
        }

        onProgress(total, total, "comparing photos")

        var buckets: [Int: [Fingerprint]] = [:]
        for index in 0..<total {
            buckets[union.find(index), default: []].append(sorted[index])
        }
        return buckets.values.filter { $0.count > 1 }
    }

    private static func distance(_ a: VNFeaturePrintObservation,
                                 _ b: VNFeaturePrintObservation) -> Float? {
        var value = Float(0)
        do {
            try a.computeDistance(&value, to: b)
            return value
        } catch {
            return nil
        }
    }

    /// Chooses which copy to keep and builds the group.
    ///
    /// Priority: **a favourite first** (an explicit signal the user wants that one), then
    /// highest resolution, then largest file, then oldest — the original rather than a
    /// re-save. Favourites among the extras are never pre-ticked.
    ///
    /// **Every extra is re-checked against the keeper itself.** Clustering links pairs
    /// transitively, so A≈B and B≈C puts all three in one cluster even when A and C are not
    /// alike — in a burst where the scene drifts, that could chain genuinely different photos
    /// together and pre-tick one for deletion. Requiring each extra to be within the
    /// threshold *of the photo being kept* makes the group's claim literally true: every
    /// extra is a near-identical copy of the keeper. Members that fail are dropped.
    private static func makeGroup(_ members: [Fingerprint]) -> DuplicateGroup? {
        guard members.count > 1 else { return nil }

        let ranked = members.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            if lhs.pixelCount != rhs.pixelCount { return lhs.pixelCount > rhs.pixelCount }
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            return lhs.creationDate < rhs.creationDate
        }

        guard let keeper = ranked.first else { return nil }
        let groupID = UUID()

        // Keep each member's distance to the keeper: it decides both the wording and, more
        // importantly, whether we dare pre-tick it.
        let verified: [(member: Fingerprint, distance: Float)] = ranked.dropFirst().compactMap { member in
            guard let distance = distance(keeper.print, member.print),
                  distance <= DetectionThresholds.duplicateMaxDistance else { return nil }
            return (member, distance)
        }
        guard !verified.isEmpty else { return nil }

        let extras = verified.map { entry -> Candidate in
            let member = entry.member
            let isNearCertain = entry.distance <= DetectionThresholds.duplicateAutoTickMaxDistance
            let description = isNearCertain ? "Copy of the photo above" : "Looks like the same photo"
            let favouriteNote = member.isFavorite ? " · one of your favourites" : ""

            return Candidate(asset: member.asset,
                             category: .duplicates,
                             reason: "\(description)\(favouriteNote) · \(ICFormat.fileSize(member.bytes))",
                             estimatedBytes: member.bytes,
                             duplicateGroupID: groupID,
                             detectionScore: entry.distance,
                             // Pre-tick only near-certain copies, and never a favourite.
                             preselect: isNearCertain && !member.isFavorite)
        }

        return DuplicateGroup(id: groupID,
                              keeper: keeper.asset,
                              keeperReason: keeperReason(for: keeper),
                              keeperBytes: keeper.bytes,
                              extras: Array(extras))
    }

    private static func keeperReason(for keeper: Fingerprint) -> String {
        if keeper.isFavorite { return "Keeping this one — it's one of your favourites" }
        return "Keeping this one — it's the best quality"
    }
}

/// Minimal union-find for clustering matched pairs into groups.
private struct UnionFind {
    private var parent: [Int]

    init(count: Int) { parent = Array(0..<count) }

    mutating func find(_ index: Int) -> Int {
        var root = index
        while parent[root] != root { root = parent[root] }
        // Path compression.
        var current = index
        while parent[current] != root {
            let next = parent[current]
            parent[current] = root
            current = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a), rootB = find(b)
        if rootA != rootB { parent[rootB] = rootA }
    }
}
