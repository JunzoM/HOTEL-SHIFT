from pathlib import Path
source = (Path(__file__).resolve().parents[1] / 'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()
assert 'storageWarning = "変更内容を保存用データに変換できませんでした' in source
assert 'storageWarning = "変更内容を端末に保存できませんでした' in source
assert 'needsSave = false\n            // Clear transient errors' in source
assert 'storageWarning = nil\n        } catch {' in source
assert 'guard !storageWriteBlocked, needsSave else { return }' in source
assert 'try encoded.write(to: fileURL, options: .atomic)' in source
print('FIXED182 save failure regression checks PASS')
