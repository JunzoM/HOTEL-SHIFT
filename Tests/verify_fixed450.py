from pathlib import Path
p = Path(__file__).resolve().parents[1] / 'HOTEL_SHIFT/Views/ShiftCalendarView.swift'
s = p.read_text()
assert 'private func csvHistoryPresetButton(_ preset: String)' in s
assert '.buttonStyle(csvHistoryDateFilterEnabled && csvHistorySelectedPreset == preset ?' not in s
assert 'csvHistoryPresetButton(preset)' in s
assert '.buttonStyle(.borderedProminent)' in s
assert '.buttonStyle(.bordered)' in s
assert 'applyCSVHistoryDatePreset(preset)' in s
print('FIXED450: PASS')
