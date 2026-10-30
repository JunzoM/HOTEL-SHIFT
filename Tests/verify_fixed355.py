from pathlib import Path
s=(Path(__file__).resolve().parents[1]/'HOTEL_SHIFT/Views/ShiftCalendarView.swift').read_text()
checks={
 'restore button explicit': 'Label("前回の保存内容に戻す"' in s,
 'restore confirmation': '編集中の検索条件を破棄しますか？' in s,
 'restore preserves timestamp explanation': '最終保存日時も変更しません' in s,
 'retry button explicit': 'Button("現在の条件を再保存")' in s,
 'retry calls save': 'saveCSVHistoryFilters(explicitRetry: true)' in s,
 'retry accessibility': '画面に表示されている検索条件を保存します' in s,
 'restore accessibility': '編集中の変更を破棄し、前回保存した検索条件を読み込みます' in s,
 'saved snapshot guard': 'if csvHistoryHasSavedSnapshot &&' in s,
 'restore uses recovery': 'CSVHistoryFilterRecovery.recover(UserDefaults.standard.object(forKey: csvHistoryFiltersKey))' in s,
 'retry disabled invalid dates': '.disabled(!csvHistoryDateRangeValid)' in s,
 'preserves shift data note': 'シフトやCSV履歴は削除されません' in s,
}
for name,ok in checks.items():
 print(('PASS' if ok else 'FAIL'),name)
assert all(checks.values())
print(f'{len(checks)}/{len(checks)} passed')
