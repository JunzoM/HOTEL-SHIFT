"""Exercise the actual PDF export method across main-actor suspension points."""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
source_path = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'HOTEL_SHIFT/Services/ShiftStore.swift'
source = source_path.read_text()
key = source[source.index('    private struct PDFPreparationKey:'):source.index('    private var preparedPDF:')].replace('private struct', 'struct')
method = source[source.index('    func exportShiftPDFAsync('):source.index('    // FIXED473:')]
harness = r'''
import Foundation
func check(_ condition: @autoclosure () -> Bool, _ message: String = "regression") {
    if !condition() { print("FAIL: " + message); exit(1) }
}
actor Gate {
    var entered = false
    var continuation: CheckedContinuation<URL?, Never>?
    func value() async -> URL? {
        await withCheckedContinuation { continuation = $0; entered = true }
    }
    func waitForEntry() async { while !entered { await Task.yield() } }
    func release(_ result: URL?) { continuation?.resume(returning: result); continuation = nil }
}
final class RenderSpy: @unchecked Sendable {
    let lock = NSLock()
    private var count = 0
    private var blocking = false
    let started = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    func waitForStart() { started.wait() }
    func blockNext() { lock.lock(); blocking = true; lock.unlock() }
    func increment() {
        lock.lock(); count += 1; let wait = blocking; blocking = false; lock.unlock()
        if wait { started.signal(); resume.wait() }
    }
    func reads() -> Int { lock.lock(); defer { lock.unlock() }; return count }
}
@MainActor final class Harness {
    struct Snapshot { var assignments: [Int] = [1] }
    struct Location { let name = "Hotel" }
    var storageWriteBlocked = false
    var selectedLocationID = UUID()
    var pdfRevision: UInt64 = 1
    var selectedStaff = [1]
    func pdfAssignments(month: Date) -> [Int] { data.assignments }
    var data = Snapshot()
    var selectedLocation: Location? = Location()
    nonisolated static let spy = RenderSpy()
    nonisolated static var fixture: URL { URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fixed554-test.pdf") }
    nonisolated static func renderShiftPDF(month: Date, paperSize: String, showStaffName: Bool,
        showWorkTime: Bool, showBreakTime: Bool, showMemo: Bool, showWage: Bool,
        department: String, periodMode: String, selectedStaff: [Int], assignments: [Int],
        selectedLocationID: UUID, locationName: String) -> URL? {
        spy.increment()
        return fixture
    }
KEY
    var preparedPDF: (key: PDFPreparationKey, task: Task<URL?, Never>)?
METHOD
    func seed(_ gate: Gate, month: Date) {
        preparedPDF = (PDFPreparationKey(month: month, options: ["A4横", "すべて", "1か月"],
            flags: [true,true,true,true,false], locationID: selectedLocationID, revision: pdfRevision,
            calendar: Calendar.current, exportDay: Calendar.current.startOfDay(for: Date())),
            Task { await gate.value() })
    }
}
@main struct Runner {
    @MainActor static func main() async throws {
        try Data("test".utf8).write(to: Harness.fixture)
        defer { try? FileManager.default.removeItem(at: Harness.fixture) }
        let month = Date(timeIntervalSince1970: 1790812800)
        // Each case pauses the actual method while it awaits the existing cached task.
        for scenario in 0..<6 {
            let h = Harness(), gate = Gate()
            h.seed(gate, month: month)
            let before = Harness.spy.reads()
            let request = Task { await h.exportShiftPDFAsync(month: month) }
            await gate.waitForEntry()
            switch scenario {
            case 1, 2: h.pdfRevision += 1; h.data.assignments = [2]
            case 3: h.selectedLocationID = UUID()
            case 4: request.cancel()
            case 5: h.storageWriteBlocked = true
            default: break
            }
            await gate.release(scenario == 2 ? nil : Harness.fixture)
            let result = await request.value
            check((scenario == 0) == (result != nil), "stale/cancelled result escaped: \(scenario)")
            check(Harness.spy.reads() == before, "stale cached key triggered a new render")
        }
        // A valid cache miss still renders successfully.
        let fresh = Harness()
        let before = Harness.spy.reads()
        let result = await fresh.exportShiftPDFAsync(month: month)
        check(result == Harness.fixture && Harness.spy.reads() == before + 1)
        // Also change state while a newly detached render is running.
        for scenario in 0..<3 {
            let h = Harness()
            Harness.spy.blockNext()
            let request = Task { await h.exportShiftPDFAsync(month: month) }
            await Task.detached { Harness.spy.waitForStart() }.value
            switch scenario {
            case 0: h.pdfRevision += 1
            case 1: h.selectedLocationID = UUID()
            default: request.cancel()
            }
            Harness.spy.resume.signal()
            let stale = await request.value
            check(stale == nil, "new render returned obsolete data")
        }
        print("PDF export: 10 async regression scenarios passed")
    }
}
'''.replace('KEY', key).replace('METHOD', method)
if 'private var preparedPDF: (id: UUID,' in source:
    harness = harness.replace('var preparedPDF: (key:', 'var preparedPDF: (id: UUID, key:')
    harness = harness.replace('preparedPDF = (PDFPreparationKey(', 'preparedPDF = (UUID(), PDFPreparationKey(')
with tempfile.TemporaryDirectory(prefix='fixed554-pdf-') as folder:
    path = Path(folder)
    (path/'main.swift').write_text(harness)
    subprocess.run(['swiftc', '-parse-as-library', str(path/'main.swift'), '-o', str(path/'verify')], check=True)
    subprocess.run([str(path/'verify')], check=True)
