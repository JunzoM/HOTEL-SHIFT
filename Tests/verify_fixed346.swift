import Foundation

struct Session {
    var state = "保存済み"
    var active: String? = nil
    var symbol: String? = nil
    var activeState: String? = nil
    var dismissed: String? = nil
    var dismissedState: String? = nil
    mutating func notify(_ message: String, _ icon: String) -> Bool {
        if dismissedState != state { dismissed = nil; dismissedState = nil }
        let should = CSVHistoryFeedbackPolicy.shouldPresent(
            message: message, symbol: icon, state: state,
            dismissedKey: dismissed, dismissedState: dismissedState,
            activeMessage: active, activeSymbol: symbol, activeState: activeState)
        if should { active = message; symbol = icon; activeState = state }
        return should
    }
    mutating func close() {
        if let active { dismissed = active + "|" + (symbol ?? ""); dismissedState = activeState }
        active = nil; activeState = nil
    }
    mutating func editSilently() { active = nil; activeState = nil }
    var visible: Bool { active != nil && activeState == state }
}
var count = 0
func check(_ condition: Bool, _ label: String) {
    precondition(condition, label)
    count += 1
    print("PASS", label)
}
var s = Session()
check(s.notify("保存しました", "check"), "initial save")
check(s.visible, "save visible")
check(!s.notify("保存しました", "check"), "active duplicate suppressed")
s.close()
check(!s.visible, "dismiss hides notification")
check(!s.notify("保存しました", "check"), "dismissed notification suppressed")
s.editSilently()
check(!s.notify("保存しました", "check"), "silent edit does not resurrect")
s.state = "保存保留"
check(!s.visible, "old success not visible while pending")
check(s.notify("期間を確認", "clock"), "pending shown")
check(!s.notify("期間を確認", "clock"), "pending duplicate suppressed")
s.close()
check(!s.notify("期間を確認", "clock"), "dismissed pending suppressed")
s.state = "保存済み"
check(s.notify("修正して保存", "check"), "recovered save shown")
s.state = "復元エラー"
check(!s.visible, "stale recovered save hidden")
check(s.notify("復元できません", "warning"), "restore error shown")
s.state = "保存済み"
check(s.notify("条件を戻しました", "undo"), "revert shown")
check(s.notify("手動保存", "check"), "different explicit action shown")
check(!s.notify("手動保存", "check"), "new action duplicate suppressed")
print("\(count)/\(count) transition checks passed")
