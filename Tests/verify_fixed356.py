from pathlib import Path
s=(Path(__file__).resolve().parents[1]/'HOTEL_SHIFT/Views/ShiftCalendarView.swift').read_text()
checks={
 'revert requires confirmation': '.confirmationDialog("編集中の検索条件を破棄しますか？"' in s,
 'cancel is explicit': 'Button("キャンセル", role: .cancel) {\n                    // FIXED356: Cancel is intentionally side-effect free.\n                    confirmingCSVHistoryRevert = false' in s,
 'cancel accessibility': '検索条件を変更せず、確認画面を閉じます' in s,
 'confirm accessibility': '編集中の検索条件を破棄し、前回の保存内容を復元します。シフトやCSV履歴は変更しません' in s,
 'recovery validated on action': 'CSVHistoryFilterRecovery.recover(UserDefaults.standard.object(forKey: csvHistoryFiltersKey)) else {' in s,
 'failed recovery notice': '前回の保存内容を確認できませんでした。検索条件を初期化しました。' in s,
 'failed recovery resets UI': 'restoreCSVHistoryFilters()\n            csvHistoryRestoreNotice =' in s,
 'success clears write failure': 'csvHistoryWriteFailure = false\n        csvHistoryRestoreNotice = nil' in s,
 'success preserves timestamp': 'csvHistoryLastSavedAt = CSVHistorySavedTimestamp.read(' in s,
 'cancel not destructive': 'Button("キャンセル", role: .cancel)' in s,
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL'),name)
assert all(checks.values())
print(f'{len(checks)}/{len(checks)} checks passed')
