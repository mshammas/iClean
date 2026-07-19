import Foundation
import Photos
import SQLite3

/// SQLite wants to know whether it may keep the pointer we hand it. `TRANSIENT` tells it to
/// copy immediately, which is what we want everywhere here — it removes any question of a Swift
/// buffer outliving the bind call.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Identity of a cached measurement: which asset, and which version of it.
///
/// `modificationDate` is the invalidation signal. It also changes for non-pixel edits (toggling
/// a favourite), which costs a needless recompute — wasteful, never stale, and that is the
/// direction to fail in.
struct ScanCacheKey: Hashable, Sendable {
    let localIdentifier: String
    /// Milliseconds since the reference date. Integer, not `Double`: this is compared for exact
    /// equality, and float equality on round-tripped dates is a trap.
    let modifiedAt: Int64

    /// Used when PhotoKit reports no modification date. Such an asset isn't being modified in
    /// any way PhotoKit will tell us about, so a stable sentinel is a usable key.
    private static let noDate = Int64.min

    init(localIdentifier: String, modifiedAt: Int64) {
        self.localIdentifier = localIdentifier
        self.modifiedAt = modifiedAt
    }

    init(_ asset: PHAsset) {
        self.localIdentifier = asset.localIdentifier
        if let date = asset.modificationDate {
            self.modifiedAt = Int64((date.timeIntervalSinceReferenceDate * 1000).rounded())
        } else {
            self.modifiedAt = Self.noDate
        }
    }
}

