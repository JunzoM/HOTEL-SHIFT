#!/usr/bin/env python3
"""Execute the preview lookup and compare against the previous first-match semantics."""
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]

class PreviewLookupTests(unittest.TestCase):
    def test_lookup_matches_history_search(self):
        text = (ROOT / 'HOTEL_SHIFT/Views/StaffAndOtherViews.swift').read_text()
        start = text.index('    private func assignmentLookup(for dates:')
        end = text.index('    var body: some View {', start)
        method = text[start:end].replace('private func', 'func', 1)
        program = '''import Foundation
struct PreviewStore { let data: ShiftData; let selectedLocationID: UUID }
struct PreviewCheck {
 let store: PreviewStore
''' + method + '''
}
@main struct Runner {
 static func main() {
    let location = UUID(), otherLocation = UUID()
    let staffIDs = (0..<30).map { _ in UUID() }
    let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1))!
    let dates = (0..<31).map { Calendar.current.date(byAdding: .day, value: $0, to: start)! }
    var shifts: [ShiftAssignment] = []
    for id in staffIDs {
        for date in dates {
            shifts.append(ShiftAssignment(staffID: id, dateKey: date.shiftDateKey, type: .late, locationID: otherLocation))
            if Calendar.current.component(.day, from: date) % 3 != 0 {
                shifts.append(ShiftAssignment(staffID: id, dateKey: date.shiftDateKey, type: .day, note: "first", locationID: location))
                shifts.append(ShiftAssignment(staffID: id, dateKey: date.shiftDateKey, type: .night, note: "duplicate", locationID: location))
            }
            shifts.append(ShiftAssignment(staffID: id, dateKey: "2025-01-01", type: .off, locationID: location))
        }
    }
    let check = PreviewCheck(store: PreviewStore(data: ShiftData(locations: [], staff: [], assignments: shifts), selectedLocationID: location))
    let lookup = check.assignmentLookup(for: dates)
    for id in staffIDs + [UUID()] {
        for date in dates {
            let key = date.shiftDateKey
            let expected = shifts.first { $0.locationID == location && $0.staffID == id && $0.dateKey == key }
            precondition(lookup[id]?[key] == expected)
        }
    }
    precondition(lookup.values.allSatisfy { $0["2025-01-01"] == nil })
    print("961 cells: matching, missing, duplicate, other hotel and old month cases passed")
 }
}
'''
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'LookupTests.swift'
            source.write_text(program)
            binary = Path(tmp) / 'lookup-tests'
            result = subprocess.run(['swiftc', '-parse-as-library', '-module-cache-path', tmp + '/cache',
                str(ROOT / 'HOTEL_SHIFT/Models/ShiftModels.swift'), str(source), '-o', str(binary)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
if __name__ == '__main__': unittest.main()
