import Foundation

struct FeedbackState {
    var status = "保存済み"
    var active: String? = nil
    var symbol: String? = nil
    var activeStatus: String? = nil
    var dismissed: String? = nil
    var dismissedStatus: String? = nil
    mutating func present(_ message: String, _ icon: String) -> Bool {
        if dismissedStatus != status { dismissed = nil; dismissedStatus = nil }
        let allowed = CSVHistoryFeedbackPolicy.shouldPresent(
            message: message, symbol: icon, state: status,
            dismissedKey: dismissed, dismissedState: dismissedStatus,
            activeMessage: active, activeSymbol: symbol, activeState: activeStatus)
        if allowed { active = message; symbol = icon; activeStatus = status }
        return allowed
    }
    mutating func close() {
        if let active { dismissed = active + "|" + (symbol ?? ""); dismissedStatus = activeStatus }
        active = nil; activeStatus = nil
    }
    mutating func silentEdit() { active = nil; activeStatus = nil }
}

var count = 0
func check(_ value: Bool, _ name: String) {
    precondition(value, name)
    count += 1
    print("PASS \(name)")
}
var s = FeedbackState()
check(s.present("保存しました", "check"), "first success notification")
check(!s.present("保存しました", "check"), "duplicate active notification suppressed")
s.close()
check(s.active == nil, "close clears active message")
check(!s.present("保存しました", "check"), "dismissed notification suppressed")
s.silentEdit()
check(!s.present("保存しました", "check"), "silent edit does not resurrect dismissal")
s.status = "保存保留"
check(s.present("日付を確認", "clock"), "pending state permits new notification")
check(!s.present("日付を確認", "clock"), "pending duplicate suppressed")
s.close()
check(!s.present("日付を確認", "clock"), "pending dismissal remembered")
s.status = "保存済み"
check(s.present("修正して保存", "check"), "return to saved state permits new message")
s.close()
check(!s.present("修正して保存", "check"), "recovery dismissal suppressed")
s.status = "復元エラー"
check(s.present("復元できません", "warning"), "recovery error overrides previous state")
s.status = "保存済み"
check(s.present("保存済みに戻す", "undo"), "revert notification appears after state transition")
check(s.present("手動保存", "check"), "different action in same state allowed")
print("\(count)/\(count) transition tests passed")
