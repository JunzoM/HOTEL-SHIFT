import Foundation
@main struct Verify348 {
 static func main() {
  var assertions = 0
  func check(_ value: Bool, _ name: String) { precondition(value, name); assertions += 1 }
  let saved = CSVHistoryFeedbackDecision.evaluate(message: "検索条件を保存しました。", symbol: "check", state: "保存済み", dismissedKey: nil, dismissedState: nil, activeMessage: nil, activeSymbol: nil, activeState: nil)
  check(saved.shouldPresent, "save accepted")
  check(saved.visibleMessage == "検索条件を保存しました。", "visual save")
  check(saved.announcement == "検索条件を保存しました。保存済み", "spoken save")
  let duplicate = CSVHistoryFeedbackDecision.evaluate(message: "検索条件を保存しました。", symbol: "check", state: "保存済み", dismissedKey: nil, dismissedState: nil, activeMessage: "検索条件を保存しました。", activeSymbol: "check", activeState: "保存済み")
  check(!duplicate.shouldPresent, "duplicate rejected")
  check(duplicate.visibleMessage == nil && duplicate.announcement == nil, "duplicate silent and hidden")
  let dismissed = CSVHistoryFeedbackDecision.evaluate(message: "検索条件を保存しました。", symbol: "check", state: "保存済み", dismissedKey: "検索条件を保存しました。|check", dismissedState: "保存済み", activeMessage: nil, activeSymbol: nil, activeState: nil)
  check(!dismissed.shouldPresent, "dismissed rejected")
  check(dismissed.announcement == nil, "dismissed silent")
  let pending = CSVHistoryFeedbackDecision.evaluate(message: "保存を保留しました。", symbol: "clock", state: "保存保留", dismissedKey: "検索条件を保存しました。|check", dismissedState: "保存済み", activeMessage: "検索条件を保存しました。", activeSymbol: "check", activeState: "保存済み")
  check(pending.shouldPresent, "new state accepted")
  check(pending.visibleMessage == "保存を保留しました。", "pending visible")
  check(pending.announcement == "保存を保留しました。保存保留", "pending spoken")
  let restored = CSVHistoryFeedbackDecision.evaluate(message: "保存済み", symbol: "undo", state: "保存済み", dismissedKey: nil, dismissedState: nil, activeMessage: nil, activeSymbol: nil, activeState: nil)
  check(restored.announcement == "保存済み", "no duplicate spoken status")
  let error = CSVHistoryFeedbackDecision.evaluate(message: "復元できませんでした。", symbol: "warning", state: "復元エラー", dismissedKey: nil, dismissedState: nil, activeMessage: nil, activeSymbol: nil, activeState: nil)
  check(error.shouldPresent && error.announcement == "復元できませんでした。復元エラー", "error announced")
  let recovered = CSVHistoryFeedbackDecision.evaluate(message: "検索条件を修正して保存しました。", symbol: "check", state: "保存済み", dismissedKey: "保存を保留しました。|clock", dismissedState: "保存保留", activeMessage: "保存を保留しました。", activeSymbol: "clock", activeState: "保存保留")
  check(recovered.shouldPresent, "recovery accepted")
  check(recovered.announcement == "検索条件を修正して保存しました。保存済み", "recovery spoken")
  print("FIXED348: \(assertions)/\(assertions) checks passed")
 }
}
