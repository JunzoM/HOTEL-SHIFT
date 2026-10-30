import Foundation
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), "FAIL: \(label)")
    print("PASS: \(label)")
}
let suite = "HOTEL_SHIFT_FIXED335_\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let filterKey = "filters"
let timeKey = "savedAt"
let now = Date(timeIntervalSince1970: 1_730_000_000)
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
let start = CSVHistoryFilterPreferences.dateForDayKey("2024-10-01", calendar: calendar)!
let end = CSVHistoryFilterPreferences.dateForDayKey("2024-10-04", calendar: calendar)!
func prefs(_ search: String, _ endDay: String = "2024-10-04") -> CSVHistoryFilterPreferences {
    CSVHistoryFilterPreferences(search: search, status: "成功", scope: "全件CSV", dateEnabled: true,
        start: start, end: end, preset: nil, startDay: "2024-10-01", endDay: endDay)
}
func save(_ p: CSVHistoryFilterPreferences, at time: Date) -> Bool {
    guard let data = try? JSONEncoder().encode(p),
          CSVHistoryFilterPreferences.validated(from: data, calendar: calendar) != nil else { return false }
    defaults.set(data, forKey: filterKey)
    _ = CSVHistorySavedTimestamp.recordSuccessfulSave(in: defaults, key: timeKey, at: time)
    return true
}
check(CSVHistorySavedTimestamp.read(from: defaults, key: timeKey, hasValidSnapshot: false) == nil, "fresh install has no timestamp")
check(save(prefs("first"), at: now), "valid snapshot saved")
check(CSVHistorySavedTimestamp.read(from: defaults, key: timeKey, hasValidSnapshot: true) == now, "saved time survives defaults read")
let snapshot = defaults.data(forKey: filterKey)!
check(!save(prefs("bad", "2024-09-30"), at: now.addingTimeInterval(60)), "invalid range rejected")
check(defaults.data(forKey: filterKey) == snapshot, "invalid edit preserves last valid snapshot")
check(CSVHistorySavedTimestamp.read(from: defaults, key: timeKey, hasValidSnapshot: true) == now, "pending edit does not update timestamp")
let later = now.addingTimeInterval(120)
check(save(prefs("fixed"), at: later), "corrected edit saves")
check(CSVHistorySavedTimestamp.read(from: defaults, key: timeKey, hasValidSnapshot: true) == later, "corrected edit updates timestamp")
check(CSVHistorySavedTimestamp.read(from: defaults, key: timeKey, hasValidSnapshot: false) == nil, "timestamp hidden without valid snapshot")
defaults.set("bad timestamp", forKey: timeKey)
check(CSVHistorySavedTimestamp.read(from: defaults, key: timeKey, hasValidSnapshot: true) == nil, "wrong timestamp type ignored")
defaults.set(later, forKey: timeKey)
defaults.set(Data("bad json".utf8), forKey: filterKey)
if case .invalid = CSVHistoryFilterRecovery.recover(defaults.object(forKey: filterKey), calendar: calendar) {
    defaults.removeObject(forKey: filterKey)
    CSVHistorySavedTimestamp.clear(in: defaults, key: timeKey)
} else { preconditionFailure("corruption not detected") }
check(defaults.object(forKey: timeKey) == nil, "corruption clears stale timestamp")
check(save(prefs("recovered"), at: later), "recovery allows saving again")
check(CSVHistorySavedTimestamp.read(from: defaults, key: timeKey, hasValidSnapshot: true) == later, "timestamp restored after recovery")
var legacy = prefs("legacy")
legacy.startDay = nil
legacy.endDay = nil
defaults.set(try! JSONEncoder().encode(legacy), forKey: filterKey)
let legacyTime = now.addingTimeInterval(-3600)
defaults.set(legacyTime, forKey: timeKey)
if case .restored(_, _, _, let upgraded) = CSVHistoryFilterRecovery.recover(defaults.object(forKey: filterKey), calendar: calendar) {
    check(upgraded != nil, "legacy snapshot migrates")
    defaults.set(upgraded!, forKey: filterKey)
} else { preconditionFailure("legacy restore failed") }
check(CSVHistorySavedTimestamp.read(from: defaults, key: timeKey, hasValidSnapshot: true) == legacyTime, "legacy migration preserves original save time")
print("FIXED335: all timestamp persistence checks passed")
