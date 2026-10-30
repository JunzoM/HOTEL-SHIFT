import Foundation
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label)
    checks += 1
}
let notice = "保存された検索条件を復元できませんでした"
let invalid = CSVHistoryRestoreRetryTransition.evaluate(previousNotice: notice, result: .invalidInput)
check(invalid.restoreNotice == notice, "invalid input preserves warning")
check(invalid.feedback == nil, "invalid input no success feedback")
check(!invalid.saved, "invalid input not saved")
let failed = CSVHistoryRestoreRetryTransition.evaluate(previousNotice: invalid.restoreNotice, result: .writeFailed)
check(failed.restoreNotice == notice, "write failure preserves warning")
check(failed.feedback == nil, "write failure no success feedback")
check(!failed.saved, "write failure not saved")
let success = CSVHistoryRestoreRetryTransition.evaluate(previousNotice: failed.restoreNotice, result: .verified)
check(success.restoreNotice == nil, "verified save clears warning")
check(success.feedback == "検索条件を再設定して保存しました。", "recovery success message")
check(success.saved, "verified saved")
let normal = CSVHistoryRestoreRetryTransition.evaluate(previousNotice: nil, result: .verified)
check(normal.restoreNotice == nil, "normal save no warning")
check(normal.feedback == nil, "normal save no recovery message")
check(normal.saved, "normal save succeeds")
let again = CSVHistoryRestoreRetryTransition.evaluate(previousNotice: success.restoreNotice, result: .writeFailed)
check(again.restoreNotice == nil, "no stale warning after recovery")
check(again.feedback == nil, "failure no success notification")
check(!again.saved, "failed retry not saved")
print("FIXED359: \(checks)/\(checks) restore-retry transition tests passed")
