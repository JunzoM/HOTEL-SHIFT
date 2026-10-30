"""Static regression checks for FIXED339 SwiftUI feedback wiring."""
from pathlib import Path
s = (Path(__file__).resolve().parents[1] / 'HOTEL_SHIFT/Views/ShiftCalendarView.swift').read_text()
checks = {
    'success feedback': 'showCSVHistoryFeedback("検索条件を保存しました。"' in s,
    'pending feedback': 'showCSVHistoryFeedback("保存を保留しました。' in s,
    'revert feedback': 'showCSVHistoryFeedback("保存済みの検索条件に戻しました。"' in s,
    'dismiss action': 'Button("閉じる") { self.csvHistoryActionFeedback = nil }' in s,
    'reset on restore': 'csvHistoryActionFeedback = nil\n        csvHistorySavePending = false' in s,
    'confirmation preserved': 'confirmingCSVHistoryRevert = true' in s,
    'status remains': 'Text(csvHistorySaveStatusText)' in s,
}
for label, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ': ' + label)
assert all(checks.values())
