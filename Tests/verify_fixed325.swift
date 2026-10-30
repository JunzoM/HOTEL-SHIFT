import Foundation
func require(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS: \(label)") }
func calendar(_ id: String) -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: id)!; return c }
let tokyo = calendar("Asia/Tokyo")
let newYork = calendar("America/New_York")
let berlin = calendar("Europe/Berlin")
for day in ["2026-01-01", "2026-03-08", "2026-11-01", "2024-02-29", "2026-12-31"] {
    let saved = CSVHistoryFilterPreferences.dateForDayKey(day, calendar: tokyo)!
    let pref = CSVHistoryFilterPreferences(search: "", status: "すべて", scope: "すべて", dateEnabled: true, start: saved, end: saved, preset: nil, startDay: day, endDay: day)
    let decoded = CSVHistoryFilterPreferences.validated(from: try! JSONEncoder().encode(pref), calendar: newYork)!
    require(CSVHistoryFilterPreferences.dayKey(decoded.restoredDates(calendar: newYork)!.start, calendar: newYork) == day, "Tokyo to New York: \(day)")
    require(CSVHistoryFilterPreferences.dayKey(decoded.restoredDates(calendar: berlin)!.end, calendar: berlin) == day, "Tokyo to Berlin: \(day)")
}
for invalid in ["2026-02-29", "2026-13-01", "2026-00-01", "2026-01-32", "2026-1-01", "2026-01-1", "bad"] {
    require(CSVHistoryFilterPreferences.dateForDayKey(invalid, calendar: tokyo) == nil, "invalid date rejected: \(invalid)")
}
let old = CSVHistoryFilterPreferences(search: "", status: "すべて", scope: "すべて", dateEnabled: false, start: Date(), end: Date(), preset: nil)
require(CSVHistoryFilterPreferences.validated(from: try! JSONEncoder().encode(old)) != nil, "legacy dates still decode")
print("FIXED325: 18 tests passed")
