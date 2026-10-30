import Foundation
let suite = "hotel.shift.fixed354.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let key = "filters", timeKey = "savedAt"
var count = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label); count += 1
}
let date = Date(timeIntervalSince1970: 1_700_000_000)
let prefs = CSVHistoryFilterPreferences(search: "valid", status: "すべて", scope: "すべて", dateEnabled: false, start: date, end: date, preset: nil, startDay: CSVHistoryFilterPreferences.dayKey(date), endDay: CSVHistoryFilterPreferences.dayKey(date))
let data = try! JSONEncoder().encode(prefs)
let previousTime = Date(timeIntervalSince1970: 1_700_000_100)
let missing = CSVHistoryFailedSaveInspection.inspect(defaults: defaults, filtersKey: key, timestampKey: timeKey)
check(!missing.hasSavedSnapshot, "missing snapshot")
check(missing.lastSavedAt == nil, "missing timestamp")
defaults.set(previousTime, forKey: timeKey)
let orphan = CSVHistoryFailedSaveInspection.inspect(defaults: defaults, filtersKey: key, timestampKey: timeKey)
check(!orphan.hasSavedSnapshot, "orphan timestamp not saved")
check(orphan.lastSavedAt == nil, "orphan timestamp hidden")
defaults.set(data, forKey: key)
let valid = CSVHistoryFailedSaveInspection.inspect(defaults: defaults, filtersKey: key, timestampKey: timeKey)
check(valid.hasSavedSnapshot, "valid snapshot")
check(valid.lastSavedAt == previousTime, "valid timestamp")
let failed = CSVHistoryVerifiedWriter.save(data, in: defaults, key: key, write: { store, name, _ in store.set("bad", forKey: name) })
check({ if case .failed(restoredPrevious: true) = failed { return true }; return false }(), "rollback succeeded")
let rolledBack = CSVHistoryFailedSaveInspection.inspect(defaults: defaults, filtersKey: key, timestampKey: timeKey)
check(rolledBack.hasSavedSnapshot, "rollback saved badge")
check(rolledBack.lastSavedAt == previousTime, "rollback keeps timestamp")
defaults.set(Data("corrupt".utf8), forKey: key)
let corrupt = CSVHistoryFailedSaveInspection.inspect(defaults: defaults, filtersKey: key, timestampKey: timeKey)
check(!corrupt.hasSavedSnapshot, "corrupt snapshot rejected")
check(corrupt.lastSavedAt == nil, "corrupt timestamp hidden")
defaults.removeObject(forKey: key)
let failedFirst = CSVHistoryVerifiedWriter.save(data, in: defaults, key: key, write: { store, name, _ in store.set("bad", forKey: name) })
check({ if case .failed(restoredPrevious: false) = failedFirst { return true }; return false }(), "unrecoverable failed save")
check(!CSVHistoryFailedSaveInspection.inspect(defaults: defaults, filtersKey: key, timestampKey: timeKey).hasSavedSnapshot, "unrecoverable badge")
check({ if case .saved = CSVHistoryVerifiedWriter.save(data, in: defaults, key: key) { return true }; return false }(), "retry successful")
check(CSVHistoryFailedSaveInspection.inspect(defaults: defaults, filtersKey: key, timestampKey: timeKey).hasSavedSnapshot, "retry restores badge")
print("FIXED354: \(count)/\(count) recovery UI consistency tests passed")
