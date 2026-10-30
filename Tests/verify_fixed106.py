from pathlib import Path
s = (Path(__file__).parents[1] / 'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()
start = s.index('    func importBackup(from url: URL) -> Bool {')
end = s.index('    // Batch rapid edits into a single atomic write.', start)
restore = s[start:end]
assert 'Self.isValidBackup(decoded)' in restore
assert 'hotel-shift-before-restore-' in restore
assert restore.index('try manager.copyItem') < restore.index('try encoded.write(to: fileURL')
assert restore.index('try encoded.write(to: fileURL') < restore.index('data = migrated')
assert 'return false' in restore
assert 'guard !storageWriteBlocked else { return nil }' in s
print('FIXED106 restore safeguards: OK')
