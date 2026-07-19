import Foundation
import Vision
import CoreGraphics
import SQLite3

// Standalone test harness for the scan cache. See Tools/ScanCacheHarness/run.sh.
//
// This project has no test target, and `ScanCacheStore` is deliberately best-effort — no
// operation throws, so a bug there looks like "the cache never works" rather than a crash.
// That makes it exactly the code that must not be trusted just because it compiles.
//
// Runs on macOS against the real source files, so it tests what ships.

var failures = 0
func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    print((condition ? "  PASS  " : "  FAIL  ") + name + (condition || detail.isEmpty ? "" : " — \(detail)"))
    if !condition { failures += 1 }
}
func section(_ title: String) { print("\n── \(title) ──") }
func scratch() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("iclean-harness-\(UUID().uuidString)")
}

/// A descriptor of plausible shape. Values are snapped to fp16 because real Vision output is.
func syntheticDescriptor(_ seed: Int) -> FeatureDescriptor {
    var s = UInt64(bitPattern: Int64(seed &* 6364136223846793005 &+ 1))
    return FeatureDescriptor(values: (0..<768).map { _ in
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Float(Float16((Float(s >> 40) / Float(1 << 24)) - 0.5))
    })
}

/// A deterministic image. `jitter` nudges every channel, standing in for a re-encoded copy.
func image(_ seed: Int, jitter: Int = 0) -> CGImage {
    let w = 256, h = 256
    var px = [UInt8](repeating: 0, count: w * h * 4)
    var s = UInt64(bitPattern: Int64(seed &* 2654435761 &+ 31337))
    for i in 0..<(w * h) {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        var r = Int((s >> 33) & 0xFF), g = Int((s >> 21) & 0xFF), b = Int((s >> 11) & 0xFF)
        if jitter != 0 {
            r = min(255, max(0, r + jitter)); g = min(255, max(0, g + jitter)); b = min(255, max(0, b + jitter))
        }
        px[i * 4 + 0] = UInt8(r); px[i * 4 + 1] = UInt8(g); px[i * 4 + 2] = UInt8(b); px[i * 4 + 3] = 255
    }
    let provider = CGDataProvider(data: Data(px) as CFData)!
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                   space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

func realDescriptor(_ cg: CGImage) -> FeatureDescriptor {
    let request = VNGenerateImageFeaturePrintRequest()
    request.revision = DetectionThresholds.visionFeaturePrintRevision
    try! VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
    return FeatureDescriptor(request.results!.first!)!
}

// MARK: - 1. Store correctness

section("store correctness")
do {
    let root = scratch()
    var store = ScanCacheStore(directory: root)
    let a = ScanCacheKey(localIdentifier: "A", modifiedAt: 1000)
    let b = ScanCacheKey(localIdentifier: "B", modifiedAt: 2000)

    check("blur miss on empty store", await store.blurScores(for: [a]).isEmpty)
    check("descriptor miss on empty store", await store.descriptors(for: [a]).isEmpty)

    await store.storeBlurScores([(a, 42.5), (b, 1390.0)])
    let blur = await store.blurScores(for: [a, b])
    check("blur round-trip is exact", blur["A"] == 42.5 && blur["B"] == 1390.0)
    check("moved modification date misses",
          await store.blurScores(for: [ScanCacheKey(localIdentifier: "A", modifiedAt: 1001)]).isEmpty)
    check("rows not asked for are excluded", await store.blurScores(for: [a]).count == 1)

    let d1 = syntheticDescriptor(7), d2 = syntheticDescriptor(99)
    await store.storeDescriptors([(a, d1), (b, d2)])
    let restored = await store.descriptors(for: [a, b])
    check("descriptor fp16 round-trip is lossless",
          restored["A"]?.values == d1.values && restored["B"]?.values == d2.values)
    check("distance survives round-trip exactly",
          restored["A"]!.distance(to: restored["B"]!) == d1.distance(to: d2))

    var counts = await store.counts()
    check("counts before reopen", counts.blur == 2 && counts.descriptors == 2, "\(counts)")
    store = ScanCacheStore(directory: root)
    counts = await store.counts()
    check("survives reopen", counts.blur == 2 && counts.descriptors == 2, "\(counts)")
    check("reports a non-zero size", await store.sizeOnDisk() > 0)

    check("prune drops absent assets from both tables", await store.prune(keeping: ["A"]) == 2)
    counts = await store.counts()
    check("prune keeps what was asked for", counts.blur == 1 && counts.descriptors == 1, "\(counts)")

    // Version invalidation must hit one table only — a blur retune must not cost 24 MB of
    // descriptors. Forge a stale stamp directly, then reopen.
    await store.storeBlurScores([(b, 5.0)]); await store.storeDescriptors([(b, d2)])
    var raw: OpaquePointer?
    sqlite3_open(root.appendingPathComponent("scan-cache.sqlite").path, &raw)
    sqlite3_exec(raw, "UPDATE meta SET value='stale' WHERE key='print_version';", nil, nil, nil)
    sqlite3_close(raw)
    store = ScanCacheStore(directory: root)
    counts = await store.counts()
    check("version bump wipes descriptors only", counts.descriptors == 0 && counts.blur == 2, "\(counts)")

    sqlite3_open(root.appendingPathComponent("scan-cache.sqlite").path, &raw)
    var statement: OpaquePointer?
    var pageSize: Int32 = 0
    sqlite3_prepare_v2(raw, "PRAGMA page_size;", -1, &statement, nil)
    if sqlite3_step(statement) == SQLITE_ROW { pageSize = sqlite3_column_int(statement, 0) }
    sqlite3_finalize(statement); sqlite3_close(raw)
    check("page size is 8192", pageSize == 8192, "got \(pageSize)")

    try? FileManager.default.removeItem(at: root)
}

// MARK: - 2. Degradation

section("failure degrades to no-cache, never to an error")
do {
    let bad = ScanCacheStore(directory: URL(fileURLWithPath: "/dev/null/nope"))
    let key = ScanCacheKey(localIdentifier: "A", modifiedAt: 1)
    check("unwritable directory: read returns empty", await bad.blurScores(for: [key]).isEmpty)
    await bad.storeBlurScores([(key, 1.0)])
    check("unwritable directory: write is a no-op", await bad.blurScores(for: [key]).isEmpty)
    check("unwritable directory: prune is a no-op", await bad.prune(keeping: []) == 0)
}

// MARK: - 3. Real Vision descriptors

section("real Vision descriptors survive the cache")
do {
    var images: [(String, CGImage)] = []
    for j in [0, 1, 2, 3, 5, 8, 13] { images.append(("jitter\(j)", image(5, jitter: j))) }
    for s in [17, 41, 63, 88] { images.append(("other\(s)", image(s))) }
    let fresh = images.map { ($0.0, realDescriptor($0.1)) }

    let root = scratch()
    let store = ScanCacheStore(directory: root)
    let keys = fresh.enumerated().map {
        ScanCacheKey(localIdentifier: "\($0.element.0)/L0/001", modifiedAt: Int64($0.offset))
    }
    await store.storeDescriptors(Array(zip(keys, fresh.map(\.1))))
    let restored = await store.descriptors(for: keys)

    var maxDelta: Float = 0, distancesMatch = true, verdictsMatch = true
    for i in 0..<fresh.count {
        for j in (i + 1)..<fresh.count {
            guard let ra = restored[keys[i].localIdentifier],
                  let rb = restored[keys[j].localIdentifier],
                  let before = fresh[i].1.distance(to: fresh[j].1),
                  let after = ra.distance(to: rb) else { distancesMatch = false; continue }
            maxDelta = max(maxDelta, abs(before - after))
            if before != after { distancesMatch = false }
            // What clustering would actually conclude has to agree too.
            let groupedBefore = before <= DetectionThresholds.duplicateMaxDistance
            let groupedAfter = after <= DetectionThresholds.duplicateMaxDistance
            let tickedBefore = before <= DetectionThresholds.duplicateAutoTickMaxDistance
            let tickedAfter = after <= DetectionThresholds.duplicateAutoTickMaxDistance
            if groupedBefore != groupedAfter || tickedBefore != tickedAfter { verdictsMatch = false }
        }
    }
    let pairs = fresh.count * (fresh.count - 1) / 2
    check("all \(pairs) pairwise distances identical", distancesMatch, "max delta \(maxDelta)")
    check("all grouping and auto-tick verdicts identical", verdictsMatch)

    // The claim the whole fp16 decision rests on.
    var nonRepresentable = 0, elements = 0
    for (_, d) in fresh {
        for v in d.values { elements += 1; if Float(Float16(v)) != v { nonRepresentable += 1 } }
    }
    check("all \(elements) real elements are fp16-representable", nonRepresentable == 0,
          "\(nonRepresentable) were not")

    // Vision's own metric must equal ours, or the calibrated thresholds mean nothing.
    let o1 = { () -> VNFeaturePrintObservation in
        let r = VNGenerateImageFeaturePrintRequest(); r.revision = DetectionThresholds.visionFeaturePrintRevision
        try! VNImageRequestHandler(cgImage: image(5), options: [:]).perform([r])
        return r.results!.first!
    }()
    let o2 = { () -> VNFeaturePrintObservation in
        let r = VNGenerateImageFeaturePrintRequest(); r.revision = DetectionThresholds.visionFeaturePrintRevision
        try! VNImageRequestHandler(cgImage: image(41), options: [:]).perform([r])
        return r.results!.first!
    }()
    var vision = Float(0)
    try! o1.computeDistance(&vision, to: o2)
    let ours = FeatureDescriptor(o1)!.distance(to: FeatureDescriptor(o2)!)!
    check("FeatureDescriptor matches Vision.computeDistance", vision == ours, "\(vision) vs \(ours)")

    try? FileManager.default.removeItem(at: root)
}

// MARK: - 4. Scale, throughput and reclaim

section("scale: 13,530 photos with realistic identifiers")
do {
    let N = 13530
    let root = scratch()
    let store = ScanCacheStore(directory: root)
    let keys = (0..<N).map { ScanCacheKey(localIdentifier: "\(UUID().uuidString)/L0/001",
                                          modifiedAt: Int64($0) * 1000) }
    let descriptors = (0..<N).map(syntheticDescriptor)

    var t = Date()
    await store.storeDescriptors(Array(zip(keys, descriptors)))
    let writeTime = Date().timeIntervalSince(t)
    await store.storeBlurScores(keys.map { ($0, Float(42)) })

    t = Date()
    let read = await store.descriptors(for: keys)
    let readTime = Date().timeIntervalSince(t)

    print(String(format: "  write %d descriptors: %.2fs", N, writeTime))
    print(String(format: "  read  %d descriptors: %.2fs  (recomputing them costs ~87s on device)", N, readTime))
    check("every descriptor came back", read.count == N, "got \(read.count)")

    let full = await store.sizeOnDisk()
    print(String(format: "  on disk: %.1f MB (%.0f bytes/photo)", Double(full) / 1e6, Double(full) / Double(N)))
    check("read is far cheaper than recomputing", readTime < 5.0, "took \(readTime)s")

    // Space the user is promised has to actually come back.
    let pruned = await store.prune(keeping: Set(keys.prefix(N / 2).map(\.localIdentifier)))
    let afterPrune = await store.sizeOnDisk()
    check("prune reclaims disk space", afterPrune < full * 3 / 4,
          String(format: "%.1f MB → %.1f MB after removing %d rows",
                 Double(full) / 1e6, Double(afterPrune) / 1e6, pruned))

    await store.clear()
    let cleared = await store.sizeOnDisk()
    check("clear reclaims essentially everything", cleared < 200_000,
          String(format: "%.3f MB left", Double(cleared) / 1e6))
    let counts = await store.counts()
    check("clear empties both tables", counts.blur == 0 && counts.descriptors == 0, "\(counts)")

    await store.storeBlurScores([(keys[0], 1.0)])
    check("store is still usable after clearing",
          await store.blurScores(for: [keys[0]])[keys[0].localIdentifier] == 1.0)

    try? FileManager.default.removeItem(at: root)
}

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
