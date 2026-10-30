import Foundation
let suite = "hotel.shift.fixed352.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let key = "csv.filters"
let timeKey = "csv.savedAt"
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message); checks += 1 }
func snapshot(_ search: String) -> Data {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let p = CSVHistoryFilterPreferences(search: search, status: "すべて", scope: "すべて", dateEnabled: false, start: now, end: now, preset: nil, startDay: CSVHistoryFilterPreferences.dayKey(now), endDay: CSVHistoryFilterPreferences.dayKey(now))
    return try! JSONEncoder().encode(p)
}
let original = snapshot("original")
let replacement = snapshot("replacement")
let savedAt = Date(timeIntervalSince1970: 1_700_000_123)
check({ if case .saved = CSVHistoryVerifiedWriter.save(original, in: defaults, key: key) { return true }; return false }(), "initial save")
CSVHistorySavedTimestamp.recordSuccessfulSave(in: defaults, key: timeKey, at: savedAt)
check(defaults.data(forKey: key) == original, "initial bytes")
let failed = CSVHistoryVerifiedWriter.save(replacement, in: defaults, key: key, write: { store, name, _ in store.set("bad type", forKey: name) })
check({ if case .failed(restoredPrevious: true) = failed { return true }; return false }(), "rollback succeeds")
check(defaults.data(forKey: key) == original, "previous snapshot retained")
check(CSVHistorySavedTimestamp.read(from: defaults, key: timeKey, hasValidSnapshot: true) == savedAt, "timestamp retained")
check({ if case .restored = CSVHistoryFilterRecovery.recover(defaults.object(forKey: key)) { return true }; return false }(), "old snapshot remains restorable")
check({ if case .saved = CSVHistoryVerifiedWriter.save(replacement, in: defaults, key: key) { return true }; return false }(), "retry succeeds")
check(defaults.data(forKey: key) == replacement, "retry persists new snapshot")
check(CSVHistorySavedTimestamp.read(from: defaults, key: timeKey, hasValidSnapshot: true) == savedAt, "timestamp only advanced by caller")
defaults.removeObject(forKey: key)
let missing = CSVHistoryVerifiedWriter.save(original, in: defaults, key: key, write: { store, name, _ in store.set("bad", forKey: name) })
check({ if case .failed(restoredPrevious: false) = missing { return true }; return false }(), "missing prior snapshot")
check(defaults.object(forKey: key) == nil, "failed initial write cleaned")
defaults.set(Data("corrupt".utf8), forKey: key)
_ = CSVHistoryVerifiedWriter.save(original, in: defaults, key: key, write: { store, name, _ in store.set("bad", forKey: name) })
check(defaults.object(forKey: key) == nil, "corrupt prior snapshot not restored")
check({ if case .saved = CSVHistoryVerifiedWriter.save(original, in: defaults, key: key) { return true }; return false }(), "recovery save")
check(defaults.data(forKey: key) == original, "recovery content")
print("FIXED352: \(checks)/\(checks) verified-write recovery checks passed")
