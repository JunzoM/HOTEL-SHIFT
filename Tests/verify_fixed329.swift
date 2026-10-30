import Foundation
func check(_ yes: @autoclosure () -> Bool, _ label: String) { precondition(yes(), label); print("PASS: \(label)") }
var tokyo = Calendar(identifier: .gregorian)
tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
var ny = Calendar(identifier: .gregorian)
ny.timeZone = TimeZone(identifier: "America/New_York")!
let day = CSVHistoryFilterPreferences.dateForDayKey("2024-02-29", calendar: tokyo)!
let original = CSVHistoryFilterPreferences(search: "失敗", status: "失敗", scope: "全件CSV", dateEnabled: true, start: day, end: day, preset: nil)
let oldData = try! JSONEncoder().encode(original)
switch CSVHistoryFilterRecovery.recover(oldData, calendar: tokyo) {
case .restored(let pref, _, _, let upgraded):
    check(pref.startDay == "2024-02-29", "legacy migrated")
    check(upgraded != nil, "legacy upgrade provided")
    switch CSVHistoryFilterRecovery.recover(upgraded!, calendar: ny) {
    case .restored(let next, let start, _, let secondUpgrade):
        check(next.search == "失敗", "search preserved")
        check(next.status == "失敗", "status preserved")
        check(next.scope == "全件CSV", "scope preserved")
        check(CSVHistoryFilterPreferences.dayKey(start, calendar: ny) == "2024-02-29", "timezone stable")
        check(secondUpgrade == nil, "migration idempotent")
    default: preconditionFailure("new format restore failed")
    }
default: preconditionFailure("legacy restore failed")
}
if case .missing = CSVHistoryFilterRecovery.recover(nil) { print("PASS: missing state") } else { preconditionFailure("missing") }
for invalid in ["not data" as Any, Data("{invalid".utf8) as Any] {
    if case .invalid = CSVHistoryFilterRecovery.recover(invalid) { print("PASS: corrupt state rejected") } else { preconditionFailure("corrupt") }
}
var reversed = original
reversed.startDay = "2024-03-01"
reversed.endDay = "2024-02-29"
if case .invalid = CSVHistoryFilterRecovery.recover(try! JSONEncoder().encode(reversed), calendar: tokyo) { print("PASS: reversed dates rejected") } else { preconditionFailure("reversed") }
var bad = original
bad.scope = "invalid"
if case .invalid = CSVHistoryFilterRecovery.recover(try! JSONEncoder().encode(bad), calendar: tokyo) { print("PASS: invalid scope rejected") } else { preconditionFailure("scope") }
// A valid replacement can be saved after an invalid preference is discarded.
if case .restored = CSVHistoryFilterRecovery.recover(oldData, calendar: tokyo) { print("PASS: valid retry after invalid") } else { preconditionFailure("retry") }
print("FIXED329: recovery tests passed")
