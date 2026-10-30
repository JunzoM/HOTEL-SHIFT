import Foundation

func check(_ ok: Bool, _ label: String) {
    if !ok { fatalError("FAIL: \(label)") }
    print("PASS: \(label)")
}

let calendar = Calendar(identifier: .gregorian)
let jan31 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
let feb1 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
let base = CSVHistoryFilterPreferences(search: "勤務件数", status: "失敗", scope: "絞り込みCSV", dateEnabled: true, start: jan31, end: feb1, preset: nil)
func encode(_ v: CSVHistoryFilterPreferences) -> Data { try! JSONEncoder().encode(v) }
check(CSVHistoryFilterPreferences.validated(from: encode(base), calendar: calendar) != nil, "valid date range across month boundary")
check(CSVHistoryFilterPreferences.validated(from: Data("{broken".utf8)) == nil, "malformed JSON")
check(CSVHistoryFilterPreferences.validated(from: Data("{}".utf8)) == nil, "old/incomplete schema")
var v = base; v.status = "unknown"
check(CSVHistoryFilterPreferences.validated(from: encode(v)) == nil, "unknown status")
v = base; v.scope = "unknown"
check(CSVHistoryFilterPreferences.validated(from: encode(v)) == nil, "unknown scope")
v = base; v.search = String(repeating: "a", count: 1001)
check(CSVHistoryFilterPreferences.validated(from: encode(v)) == nil, "oversized search")
v = base; v.preset = "unknown"
check(CSVHistoryFilterPreferences.validated(from: encode(v)) == nil, "unknown preset")
v = base; v.start = feb1; v.end = jan31
check(CSVHistoryFilterPreferences.validated(from: encode(v), calendar: calendar) == nil, "reversed manual range")
v.dateEnabled = false
check(CSVHistoryFilterPreferences.validated(from: encode(v), calendar: calendar) != nil, "disabled date range ignores order")
v.dateEnabled = true; v.preset = "先月"
check(CSVHistoryFilterPreferences.validated(from: encode(v), calendar: calendar) != nil, "preset range recalculated on restore")
print("FIXED322: 10 tests passed")
