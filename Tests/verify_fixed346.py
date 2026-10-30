"""FIXED346: regression checks against the current, extracted feedback policy."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
view = (root / 'HOTEL_SHIFT/Views/ShiftCalendarView.swift').read_text()
policy = (root / 'HOTEL_SHIFT/Models/CSVHistoryFeedbackPolicy.swift').read_text()
checks = {
 'policy extracted and referenced': 'enum CSVHistoryFeedbackPolicy' in policy and 'CSVHistoryFeedbackPolicy.shouldPresent(' in view,
 'dismissed fingerprint compared': 'dismissedKey == fingerprint' in policy and 'dismissedState == state' in policy,
 'active duplicate compared': 'activeMessage == message' in policy and 'activeSymbol == symbol' in policy and 'activeState == state' in policy,
 'state transition clears dismissal': 'if csvHistoryDismissedState != state {' in view,
 'dismiss button remembers dismissal': 'Button("閉じる") { dismissCSVHistoryFeedback(rememberDismissal: true) }' in view,
 'stale notification hidden': 'csvHistoryFeedbackState == csvHistorySaveStatusText' in view,
 'voiceover announced only when enabled': 'if UIAccessibility.isVoiceOverRunning {' in view,
 'voiceover announces current visible state': 'argument: message + "。" + csvHistorySaveStatusText' in view,
 'persistent status readable after dismissal': '.accessibilityLabel(csvHistoryAccessibleStatus)' in view,
 'timestamp included in accessibility status': '[csvHistorySaveStatusText, csvHistoryLastSavedText].compactMap' in view,
 'dismiss button separately reachable': '.accessibilityElement(children: .contain)' in view,
 'routine edit stays silent': 'Routine edits save silently' in view,
 'pending retry still present': 'saveCSVHistoryFilters(explicitRetry: true)' in view,
 'restore resets notification': 'csvHistoryDismissedFeedbackKey = nil' in view and 'csvHistoryFeedbackState = nil' in view,
}
for name, ok in checks.items():
 print(('PASS' if ok else 'FAIL'), name)
assert all(checks.values())
print(f'{len(checks)}/{len(checks)} checks passed')
