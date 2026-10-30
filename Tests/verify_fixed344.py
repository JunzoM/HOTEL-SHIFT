from pathlib import Path
s=Path(__file__).resolve().parents[1].joinpath('HOTEL_SHIFT/Views/ShiftCalendarView.swift').read_text()
checks={
 'dismissed message fingerprint': 'csvHistoryDismissedFeedbackKey = message + "|" + csvHistoryActionFeedbackSymbol',
 'dismissed state tracked': 'csvHistoryDismissedState = csvHistoryFeedbackState',
 'dismissal explicit': 'dismissCSVHistoryFeedback(rememberDismissal: true)',
 'same-state suppression': 'guard csvHistoryDismissedFeedbackKey != message + "|" + symbol else { return }',
 'new-state reset': 'if csvHistoryDismissedState != state {',
 'routine edit clears visible feedback': 'dismissCSVHistoryFeedback()\n        }\n        csvRetryHistoryExportURL = nil',
 'persistent status remains': '.accessibilityLabel(csvHistoryAccessibleStatus)',
}
for name, token in checks.items():
 assert token in s, name
 print('PASS',name)
print(f'{len(checks)}/{len(checks)} checks passed')
