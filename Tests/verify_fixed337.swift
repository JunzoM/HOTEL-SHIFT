import Foundation
func check(_ condition: Bool, _ name: String) { precondition(condition, name); print("PASS: \(name)") }
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
let start = CSVHistoryFilterPreferences.dateForDayKey("2026-10-01", calendar: calendar)!
let end = CSVHistoryFilterPreferences.dateForDayKey("2026-10-04", calendar: calendar)!
let saved = CSVHistoryFilterPreferences(search: "元の検索", status: "成功", scope: "全件CSV", dateEnabled: true, start: start, end: end, preset: nil, startDay: "2026-10-01", endDay: "2026-10-04")
let bytes = try! JSONEncoder().encode(saved)
func recover(_ data: Any?) -> CSVHistoryFilterPreferences? {
    if case .restored(let p, _, _, _) = CSVHistoryFilterRecovery.recover(data, calendar: calendar) { return p }
    return nil
}
check(recover(bytes)?.search == "元の検索", "stored search can be restored")
check(recover(bytes)?.status == "成功", "stored status can be restored")
check(recover(bytes)?.scope == "全件CSV", "stored scope can be restored")
check(recover(bytes)?.startDay == "2026-10-01", "stored start day can be restored")
check(recover(bytes)?.endDay == "2026-10-04", "stored end day can be restored")
var edited = saved
edited.search = "編集中"
check(!CSVHistorySnapshotComparison.matches(current: edited, stored: bytes, calendar: calendar), "edited filters differ")
check(CSVHistorySnapshotComparison.matches(current: recover(bytes)!, stored: bytes, calendar: calendar), "reverted filters match")
check(recover(Data("broken".utf8)) == nil, "damaged snapshot cannot be reverted")
check(recover(nil) == nil, "missing snapshot cannot be reverted")
check(recover("wrong type") == nil, "wrong type cannot be reverted")
let suite = "hotelShift.fixed337.tests"
let defaults = UserDefaults(suiteName: suite)!
defaults.removePersistentDomain(forName: suite)
let timestampKey = "savedAt"
let time = Date(timeIntervalSince1970: 1_700_000_000)
CSVHistorySavedTimestamp.recordSuccessfulSave(in: defaults, key: timestampKey, at: time)
check(CSVHistorySavedTimestamp.read(from: defaults, key: timestampKey, hasValidSnapshot: true) == time, "existing save time is retained")
check(CSVHistorySnapshotComparison.matches(current: saved, stored: bytes, calendar: calendar), "saved snapshot remains unchanged")
defaults.removePersistentDomain(forName: suite)
print("FIXED337: 12 checks passed")
