import Foundation
func check(_ condition: Bool, _ label: String) { precondition(condition, label); print("PASS: \(label)") }
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
let start = CSVHistoryFilterPreferences.dateForDayKey("2026-10-20", calendar: cal)!
let end = CSVHistoryFilterPreferences.dateForDayKey("2026-10-25", calendar: cal)!
let original = CSVHistoryFilterPreferences(search: "予約", status: "成功", scope: "全件CSV", dateEnabled: true, start: start, end: end, preset: nil, startDay: "2026-10-20", endDay: "2026-10-25")
let stored = try! JSONEncoder().encode(original)
var edited = original
edited.search = "変更中"
check(!CSVHistorySnapshotComparison.matches(current: edited, stored: stored, calendar: cal), "edited search shows unsaved")
var pending = edited
pending.startDay = "2026-10-26"
pending.endDay = "2026-10-25"
check(!CSVHistorySnapshotComparison.matches(current: pending, stored: stored, calendar: cal), "invalid range cannot show saved")
guard case .restored(let restored, let restoredStart, let restoredEnd, _) = CSVHistoryFilterRecovery.recover(stored, calendar: cal) else { fatalError("recover failed") }
check(CSVHistorySnapshotComparison.matches(current: restored, stored: stored, calendar: cal), "reverted controls match snapshot")
check(restoredStart == start && restoredEnd == end, "revert uses exact stored dates")
check(restored.search == original.search, "revert clears edited keyword")
check(restored.status == original.status, "revert restores status")
check(restored.scope == original.scope, "revert restores CSV scope")
check(restored.dateEnabled, "revert restores date enabled")
check(restored.startDay == original.startDay && restored.endDay == original.endDay, "revert restores day keys")
check(restored.preset == original.preset, "revert restores preset")
check({ if case .missing = CSVHistoryFilterRecovery.recover(nil) { return true }; return false }(), "missing snapshot is detected")
check({ if case .invalid = CSVHistoryFilterRecovery.recover(Data("broken".utf8)) { return true }; return false }(), "invalid snapshot is detected")
let suite = "hotelShift.fixed338.tests"
let defaults = UserDefaults(suiteName: suite)!
defaults.removePersistentDomain(forName: suite)
let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
defaults.set(stored, forKey: "filters")
CSVHistorySavedTimestamp.recordSuccessfulSave(in: defaults, key: "savedAt", at: timestamp)
check(CSVHistorySavedTimestamp.read(from: defaults, key: "savedAt", hasValidSnapshot: true) == timestamp, "revert does not change saved timestamp")
check(CSVHistorySnapshotComparison.matches(current: restored, stored: defaults.object(forKey: "filters"), calendar: cal), "stored snapshot remains consistent after revert")
defaults.removePersistentDomain(forName: suite)
print("FIXED338: 13 checks passed")
