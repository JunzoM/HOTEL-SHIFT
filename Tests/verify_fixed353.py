from pathlib import Path
p=Path(__file__).resolve().parents[1] / 'HOTEL_SHIFT/Views/ShiftCalendarView.swift'
s=p.read_text()
checks={
 'failure specific heading':'csvHistoryWriteFailure ? "検索条件の保存に失敗しました"' in s,
 'previous snapshot guidance':'前回の正常な検索条件は保持されています' in s,
 'no snapshot guidance':'保存済みの検索条件がありません' in s,
 'retry offered':'Button("再保存") { saveCSVHistoryFilters(explicitRetry: true) }' in s,
 'revert offered':'Button("保存済みの条件に戻す", role: .destructive)' in s,
 'revert handles write failure':'csvHistorySavePending || csvHistoryWriteFailure || !csvHistoryMatchesSavedSnapshot' in s,
 'revert clears failure':'csvHistoryWriteFailure = false' in s[s.index('private func revertCSVHistoryFiltersToSaved()'):s.index('private func restoreCSVHistoryFilters()')],
 'status prioritizes failure':'if csvHistoryWriteFailure { return "保存エラー' in s,
}
for name,ok in checks.items():
 print(('PASS' if ok else 'FAIL')+' '+name)
assert all(checks.values())
print(f'FIXED353: {len(checks)}/{len(checks)} checks passed')
