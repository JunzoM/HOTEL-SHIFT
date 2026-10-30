from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
tests = r'''
let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn:"/\\:?%*|\"<>"))
let examples = ["ホテル", "", " /:\n\0 ", String(repeating:"ホテル",count:1000),
    String(repeating:"a",count:1000),String(repeating:"👨‍👩‍👧‍👦",count:100),"..", "a/b\\c\0d\ne"]
let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
defer { try? FileManager.default.removeItem(at:folder) }
for text in examples {
    let name = ExportFilename.component(text)
    assert(!name.isEmpty && name.utf8.count <= 120)
    assert(name.unicodeScalars.allSatisfy { !invalid.contains($0) })
    let filename = name + "_シフト_2026-10_上下半月分割_" + UUID().uuidString + ".pdf"
    assert(filename.utf8.count < 255)
    try Data("test".utf8).write(to:folder.appendingPathComponent(filename))
}
assert(ExportFilename.component("ホテル") == "ホテル")
print("Filename: 9 Unicode/long-name cases passed, including actual file writes")
'''
with tempfile.TemporaryDirectory(prefix='fixed555-filename-') as folder:
    path=Path(folder)/'test.swift'
    path.write_text('import Foundation\n@main struct Runner { static func main() throws {\n'+tests+'\n} }\n')
    subprocess.run(['swiftc','-parse-as-library',str(root/'HOTEL_SHIFT/Models/ShiftModels.swift'),str(path),'-o',str(Path(folder)/'test')],check=True)
    subprocess.run([str(Path(folder)/'test')],check=True)