/// On-disk memoization of the two expensive per-photo measurements: the blur score and the
/// Vision feature print.
///
/// **Every operation is best-effort.** A cache that fails must degrade to "no cache" and never
/// break a scan, so nothing here throws — failures are swallowed (and logged in Debug) and the
/// caller simply gets a miss. The scan already works without this; it must keep working when
/// the disk is full, the file is corrupt, or iOS has purged something underneath us.
///
/// See CLAUDE.md → "Scan cache design" for the measured basis (~21 MB of descriptors, <1 MB of
/// scores, blur 149s / fingerprinting 87s on a 17k library).
actor ScanCacheStore {

    static let shared = ScanCacheStore()

    private let fileURL: URL
    private var db: OpaquePointer?
    /// Nil until the first use; `false` once opening has failed, so we don't retry every call.
    private var isOpen: Bool?

    /// - Parameter directory: overridable so tests can use a scratch location.
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iClean", isDirectory: true)
        self.fileURL = base.appendingPathComponent("scan-cache.sqlite")
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: Opening

    /// Opens (and if needed creates) the database, applying any version invalidation.
    @discardableResult
    private func open() -> Bool {
        if let isOpen { return isOpen }

        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
        } catch {
            log("could not create cache directory: \(error)")
            isOpen = false
            return false
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(fileURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            log("could not open cache: \(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "?")")
            if let handle { sqlite3_close(handle) }
            isOpen = false
            return false
        }
        db = handle

        // A regenerable cache must never consume the user's iCloud backup — least of all in an
        // app whose whole purpose is reclaiming storage.
        excludeFromBackup()

        // Page size must be set before the file gains any content, and before WAL mode —
        // changing it afterwards needs a full VACUUM.
        //
        // 8 KB, not the 4 KB default, purely to stop padding waste. A descriptor row is ~1,600
        // bytes (1,536 blob + a 43-char identifier + overhead), so a 4 KB page holds two and
        // throws away 22% of every page. Eight KB holds five. Measured at 13.5k photos with
        // realistic identifiers: **30.1 MB → 24.6 MB** for exactly the same data.
        // 16 KB was also measured and gains a further 0.1 MB, i.e. this is the floor; the
        // remaining 18% over raw descriptor bytes is the blur table plus two TEXT primary-key
        // indexes, which would need an integer-key redesign to shift and isn't worth it.
        guard exec("PRAGMA page_size=8192;"),
              exec("PRAGMA journal_mode=WAL;"),
              exec("PRAGMA synchronous=NORMAL;"),
              exec("""
                   CREATE TABLE IF NOT EXISTS meta (
                       key TEXT PRIMARY KEY,
                       value TEXT NOT NULL
                   );
                   CREATE TABLE IF NOT EXISTS blur (
                       local_id TEXT PRIMARY KEY,
                       modified INTEGER NOT NULL,
                       score REAL NOT NULL
                   );
                   CREATE TABLE IF NOT EXISTS print (
                       local_id TEXT PRIMARY KEY,
                       modified INTEGER NOT NULL,
                       vec BLOB NOT NULL
                   );
                   """)
        else {
            log("could not initialise schema: \(lastError())")
            sqlite3_close(handle)
            db = nil
            isOpen = false
            return false
        }

        invalidateIfVersionChanged(table: "blur", key: "blur_version", expected: ScanCacheVersion.blur)
        invalidateIfVersionChanged(table: "print", key: "print_version", expected: ScanCacheVersion.descriptor)

        isOpen = true
        return true
    }

    /// Drops a table's contents when the parameters that produced them have changed. Only the
    /// affected table — a blur retune must not throw away 21 MB of descriptors.
    private func invalidateIfVersionChanged(table: String, key: String, expected: String) {
        let stored = metaValue(for: key)
        guard stored != expected else { return }
        if stored != nil {
            log("\(table) cache invalidated: \(stored ?? "nil") → \(expected)")
        }
        _ = exec("DELETE FROM \(table);")
        setMetaValue(expected, for: key)
    }

    private func excludeFromBackup() {
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    // MARK: Blur scores

    /// Cached blur scores for the given assets, keyed by `localIdentifier`.
    ///
    /// Only entries whose stored modification date still matches are returned; anything else is
    /// a miss and the caller re-measures.
    func blurScores(for keys: [ScanCacheKey]) -> [String: Float] {
        guard open(), !keys.isEmpty else { return [:] }

        let wanted = Dictionary(keys.map { ($0.localIdentifier, $0.modifiedAt) },
                                uniquingKeysWith: { first, _ in first })
        var found: [String: Float] = [:]
        found.reserveCapacity(min(keys.count, 4096))

        query("SELECT local_id, modified, score FROM blur;") { statement in
            guard let raw = sqlite3_column_text(statement, 0) else { return }
            let id = String(cString: raw)
            guard wanted[id] == sqlite3_column_int64(statement, 1) else { return }
            found[id] = Float(sqlite3_column_double(statement, 2))
        }
        return found
    }

    func storeBlurScores(_ entries: [(key: ScanCacheKey, score: Float)]) {
        guard open(), !entries.isEmpty else { return }
        write("INSERT OR REPLACE INTO blur (local_id, modified, score) VALUES (?, ?, ?);",
              entries) { statement, entry in
            sqlite3_bind_text(statement, 1, entry.key.localIdentifier, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(statement, 2, entry.key.modifiedAt)
            sqlite3_bind_double(statement, 3, Double(entry.score))
        }
    }

    // MARK: Feature descriptors

    /// Cached descriptors for the given assets, keyed by `localIdentifier`.
    ///
    /// Rows for assets that weren't asked for, or whose modification date has moved, are
    /// skipped without being decoded — worth doing when the table is ~21 MB.
    func descriptors(for keys: [ScanCacheKey]) -> [String: FeatureDescriptor] {
        guard open(), !keys.isEmpty else { return [:] }

        let wanted = Dictionary(keys.map { ($0.localIdentifier, $0.modifiedAt) },
                                uniquingKeysWith: { first, _ in first })
        var found: [String: FeatureDescriptor] = [:]
        found.reserveCapacity(min(keys.count, 16384))

        query("SELECT local_id, modified, vec FROM print;") { statement in
            guard let raw = sqlite3_column_text(statement, 0) else { return }
            let id = String(cString: raw)
            guard wanted[id] == sqlite3_column_int64(statement, 1) else { return }
            guard let bytes = sqlite3_column_blob(statement, 2) else { return }
            let count = Int(sqlite3_column_bytes(statement, 2))
            guard count > 0 else { return }
            let data = Data(bytes: bytes, count: count)
            if let descriptor = FeatureDescriptor(halfPrecisionData: data) {
                found[id] = descriptor
            }
        }
        return found
    }

    func storeDescriptors(_ entries: [(key: ScanCacheKey, descriptor: FeatureDescriptor)]) {
        guard open(), !entries.isEmpty else { return }
        write("INSERT OR REPLACE INTO print (local_id, modified, vec) VALUES (?, ?, ?);",
              entries) { statement, entry in
            sqlite3_bind_text(statement, 1, entry.key.localIdentifier, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(statement, 2, entry.key.modifiedAt)
            let data = entry.descriptor.halfPrecisionData
            data.withUnsafeBytes { buffer in
                _ = sqlite3_bind_blob(statement, 3, buffer.baseAddress, Int32(buffer.count),
                                      SQLITE_TRANSIENT)
            }
        }
    }

    // MARK: Maintenance

    /// Drops rows for assets no longer in the library, so a deleted photo doesn't keep paying
    /// rent. Returns how many rows went.
    ///
    /// Done as a read-then-diff rather than `NOT IN (…)`: the identifier list runs to five
    /// figures, which is no shape for a SQL literal.
    @discardableResult
    func prune(keeping identifiers: Set<String>) -> Int {
        guard open() else { return 0 }

        var removed = 0
        for table in ["blur", "print"] {
            var stale: [String] = []
            query("SELECT local_id FROM \(table);") { statement in
                guard let raw = sqlite3_column_text(statement, 0) else { return }
                let id = String(cString: raw)
                if !identifiers.contains(id) { stale.append(id) }
            }
            guard !stale.isEmpty else { continue }
            write("DELETE FROM \(table) WHERE local_id = ?;", stale) { statement, id in
                sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
            }
            removed += stale.count
        }
        if removed > 0 { _ = exec("VACUUM;") }
        return removed
    }

    /// Everything the cache holds. Backs the user-facing "Clear cached scan data".
    func clear() {
        guard open() else { return }
        _ = exec("DELETE FROM blur; DELETE FROM print;")
        _ = exec("VACUUM;")
    }

    /// Bytes on disk, including the WAL sidecar — what the user would see in iPhone Storage.
    func sizeOnDisk() -> Int64 {
        let paths = [fileURL.path, fileURL.path + "-wal", fileURL.path + "-shm"]
        return paths.reduce(Int64(0)) { total, path in
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? Int64
            return total + (size ?? 0)
        }
    }

    /// Row counts per table, for the debug scan summary.
    func counts() -> (blur: Int, descriptors: Int) {
        guard open() else { return (0, 0) }
        return (count(in: "blur"), count(in: "print"))
    }

    private func count(in table: String) -> Int {
        var result = 0
        query("SELECT COUNT(*) FROM \(table);") { statement in
            result = Int(sqlite3_column_int64(statement, 0))
        }
        return result
    }

    // MARK: SQLite plumbing

    private func exec(_ sql: String) -> Bool {
        guard let db else { return false }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    /// Runs a read query, invoking `row` for each result row.
    private func query(_ sql: String, row: (OpaquePointer) -> Void) {
        guard let db else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            log("prepare failed for \(sql): \(lastError())")
            return
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
    }

    /// Runs one prepared statement across many items inside a single transaction. Batching
    /// matters: 13.5k individual commits would each fsync.
    private func write<T>(_ sql: String, _ items: [T], bind: (OpaquePointer, T) -> Void) {
        guard let db, !items.isEmpty else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            log("prepare failed for \(sql): \(lastError())")
            return
        }
        defer { sqlite3_finalize(statement) }

        guard exec("BEGIN TRANSACTION;") else { return }
        for item in items {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(statement, item)
            if sqlite3_step(statement) != SQLITE_DONE {
                log("write step failed: \(lastError())")
                _ = exec("ROLLBACK;")
                return
            }
        }
        _ = exec("COMMIT;")
    }

    private func metaValue(for key: String) -> String? {
        var value: String?
        guard let db else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = ?;", -1,
                                 &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
        if sqlite3_step(statement) == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0) {
            value = String(cString: raw)
        }
        return value
    }

    private func setMetaValue(_ value: String, for key: String) {
        write("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?);", [(key, value)]) { statement, pair in
            sqlite3_bind_text(statement, 1, pair.0, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, pair.1, -1, SQLITE_TRANSIENT)
        }
    }

    private func lastError() -> String {
        guard let db else { return "no connection" }
        return String(cString: sqlite3_errmsg(db))
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[iClean] scan cache: \(message)")
        #endif
    }
}
