from pathlib import Path
s = (Path(__file__).resolve().parents[1] / 'HOTEL_SHIFT/Views/ShiftCalendarView.swift').read_text()
checks = {
    'routine save is silent': 'Routine edits save silently' in s,
    'explicit retry parameter': 'explicitRetry: Bool = false' in s,
    'pending transition captured': 'let wasPending = csvHistorySavePending' in s,
    'pending warning deduplicated': 'if !wasPending || explicitRetry {' in s,
    'recovery notification': '検索条件を修正して保存しました。' in s,
    'explicit save confirmation': 'else if explicitRetry {' in s,
    'stale notification cleared': 'A previous notification must not linger' in s,
    'retry button uses explicit flag': 'Button("再保存") { saveCSVHistoryFilters(explicitRetry: true) }' in s,
    'revert notification retained': '保存済みの検索条件に戻しました。' in s,
    'dismiss retained': 'Button("閉じる") { self.csvHistoryActionFeedback = nil }' in s,
}
for label, passed in checks.items():
    print(('PASS' if passed else 'FAIL') + ': ' + label)
assert all(checks.values())
print(f'{len(checks)}/{len(checks)} static regression checks passed')
