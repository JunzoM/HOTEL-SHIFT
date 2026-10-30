from pathlib import Path
s = (Path(__file__).resolve().parents[1] / 'HOTEL_SHIFT/Views/ShiftCalendarView.swift').read_text()
checks = {
    'voiceover announcement gated': 'if UIAccessibility.isVoiceOverRunning {' in s,
    'announcement posts meaningful feedback': 'UIAccessibility.post(notification: .announcement, argument: message)' in s,
    'duplicate feedback suppressed': 'guard csvHistoryActionFeedback != message || csvHistoryActionFeedbackSymbol != symbol else { return }' in s,
    'routine saves remain silent': 'Routine edits save silently' in s and 'csvHistoryActionFeedback = nil' in s,
    'action dismiss has voiceover label': '.accessibilityLabel("検索条件の操作通知を閉じる")' in s,
    'restore dismiss has voiceover label': '.accessibilityLabel("検索条件の復元エラー通知を閉じる")' in s,
    'feedback controls individually reachable': '.accessibilityElement(children: .contain)' in s,
    'retry button hint': '.accessibilityHint("修正した検索条件の保存を再試行します")' in s,
    'revert remains available': 'revertCSVHistoryFiltersToSaved()' in s,
}
for name, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ': ' + name)
assert all(checks.values())
print(f'{len(checks)}/{len(checks)} static regression checks passed')
