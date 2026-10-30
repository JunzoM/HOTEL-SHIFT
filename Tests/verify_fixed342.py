from pathlib import Path
s = (Path(__file__).resolve().parents[1] / 'HOTEL_SHIFT/Views/ShiftCalendarView.swift').read_text()
checks = {
    'status accessible after dismiss': 'private var csvHistoryAccessibleStatus: String' in s and '.accessibilityLabel(csvHistoryAccessibleStatus)' in s,
    'status includes timestamp': '[csvHistorySaveStatusText, csvHistoryLastSavedText].compactMap' in s,
    'status is static accessible element': '.accessibilityAddTraits(.isStaticText)' in s,
    'announcement matches visible status': 'argument: message + "。" + csvHistorySaveStatusText' in s,
    'notification has explicit accessibility label': '.accessibilityLabel("操作通知：" + csvHistoryActionFeedback)' in s,
    'dismiss does not mutate persistence': 'private func dismissCSVHistoryFeedback() {\n        csvHistoryActionFeedback = nil\n    }' in s,
    'dismiss helper wired': 'Button("閉じる") { dismissCSVHistoryFeedback() }' in s,
    'dismiss explains status persistence': '通知のみ閉じます。保存状態は引き続き確認できます' in s,
    'restore notice dismiss explains behavior': '通知のみ閉じます。検索条件の保存状態は変わりません' in s,
    'voiceover gate remains': 'if UIAccessibility.isVoiceOverRunning {' in s,
    'pending save logic remains': 'csvHistorySavePending = true' in s,
    'revert logic remains': 'revertCSVHistoryFiltersToSaved()' in s,
}
for label, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ': ' + label)
assert all(checks.values())
print(f'{len(checks)}/{len(checks)} static checks passed')
