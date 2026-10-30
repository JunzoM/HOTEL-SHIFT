import Foundation

var passed = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), "FAIL: \(label)")
    passed += 1
    print("PASS: \(label)")
}
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
let suite = "HOTEL_SHIFT_FIXED350_\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let filterKey = "filters"
let timestampKey = "savedAt"
let first = CSVHistoryFilterPreferences.dateForDayKey("2026-10-20", calendar: calendar)!
let last = CSVHistoryFilterPreferences.dateForDayKey("2026-10-25", calendar: calendar)!
func preferences(_ search: String, _ endDay: String = "2026-10-25") -> CSVHistoryFilterPreferences {
    CSVHistoryFilterPreferences(search: search, status: "成功", scope: "全件CSV", dateEnabled: true,
        start: first, end: last, preset: nil, startDay: "2026-10-20", endDay: endDay)
}
let time = Date(timeIntervalSince1970: 1_793_000_000)
func save(_ value: CSVHistoryFilterPreferences, at date: Date) -> Bool {
    guard let data = try? JSONEncoder().encode(value),
          CSVHistoryFilterPreferences.validated(from: data, calendar: calendar) != nil else { return false }
    defaults.set(data, forKey: filterKey)
    CSVHistorySavedTimestamp.recordSuccessfulSave(in: defaults, key: timestampKey, at: date)
    return true
}
func feedback(_ message: String, _ state: String, dismissed: String? = nil, dismissedState: String? = nil, active: String? = nil, activeState: String? = nil) -> CSVHistoryFeedbackDecision {
    CSVHistoryFeedbackDecision.evaluate(message: message, symbol: "checkmark.circle", state: state,
        dismissedKey: dismissed, dismissedState: dismissedState,
        activeMessage: active, activeSymbol: "checkmark.circle", activeState: activeState)
}
check(save(preferences("予約"), at: time), "save valid filters")
check(CSVHistorySnapshotComparison.matches(current: preferences("予約"), stored: defaults.object(forKey: filterKey), calendar: calendar), "saved filters match")
check(CSVHistorySavedTimestamp.read(from: defaults, key: timestampKey, hasValidSnapshot: true) == time, "saved timestamp persists")
let changed = preferences("予約変更")
check(!CSVHistorySnapshotComparison.matches(current: changed, stored: defaults.object(forKey: filterKey), calendar: calendar), "edited filters are unsaved")
check(!save(preferences("不正", "2026-10-19"), at: time.addingTimeInterval(30)), "invalid date cannot overwrite snapshot")
check(CSVHistorySavedTimestamp.read(from: defaults, key: timestampKey, hasValidSnapshot: true) == time, "pending edit keeps timestamp")
let pending = feedback("保存を保留しました", "保存保留")
check(pending.shouldPresent && pending.visibleMessage == "保存を保留しました", "pending visual feedback")
check(pending.announcement?.contains("保存保留") == true, "pending VoiceOver status")
let key = "保存を保留しました|checkmark.circle"
check(!feedback("保存を保留しました", "保存保留", dismissed: key, dismissedState: "保存保留").shouldPresent, "dismissed feedback suppressed")
check(feedback("検索条件を保存しました", "保存済み", dismissed: key, dismissedState: "保存保留").shouldPresent, "state change allows new feedback")
let newTime = time.addingTimeInterval(120)
check(save(changed, at: newTime), "corrected filters saved")
check(CSVHistorySnapshotComparison.matches(current: changed, stored: defaults.object(forKey: filterKey), calendar: calendar), "corrected filters match snapshot")
check(CSVHistorySavedTimestamp.read(from: defaults, key: timestampKey, hasValidSnapshot: true) == newTime, "corrected save advances timestamp")
let success = feedback("検索条件を保存しました", "保存済み")
check(success.visibleMessage == "検索条件を保存しました" && success.announcement?.contains("保存済み") == true, "success display and voice agree")
check(!feedback("検索条件を保存しました", "保存済み", active: "検索条件を保存しました", activeState: "保存済み").shouldPresent, "active feedback not duplicated")
if case .restored(let restored, _, _, _) = CSVHistoryFilterRecovery.recover(defaults.object(forKey: filterKey), calendar: calendar) {
    check(restored.search == "予約変更", "restart restores corrected filters")
} else { preconditionFailure("valid snapshot did not restore") }
defaults.set(Data("corrupt".utf8), forKey: filterKey)
if case .invalid = CSVHistoryFilterRecovery.recover(defaults.object(forKey: filterKey), calendar: calendar) {
    check(true, "corrupt snapshot detected")
} else { preconditionFailure("corrupt snapshot accepted") }
defaults.removeObject(forKey: filterKey)
CSVHistorySavedTimestamp.clear(in: defaults, key: timestampKey)
check(CSVHistorySavedTimestamp.read(from: defaults, key: timestampKey, hasValidSnapshot: true) == nil, "recovery clears stale timestamp")
check(save(preferences("復旧"), at: newTime.addingTimeInterval(60)), "save after recovery")
check(CSVHistorySnapshotComparison.matches(current: preferences("復旧"), stored: defaults.object(forKey: filterKey), calendar: calendar), "recovered snapshot matches")
print("FIXED350: \(passed)/\(passed) integration checks passed")
