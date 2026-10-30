import Foundation
let suite = "hotel.shift.fixed357.\(UUID().uuidString)"
let store = UserDefaults(suiteName: suite)!
defer { store.removePersistentDomain(forName: suite) }
let key = "filters", timeKey = "savedAt"
let day = Date(timeIntervalSince1970: 1_700_000_000)
let prefs = CSVHistoryFilterPreferences(search: "original", status: "すべて", scope: "すべて", dateEnabled: false, start: day, end: day, preset: nil, startDay: CSVHistoryFilterPreferences.dayKey(day), endDay: CSVHistoryFilterPreferences.dayKey(day))
let valid = try! JSONEncoder().encode(prefs)
let timestamp = Date(timeIntervalSince1970: 1_700_000_100)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ description: String) { precondition(condition(), description); checks += 1 }
func isCancelled(_ result: CSVHistoryRevertDecision.Outcome) -> Bool { if case .cancelled = result { return true }; return false }
func isMissing(_ result: CSVHistoryRevertDecision.Outcome) -> Bool { if case .missing = result { return true }; return false }
func isInvalid(_ result: CSVHistoryRevertDecision.Outcome) -> Bool { if case .invalid = result { return true }; return false }
// Cancel must not even evaluate the stored-value expression.
var reads = 0
func read() -> Any? { reads += 1; return store.object(forKey: key) }
check(isCancelled(CSVHistoryRevertDecision.evaluate(confirmed: false, stored: read())), "cancel outcome")
check(reads == 0, "cancel does not read")
check(isMissing(CSVHistoryRevertDecision.evaluate(confirmed: true, stored: read())), "missing outcome")
check(reads == 1, "confirmed reads once")
store.set("invalid type", forKey: key)
check(isInvalid(CSVHistoryRevertDecision.evaluate(confirmed: true, stored: read())), "invalid type")
store.set(Data("bad JSON".utf8), forKey: key)
check(isInvalid(CSVHistoryRevertDecision.evaluate(confirmed: true, stored: read())), "invalid JSON")
store.set(valid, forKey: key)
store.set(timestamp, forKey: timeKey)
let result = CSVHistoryRevertDecision.evaluate(confirmed: true, stored: read())
if case .restored(let restored, let start, let end) = result {
    check(restored.search == "original", "restored keyword")
    check(restored.status == "すべて", "restored status")
    check(restored.scope == "すべて", "restored scope")
    check(!restored.dateEnabled, "restored disabled date")
    check(start <= end, "restored dates")
} else { fatalError("expected restored") }
check(store.data(forKey: key) == valid, "revert decision does not write")
check(store.object(forKey: timeKey) as? Date == timestamp, "revert does not update timestamp")
check(isCancelled(CSVHistoryRevertDecision.evaluate(confirmed: false, stored: read())), "cancel with saved data")
check(store.data(forKey: key) == valid, "cancel keeps saved snapshot")
store.removeObject(forKey: key)
check(isMissing(CSVHistoryRevertDecision.evaluate(confirmed: true, stored: read())), "snapshot disappears before confirmation")
check(store.object(forKey: timeKey) as? Date == timestamp, "decision does not clear timestamp")
print("FIXED357: \(checks)/\(checks) revert decision tests passed")
