import Foundation
import Photos

/// Runs the detection strategies over the library, off the main thread.
///
/// An `actor` so heavy work stays off the main thread. Scanning runs in two passes:
///
/// 1. **Quick pass** — metadata only (screenshots, large videos). Walks the library in
///    batches, yielding between them so progress flows and cancellation is honoured.
/// 2. **Sharpness pass** — loads a small copy of each photo to measure blur. Much slower,
///    so it runs with bounded concurrency and reports progress frequently.
///
/// Duplicate detection (M4) will slot in as a third pass over the same eligible photos.
actor DetectionCoordinator {

    private let fetcher = PhotoLibraryFetcher()
    private let cache = ScanCacheStore.shared

    /// Scans the library and returns everything worth reviewing.
    ///
    /// - Parameters:
    ///   - includeICloudPhotos: when true, the sharpness pass downloads iCloud-only originals
    ///     instead of skipping them. Far slower and data-hungry — only from a user opt-in.
    ///   - onProgress: called periodically from a background context; callers must hop to the
    ///     main actor before touching UI state.
    /// - Throws: `CancellationError` if the surrounding task is cancelled.
    func scan(includeICloudPhotos: Bool = false,
              onProgress: @escaping @Sendable (ScanProgress) -> Void) async throws -> ScanResults {
        let assets = fetcher.fetchAllAssets()
        let total = assets.count

        onProgress(ScanProgress(phase: .quickChecks, scanned: 0, total: total))
        guard total > 0 else { return .empty }

        var candidates: [Candidate] = []
        /// Photos eligible for the pixel-level pass, collected during the quick pass so we
        /// only walk the library once.
        var photosForSharpness: [PHAsset] = []
        /// Every photo is a duplicate candidate — including screenshots, which are commonly
        /// duplicated. Selection is keyed by identifier, so appearing in two categories can
        /// never delete something twice.
        var photosForDuplicates: [PHAsset] = []
        var scanned = 0

        // MARK: Pass 1 — cheap metadata checks

        while scanned < total {
            try Task.checkCancellation()

            let end = min(scanned + DetectionThresholds.scanBatchSize, total)
            for index in scanned..<end {
                let asset = assets.object(at: index)

                if asset.mediaType == .image {
                    photosForDuplicates.append(asset)
                }

                if let screenshot = ScreenshotDetector.candidate(for: asset) {
                    candidates.append(screenshot)
                    continue    // a screenshot doesn't also need a blur check
                }
                if let largeVideo = LargeVideoDetector.candidate(for: asset) {
                    candidates.append(largeVideo)
                    continue
                }
                if asset.mediaType == .image {
                    photosForSharpness.append(asset)
                }
            }
            scanned = end

            onProgress(ScanProgress(phase: .quickChecks, scanned: scanned, total: total))
            await Task.yield()
        }

        // MARK: Pass 2 — sharpness

        let sharpnessPass = try await findBlurryPhotos(in: photosForSharpness,
                                                       includeICloudPhotos: includeICloudPhotos,
                                                       onProgress: onProgress)
        candidates.append(contentsOf: sharpnessPass.blurry)

        // MARK: Pass 3 — duplicates

        let duplicatePass = try await DuplicateDetector.findGroups(
            in: photosForDuplicates,
            allowsICloudDownload: includeICloudPhotos,
            cache: cache
        ) { processed, stageTotal, detail in
            onProgress(ScanProgress(phase: .duplicates,
                                    scanned: processed,
                                    total: stageTotal,
                                    detail: detail,
                                    includesICloudPhotos: includeICloudPhotos))
        }
        candidates.append(contentsOf: duplicatePass.groups.flatMap(\.extras))

        // Drop cache rows for assets that have left the library, so deleted photos don't keep
        // paying rent. Done after the passes so a cancelled scan never prunes on partial data.
        //
        // **Skipped under Limited Access**, where the fetch only ever returns the photos the
        // user has shared. Pruning to that subset would discard perfectly good measurements for
        // everything else, and re-measure them the moment the shared set changes — the cache
        // would thrash on exactly the flow that's most awkward to sit through. Costs some stale
        // rows instead, which `prune` clears on the next full-access scan.
        var pruned = 0
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) != .limited {
            let liveIdentifiers = Set(photosForDuplicates.map(\.localIdentifier))
                .union(photosForSharpness.map(\.localIdentifier))
            pruned = await cache.prune(keeping: liveIdentifiers)
        }

        #if DEBUG
        let cacheCounts = await cache.counts()
        let cacheBytes = await cache.sizeOnDisk()
        #endif

        #if DEBUG
        // Tuning aid: tells us whether a small blurry list means "library is sharp" or
        // "we couldn't actually look at most of it". Debug-only, never ships.
        print("""
        [iClean] scan complete
          library items ............ \(total)
          eligible for blur check .. \(photosForSharpness.count)
          actually measured ........ \(sharpnessPass.checked)
          skipped, no image ........ \(sharpnessPass.couldNotLoad)
          skipped, image too small . \(sharpnessPass.deliveredTooSmall)
          skipped, Portrait mode ... \(sharpnessPass.notEligible)
          reused from cache ........ \(sharpnessPass.reusedFromCache)
          blurry found ............. \(sharpnessPass.blurry.count)
          blur threshold ........... \(DetectionThresholds.blurVariance)
        \(Self.scoreDistribution(sharpnessPass.scores))
          -- duplicates --
          fingerprinted ............ \(duplicatePass.fingerprinted)
          reused from cache ........ \(duplicatePass.reusedFromCache)
          could not fingerprint .... \(duplicatePass.couldNotLoad)
          groups found ............. \(duplicatePass.groups.count)
          extra copies total ....... \(duplicatePass.groups.flatMap(\.extras).count)
          of those, pre-ticked ..... \(duplicatePass.groups.flatMap(\.extras).filter(\.preselect).count)
          auto-tick threshold ...... \(DetectionThresholds.duplicateAutoTickMaxDistance)
          distance threshold ....... \(DetectionThresholds.duplicateMaxDistance)
        \(Self.matchDistanceSummary(duplicatePass.matchDistances))
          -- scan cache --
          blur scores stored ....... \(cacheCounts.blur)
          descriptors stored ....... \(cacheCounts.descriptors)
          rows pruned this scan .... \(pruned)
          on disk .................. \(ICFormat.fileSize(cacheBytes))
        """)
        #endif

        return ScanResults(candidates: candidates,
                           scannedCount: total,
                           photosCheckedForBlur: sharpnessPass.checked,
                           photosUncheckedForBlur: sharpnessPass.unchecked,
                           duplicateGroups: duplicatePass.groups)
    }

    /// Blurry photos found, plus how much of the library we were actually able to examine.
    private struct SharpnessPass {
        var blurry: [Candidate] = []
        var checked = 0
        var couldNotLoad = 0
        var deliveredTooSmall = 0
        /// Portrait-mode shots, deliberately excluded from blur analysis.
        var notEligible = 0
        /// Every sharpness score we measured, for threshold tuning (Debug only).
        var scores: [Float] = []
        /// Scores answered from the cache rather than by decoding an image.
        var reusedFromCache = 0

        var unchecked: Int { couldNotLoad + deliveredTooSmall }
    }

    /// One measured photo, paired with the key its score is cached under.
    ///
    /// The outcome alone isn't enough: `.sharp` carries only a score, so the asset it belongs
    /// to has to travel with it to be storable.
    private struct BlurMeasurement {
        let key: ScanCacheKey
        let outcome: BlurDetector.Outcome
        /// Seconds this one photo spent in flight. Summed per outcome to decompose the pass —
        /// see the Debug block in `findBlurryPhotos`.
        let seconds: Double
    }

    #if DEBUG
    /// Buckets the measured sharpness scores so we can see where a threshold would land —
    /// e.g. how many photos sit between the current cut-off and a looser one.
    private static func scoreDistribution(_ scores: [Float]) -> String {
        guard !scores.isEmpty else { return "  (no scores measured)" }
        let bounds: [Float] = [10, 25, 50, 100, 200, 400, 800]
        var lines = ["  sharpness distribution (cumulative ≤):"]
        for bound in bounds {
            let count = scores.filter { $0 <= bound }.count
            let percent = Double(count) / Double(scores.count) * 100
            lines.append(String(format: "    ≤ %6.0f  %6d  (%.1f%%)", bound, count, percent))
        }
        let sorted = scores.sorted()
        let median = sorted[sorted.count / 2]
        lines.append(String(format: "    median %.0f · min %.0f · max %.0f",
                            median, sorted.first ?? 0, sorted.last ?? 0))
        return lines.joined(separator: "\n")
    }
    #endif

    #if DEBUG
    /// How close the accepted duplicate matches actually were. If these cluster near the
    /// threshold rather than near zero, the threshold is doing risky work and should tighten.
    private static func matchDistanceSummary(_ distances: [Float]) -> String {
        guard !distances.isEmpty else { return "  (no duplicate matches)" }
        let sorted = distances.sorted()
        let buckets: [Float] = [0.01, 0.05, 0.10, 0.15]
        var lines = ["  match distances (cumulative ≤):"]
        for bucket in buckets {
            let count = sorted.filter { $0 <= bucket }.count
            lines.append(String(format: "    ≤ %.2f  %6d", bucket, count))
        }
        lines.append(String(format: "    median %.4f · max %.4f",
                            sorted[sorted.count / 2], sorted.last ?? 0))
        return lines.joined(separator: "\n")
    }
    #endif

    /// Measures sharpness across `photos` with a bounded number of concurrent image loads.
    ///
    /// A sliding window keeps `blurMaxConcurrent` analyses in flight: each time one
    /// finishes we start the next, rather than queuing thousands of tasks at once.
    private func findBlurryPhotos(in photos: [PHAsset],
                                  includeICloudPhotos: Bool,
                                  onProgress: @escaping @Sendable (ScanProgress) -> Void)
    async throws -> SharpnessPass {

        let total = photos.count
        guard total > 0 else { return SharpnessPass() }

        func progress(_ scanned: Int) -> ScanProgress {
            ScanProgress(phase: .sharpness,
                         scanned: scanned,
                         total: total,
                         includesICloudPhotos: includeICloudPhotos)
        }
        onProgress(progress(0))

        var pass = SharpnessPass()
        var processed = 0
        #if DEBUG
        // Matches the fingerprinting heartbeat, so the two passes can be compared directly.
        let startedAt = Date()
        var secondsMeasuring = 0.0, secondsFailing = 0.0
        #endif

        // MARK: Metadata-only skips
        //
        // Portrait shots and the like cost nothing to identify and can never have a cached
        // score, so they're settled before the cache is touched.
        var eligible: [PHAsset] = []
        eligible.reserveCapacity(total)
        for asset in photos {
            if BlurDetector.isEligible(asset) {
                eligible.append(asset)
            } else {
                pass.notEligible += 1
                processed += 1
            }
        }

        // MARK: Cached scores
        //
        // A score is the expensive half (an 800px decode); the verdict is a comparison. So a
        // cache hit skips the decode entirely and still re-classifies against the *current*
        // `blurVariance` — retuning the threshold never costs a re-measure.
        let cachedScores = await cache.blurScores(for: eligible.map(ScanCacheKey.init))

        var needsMeasuring: [PHAsset] = []
        needsMeasuring.reserveCapacity(eligible.count - cachedScores.count)
        for asset in eligible {
            guard let score = cachedScores[asset.localIdentifier] else {
                needsMeasuring.append(asset)
                continue
            }
            record(BlurDetector.outcome(for: asset, sharpness: score), into: &pass)
            pass.reusedFromCache += 1
            processed += 1
        }
        onProgress(progress(processed))

        #if DEBUG
        print("""
        [iClean] blur cache: \(pass.reusedFromCache) reused · \(needsMeasuring.count) to measure \
        · \(pass.notEligible) ineligible
        """)
        #endif

        // MARK: Measure the rest

        var fresh: [(key: ScanCacheKey, score: Float)] = []
        fresh.reserveCapacity(needsMeasuring.count)

        try await withThrowingTaskGroup(of: BlurMeasurement.self) { group in
            var next = needsMeasuring.makeIterator()

            func measure(_ asset: PHAsset) -> @Sendable () async -> BlurMeasurement {
                let key = ScanCacheKey(asset)
                return {
                    let start = Date()
                    let outcome = await BlurDetector.analyse(asset: asset,
                                                             allowsICloudDownload: includeICloudPhotos)
                    return BlurMeasurement(key: key,
                                           outcome: outcome,
                                           seconds: Date().timeIntervalSince(start))
                }
            }

            // Prime the window.
            for _ in 0..<min(DetectionThresholds.blurMaxConcurrent, needsMeasuring.count) {
                guard let asset = next.next() else { break }
                group.addTask(operation: measure(asset))
            }

            while let measurement = try await group.next() {
                try Task.checkCancellation()

                processed += 1
                record(measurement.outcome, into: &pass)

                // Successes only: a failed load must never be cached. The set of photos with no
                // local 800px rendition changes as iOS evicts and restores originals, so
                // remembering a failure would permanently blind us to a photo that later
                // becomes checkable.
                if let score = measurement.outcome.sharpnessScore {
                    fresh.append((measurement.key, score))
                }

                #if DEBUG
                switch measurement.outcome {
                case .blurry, .sharp: secondsMeasuring += measurement.seconds
                case .couldNotLoad, .deliveredTooSmall: secondsFailing += measurement.seconds
                case .notEligible: break
                }
                #endif

                if processed % DetectionThresholds.blurProgressInterval == 0 || processed == total {
                    onProgress(progress(processed))
                }
                #if DEBUG
                if processed % 250 == 0 || processed == total {
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let rate = elapsed > 0 ? Double(processed) / elapsed : 0
                    print(String(format: "[iClean] blur pass %d/%d · %.0fs elapsed · %.1f/sec",
                                 processed, total, elapsed, rate))
                }
                #endif

                // Top the window back up.
                if let asset = next.next() {
                    group.addTask(operation: measure(asset))
                }
            }
        }

        await cache.storeBlurScores(fresh)

        #if DEBUG
        // Decomposes the pass: how much of it is real measurement (cacheable) versus failed
        // loads (re-attempted every scan by design). These are summed in-flight times across
        // `blurMaxConcurrent` workers, so they exceed wall clock — the ratio is the point.
        print(String(format: """
        [iClean] blur cost split · measured %d in %.0fs (%.0fms each) \
        · failed %d in %.0fs (%.0fms each) · cached %d
        """,
        pass.checked, secondsMeasuring, pass.checked > 0 ? secondsMeasuring / Double(pass.checked) * 1000 : 0,
        pass.unchecked, secondsFailing, pass.unchecked > 0 ? secondsFailing / Double(pass.unchecked) * 1000 : 0,
        pass.reusedFromCache))
        #endif

        return pass
    }

    /// Folds one outcome into the running totals. Shared by the cached and measured paths so
    /// they can't drift apart.
    private func record(_ outcome: BlurDetector.Outcome, into pass: inout SharpnessPass) {
        switch outcome {
        case .blurry(let candidate):
            pass.blurry.append(candidate)
            pass.checked += 1
            #if DEBUG
            if let score = candidate.detectionScore { pass.scores.append(score) }
            #endif
        case .sharp(let score):
            pass.checked += 1
            #if DEBUG
            pass.scores.append(score)
            #endif
        case .couldNotLoad:
            pass.couldNotLoad += 1
        case .deliveredTooSmall:
            pass.deliveredTooSmall += 1
        case .notEligible:
            pass.notEligible += 1   // Portrait shots; not a coverage gap
        }
    }
}
