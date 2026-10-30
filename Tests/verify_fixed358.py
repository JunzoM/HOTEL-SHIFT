from pathlib import Path
s = Path('HOTEL_SHIFT/Views/ShiftCalendarView.swift').read_text()
start = s.index('private func saveCSVHistoryFilters(')
end = s.index('private func revertCSVHistoryFiltersToSaved()', start)
f = s[start:end]
checks = {
    'restore error captured before save': 'let wasRestoreError = csvHistoryRestoreNotice != nil' in f,
    'failed encoding does not clear restore notice': f.index('guard let data =') < f.index('csvHistoryRestoreNotice = nil'),
    'failed write does not clear restore notice': f.index('guard case .saved = writeResult') < f.index('csvHistoryRestoreNotice = nil'),
    'success clears stale restore notice': 'csvHistorySavePending = false\n        // FIXED358:' in f and 'csvHistoryRestoreNotice = nil' in f,
    'notice cleared before feedback': f.index('csvHistoryRestoreNotice = nil') < f.index('if wasWriteFailure {\n            showCSVHistoryFeedback'),
    'successful recovery announced': 'showCSVHistoryFeedback("検索条件を再設定して保存しました。"' in f,
    'successful recovery branch before ordinary pending': f.index('else if wasRestoreError') < f.index('else if wasPending'),
    'restore failure still announces error': 'csvHistoryRestoreNotice = "保存された検索条件を復元できなかったため' in s,
    'restoring saved snapshot clears error': 'csvHistoryRestoreNotice = nil\n        csvHistoryHasSavedSnapshot = true' in s,
}
for name, ok in checks.items():
    assert ok, name
print(f'FIXED358: {len(checks)}/{len(checks)} static regression checks passed')
