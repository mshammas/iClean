import Foundation

/// Which candidates are ticked for deletion.
///
/// Deliberately a **value type** held in a `@Published` property rather than a nested
/// `ObservableObject` — nested observable objects don't propagate their changes to views
/// observing the parent, which silently breaks UI updates.
///
/// Selection is keyed by `PHAsset.localIdentifier`, so an asset flagged by two different
/// detectors is only ever counted (and deleted) once.
struct ReviewSelection: Equatable {
    private(set) var selectedIDs: Set<String> = []

    init(selectedIDs: Set<String> = []) {
        self.selectedIDs = selectedIDs
    }

    func isSelected(_ id: String) -> Bool { selectedIDs.contains(id) }

    var count: Int { selectedIDs.count }
    var isEmpty: Bool { selectedIDs.isEmpty }

    mutating func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    mutating func setSelected(_ ids: [String], to selected: Bool) {
        if selected {
            selectedIDs.formUnion(ids)
        } else {
            selectedIDs.subtract(ids)
        }
    }

    mutating func removeAll() { selectedIDs.removeAll() }

    // MARK: Derived totals

    /// Selected items within one category.
    func selectedCount(in candidates: [Candidate]) -> Int {
        candidates.reduce(0) { $0 + (isSelected($1.id) ? 1 : 0) }
    }

    func allSelected(in candidates: [Candidate]) -> Bool {
        !candidates.isEmpty && candidates.allSatisfy { isSelected($0.id) }
    }

    /// Total estimated bytes across selected candidates, counting each asset once even if
    /// it appears in more than one category.
    func selectedBytes(in candidates: [Candidate]) -> Int64 {
        var seen = Set<String>()
        var total: Int64 = 0
        for candidate in candidates where isSelected(candidate.id) {
            guard seen.insert(candidate.id).inserted else { continue }
            total += candidate.estimatedBytes
        }
        return total
    }
}
