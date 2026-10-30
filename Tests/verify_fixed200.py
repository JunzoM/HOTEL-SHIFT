"""FIXED200 cross-feature source invariants (static checks, not iPad tests)."""
from pathlib import Path
root = Path(__file__).resolve().parents[1] / 'HOTEL_SHIFT'
store = (root / 'Services/ShiftStore.swift').read_text()
views = (root / 'Views/StaffAndOtherViews.swift').read_text()
checks = {
    'damaged saved file blocks writes': 'storageWriteBlocked = true' in store and 'guard !storageWriteBlocked, needsSave else { return }' in store,
    'saved data uses atomic writes': 'try encoded.write(to: fileURL, options: .atomic)' in store,
    'backup restore validates data': 'Self.isValidBackup(decoded) else { return false }' in store,
    'PDF export exists': 'func exportShiftPDF(' in store,
    'PDF preview uses PDFKit': 'import PDFKit' in views and 'PDFView()' in views,
    'shift CSV uses unique name': 'シフト一覧_\\(Date().shiftDateKey)_\\(UUID().uuidString).csv' in store,
    'requests JSON uses unique name': '希望休申請_\\(Date().shiftDateKey)_\\(UUID().uuidString).json' in store,
    'backup JSON uses unique name': 'HOTEL_SHIFT_backup_\\(Date().shiftDateKey)_\\(UUID().uuidString).json' in store,
    'monthly payroll CSV uses unique name': '月間勤務実績_\\(monthPrefix)_\\(UUID().uuidString).csv' in views,
}
for label, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ' ' + label)
assert all(checks.values()), 'Cross-feature static check failed'
