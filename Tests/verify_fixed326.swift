import Foundation
func check(_ value: @autoclosure () -> Bool, _ name: String) { precondition(value(), name); print("PASS: \(name)") }
func zone(_ name: String) -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: name)!; return c }
let tokyo = zone("Asia/Tokyo")
let newYork = zone("America/New_York")
let berlin = zone("Europe/Berlin")
var tests = 0
for key in ["2024-02-29", "2026-01-01", "2026-03-08", "2026-11-01", "2026-12-31"] {
    let date = CSVHistoryFilterPreferences.dateForDayKey(key, calendar: tokyo)!
    let legacy = CSVHistoryFilterPreferences(search: "failure", status: "失敗", scope: "全件CSV", dateEnabled: true, start: date, end: date, preset: nil)
    let encoded = try! JSONEncoder().encode(legacy)
    let decoded = CSVHistoryFilterPreferences.validated(from: encoded, calendar: tokyo)!
    let upgraded = decoded.migratedToDayKeys(calendar: tokyo)!
    check(upgraded.startDay == key && upgraded.endDay == key, "legacy migration \(key)"); tests += 1
    let persisted = try! JSONEncoder().encode(upgraded)
    for calendar in [newYork, berlin] {
        let restored = CSVHistoryFilterPreferences.validated(from: persisted, calendar: calendar)!.restoredDates(calendar: calendar)!
        check(CSVHistoryFilterPreferences.dayKey(restored.start, calendar: calendar) == key, "timezone restore \(key)"); tests += 1
    }
    check(upgraded.search == legacy.search && upgraded.status == legacy.status && upgraded.scope == legacy.scope, "filters preserved \(key)"); tests += 1
}
let start = CSVHistoryFilterPreferences.dateForDayKey("2026-12-30", calendar: tokyo)!
let end = CSVHistoryFilterPreferences.dateForDayKey("2027-01-02", calendar: tokyo)!
let range = CSVHistoryFilterPreferences(search: "", status: "すべて", scope: "すべて", dateEnabled: true, start: start, end: end, preset: nil)
let upgraded = range.migratedToDayKeys(calendar: tokyo)!
check(upgraded.startDay == "2026-12-30" && upgraded.endDay == "2027-01-02", "multi-day range migration"); tests += 1
check(CSVHistoryFilterPreferences.validated(from: try! JSONEncoder().encode(upgraded), calendar: newYork) != nil, "migrated range validation"); tests += 1
print("FIXED326: \(tests) tests passed")
