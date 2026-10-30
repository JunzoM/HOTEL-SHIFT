import Foundation

let suite = "hotel.shift.fixed360.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let key = "csv.filters", timeKey = "csv.savedAt"
let now = Date(timeIntervalSince1970: 1_700_000_000)
let originalTime = Date(timeIntervalSince1970: 1_700_000_100)
let updatedTime = Date(timeIntervalSince1970: 1_700_000_200)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label)
    checks += 1
}
func snapshot(_ search: String) -> Data {
    let preferences = CSVHistoryFilterPreferences(search: search, status: "すべて", scope: "すべて", dateEnabled: false, start: now, end: now, preset: nil, startDay: CSVHistoryFilterPreferences.dayKey(now), endDay: CSVHistoryFilterPreferences.dayKey(now))
    return try! JSONEncoder().encode(preferences)
}
let original = snapshot("original")
let edited = snapshot("edited")
let warning = "保存された検索条件を復元できませんでした"

check({ if case .missing = CSVHistoryFilterRecovery.recover(defaults.object(forKey: key)) { return true }; return false }(), "initial missing")
check({ if case .saved = CSVHistoryVerifiedWriter.save(original, in: defaults, key: key) { return true }; return false }(), "initial save")
CSVHistorySavedTimestamp.recordSuccessfulSave(in: defaults, key: timeKey, at: originalTime)
check(CSVHistoryFailedSaveInspection.inspect(defaults: defaults, filtersKey: key, timestampKey: timeKey).hasSavedSnapshot, "initial valid snapshot")
check(CSVHistoryFailedSaveInspection.inspect(defaults: defaults, filtersKey: key, timestampKey: timeKey).lastSavedAt == originalTime, "initial timestamp")

// A failed write must restore the last valid snapshot and preserve its timestamp.
let failure = CSVHistoryVerifiedWriter.save(edited, in: defaults, key: key, write: { store, name, _ in store.set(Data("corrupted".utf8), forKey: name) })
check({ if case .failed(restoredPrevious: true) = failure { return true }; return false }(), "rollback succeeds")
check(defaults.data(forKey: key) == original, "original snapshot preserved")
check(CSVHistorySavedTimestamp.read(from: defaults, key: timeKey, hasValidSnapshot: true) == originalTime, "timestamp unchanged on failure")
let failedTransition = CSVHistoryRestoreRetryTransition.evaluate(previousNotice: warning, result: .writeFailed)
check(failedTransition.restoreNotice == warning && !failedTransition.saved, "restore warning survives failed save")
check(failedTransition.feedback == nil, "no false success message")

// An invalid date/input must not change storage or its timestamp.
let invalidTransition = CSVHistoryRestoreRetryTransition.evaluate(previousNotice: warning, result: .invalidInput)
check(invalidTransition.restoreNotice == warning && !invalidTransition.saved, "invalid input preserves warning")
check(defaults.data(forKey: key) == original, "invalid input leaves stored snapshot")

// Explicit revert restores saved filters without recording a new save.
let revert = CSVHistoryRevertDecision.evaluate(confirmed: true, stored: defaults.object(forKey: key))
check({ if case .restored(let preferences, _, _) = revert { return preferences.search == "original" }; return false }(), "revert restores original")
check(CSVHistorySavedTimestamp.read(from: defaults, key: timeKey, hasValidSnapshot: true) == originalTime, "revert does not change timestamp")
check({ if case .cancelled = CSVHistoryRevertDecision.evaluate(confirmed: false, stored: defaults.object(forKey: key)) { return true }; return false }(), "cancel is safe")

// A verified retry clears the warning and permits a new saved timestamp.
check({ if case .saved = CSVHistoryVerifiedWriter.save(edited, in: defaults, key: key) { return true }; return false }(), "verified retry")
let recovered = CSVHistoryRestoreRetryTransition.evaluate(previousNotice: warning, result: .verified)
check(recovered.saved && recovered.restoreNotice == nil, "verified retry clears warning")
check(recovered.feedback == "検索条件を再設定して保存しました。", "recovery feedback")
CSVHistorySavedTimestamp.recordSuccessfulSave(in: defaults, key: timeKey, at: updatedTime)
check(CSVHistoryFailedSaveInspection.inspect(defaults: defaults, filtersKey: key, timestampKey: timeKey).lastSavedAt == updatedTime, "timestamp updates only after verified save")
check({ if case .restored(let preferences, _, _, _) = CSVHistoryFilterRecovery.recover(defaults.object(forKey: key)) { return preferences.search == "edited" }; return false }(), "new snapshot survives reload")

// Notification deduplication and VoiceOver presentation share the same policy.
check(CSVHistoryFeedbackPolicy.shouldPresent(message: "検索条件を再設定して保存しました。", symbol: "checkmark.circle.fill", state: "saved", dismissedKey: nil, dismissedState: nil, activeMessage: nil, activeSymbol: nil, activeState: nil), "new notification permitted")
check(!CSVHistoryFeedbackPolicy.shouldPresent(message: "検索条件を再設定して保存しました。", symbol: "checkmark.circle.fill", state: "saved", dismissedKey: nil, dismissedState: nil, activeMessage: "検索条件を再設定して保存しました。", activeSymbol: "checkmark.circle.fill", activeState: "saved"), "duplicate suppressed")
check(CSVHistoryFeedbackPolicy.shouldPresent(message: "保存を保留しています", symbol: "exclamationmark.triangle.fill", state: "pending", dismissedKey: nil, dismissedState: nil, activeMessage: "検索条件を再設定して保存しました。", activeSymbol: "checkmark.circle.fill", activeState: "saved"), "state transition permits notification")

// Invalid snapshots cannot masquerade as saved, even if a timestamp remains.
defaults.set(Data("invalid".utf8), forKey: key)
let inspection = CSVHistoryFailedSaveInspection.inspect(defaults: defaults, filtersKey: key, timestampKey: timeKey)
check(!inspection.hasSavedSnapshot && inspection.lastSavedAt == nil, "corrupt snapshot hides stale timestamp")
print("FIXED360: \(checks)/\(checks) passed")
