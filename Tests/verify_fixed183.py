"""Static regression guard for cross-facility backup validation."""
from pathlib import Path
source = (Path(__file__).resolve().parents[1] / 'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()
start = source.index('private static func isValidBackup(')
end = source.index('    func exportBackup()', start)
validation = source[start:end]
for check in (
    'Set(locations).count == locations.count',
    'Set(staffIDs).count == staffIDs.count',
    'let staffLocationByID = Dictionary(uniqueKeysWithValues:',
    '(assignment.locationID ?? staffLocation) == staffLocation',
    'staffLocationByID[request.staffID] == request.locationID',
    'staffLocationByID[staffID] == pattern.locationID',
    'pattern.weekdays.count == 7',
):
    assert check in validation, f'Missing validation: {check}'
assert source.index('Self.isValidBackup(decoded) else { return false }') < source.index('try encoded.write(to: fileURL, options: .atomic)')
print('FIXED183 cross-facility restore static regression checks PASS')
