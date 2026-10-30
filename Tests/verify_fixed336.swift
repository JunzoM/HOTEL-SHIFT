import Foundation
func check(_ ok: Bool, _ label: String) { precondition(ok, label); print("PASS: \(label)") }
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
let start = CSVHistoryFilterPreferences.dateForDayKey("2024-10-01", calendar: cal)!
let end = CSVHistoryFilterPreferences.dateForDayKey("2024-10-04", calendar: cal)!
func make(_ search: String = "test", _ status: String = "成功", _ scope: String = "全件CSV", _ enabled: Bool = true, _ endDay: String = "2024-10-04") -> CSVHistoryFilterPreferences {
    CSVHistoryFilterPreferences(search: search, status: status, scope: scope, dateEnabled: enabled,
        start: start, end: end, preset: nil, startDay: "2024-10-01", endDay: endDay)
}
let saved = make()
let data = try! JSONEncoder().encode(saved)
func matches(_ p: CSVHistoryFilterPreferences, _ stored: Any? = nil) -> Bool {
    CSVHistorySnapshotComparison.matches(current: p, stored: stored ?? data, calendar: cal)
}
check(matches(saved), "identical snapshot")
check(!matches(make("edited")), "edited search is unsaved")
check(!matches(make("test", "失敗")), "edited status is unsaved")
check(!matches(make("test", "成功", "絞り込みCSV")), "edited scope is unsaved")
check(!matches(make("test", "成功", "全件CSV", false)), "edited date toggle is unsaved")
check(!matches(make("test", "成功", "全件CSV", true, "2024-10-03")), "edited end date is unsaved")
check(!matches(make("test", "成功", "全件CSV", true, "2024-09-30")), "invalid interim date is not saved")
check(!matches(saved, Data("broken".utf8)), "corrupted stored snapshot")
check(!matches(saved, "invalid type"), "wrong storage type")
check(!matches(saved, NSNull()), "missing saved snapshot")
var legacy = saved
legacy.startDay = nil; legacy.endDay = nil
check(matches(saved, try! JSONEncoder().encode(legacy)), "legacy snapshot compares after migration")
var hiddenDates = make("test", "成功", "全件CSV", false)
let hiddenData = try! JSONEncoder().encode(hiddenDates)
hiddenDates.endDay = "2024-10-02"
check(CSVHistorySnapshotComparison.matches(current: hiddenDates, stored: hiddenData, calendar: cal), "disabled date range does not affect active filters")
let newData = try! JSONEncoder().encode(make("edited"))
check(matches(make("edited"), newData), "corrected edit matches after successful save")
print("FIXED336: 13 checks passed")
