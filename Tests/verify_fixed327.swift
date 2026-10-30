import Foundation
func calendar(_ name: String) -> Calendar {
    var result = Calendar(identifier: .gregorian)
    result.timeZone = TimeZone(identifier: name)!
    return result
}
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label)
    print("PASS: \(label)")
}
let tokyo = calendar("Asia/Tokyo")
let ny = calendar("America/New_York")
let day = CSVHistoryFilterPreferences.dateForDayKey("2024-02-29", calendar: tokyo)!
let legacy = CSVHistoryFilterPreferences(search: "失敗", status: "失敗", scope: "全件CSV", dateEnabled: true, start: day, end: day, preset: nil)
let migrated = legacy.migratedToDayKeys(calendar: tokyo)!
check(migrated.startDay == "2024-02-29", "legacy migration")
check(migrated.migratedToDayKeys(calendar: tokyo)!.startDay == migrated.startDay, "migration idempotence")
let saved = try! JSONEncoder().encode(migrated)
let restored = CSVHistoryFilterPreferences.validated(from: saved, calendar: ny)!
check(restored.restoredDates(calendar: ny).map { CSVHistoryFilterPreferences.dayKey($0.start, calendar: ny) } == "2024-02-29", "timezone stable")
for bad in ["2024-02-30", "2023-02-29", "2024-2-29", "2024-02-29 ", "２０２４-02-29", "2024-00-29", "2024-13-01", "2024-02-2x"] {
    var copy = migrated
    copy.startDay = bad
    let bytes = try! JSONEncoder().encode(copy)
    check(CSVHistoryFilterPreferences.validated(from: bytes, calendar: tokyo) == nil, "reject \(bad)")
}
var half = migrated
half.endDay = nil
check(CSVHistoryFilterPreferences.validated(from: try! JSONEncoder().encode(half), calendar: tokyo) == nil, "reject partial keys")
var reversed = migrated
reversed.startDay = "2024-03-01"
check(CSVHistoryFilterPreferences.validated(from: try! JSONEncoder().encode(reversed), calendar: tokyo) == nil, "reject reversed manual range")
var invalidScope = migrated
invalidScope.scope = "unknown"
check(CSVHistoryFilterPreferences.validated(from: try! JSONEncoder().encode(invalidScope), calendar: tokyo) == nil, "reject unknown scope")
check(CSVHistoryFilterPreferences.validated(from: Data("{bad".utf8), calendar: tokyo) == nil, "reject corrupt JSON")
print("FIXED327: 15 tests passed")
