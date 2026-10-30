from pathlib import Path
s = (Path(__file__).resolve().parents[1] / 'HOTEL_SHIFT/Views/ShiftCalendarView.swift').read_text()
checks = {
    'state stored': '@State private var csvHistoryFeedbackState: String? = nil',
    'feedback captured': 'csvHistoryFeedbackState = state',
    'stale feedback hidden': 'csvHistoryFeedbackState == csvHistorySaveStatusText',
    'pending clears old': 'if !wasPending { dismissCSVHistoryFeedback() }',
    'dismiss clears state': 'csvHistoryFeedbackState = nil',
    'status announced': 'message + "。" + csvHistorySaveStatusText',
}
for name, needle in checks.items():
    assert needle in s, name
    print('PASS', name)
print(f'{len(checks)}/{len(checks)} static checks passed')
