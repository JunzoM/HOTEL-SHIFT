#!/usr/bin/env python3
"""Run the production async export wrapper with a controlled renderer.
Checks that rendering leaves the main thread and receives an immutable snapshot.
The actual UIKit renderer is checked separately against the iOS SDK.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
STORE = (ROOT / 'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()

class AsyncPDFTests(unittest.TestCase):
    def test_background_snapshot(self):
        start = STORE.index('    func exportShiftPDF(')
        end = STORE.index('    nonisolated private static func renderShiftPDF(', start)
        wrapper = STORE[start:end]
        cache_start = STORE.index('    private struct PDFPreparationKey:')
        cache_end = STORE.index('    @Published var selectedLocationID:', cache_start)
        cache_state = STORE[cache_start:cache_end]
        renderer_signature = STORE[end:STORE.index(' {', end)]
        program = '''import Foundation
@MainActor final class TestStore {
    private(set) var pdfRevision: UInt64 = 0
    var selectedStaff: [StaffMember]
    var data: ShiftData
    var selectedLocationID: UUID
    var selectedLocation: HotelLocation?
    nonisolated static let started = DispatchSemaphore(value: 0)
    nonisolated static let release = DispatchSemaphore(value: 0)
    init() {
        let location = HotelLocation(name: "before-hotel")
        let person = StaffMember(name: "before-staff", department: "front", employment: "full", hourlyWage: 1000)
        let shift = ShiftAssignment(staffID: person.id, dateKey: "2026-10-01", type: .day, note: "before-shift")
        selectedStaff = [person]
        selectedLocationID = location.id
        selectedLocation = location
        data = ShiftData(locations: [location], staff: [person], assignments: [shift])
    }
''' + cache_state + wrapper + renderer_signature + ''' {
        precondition(!Thread.isMainThread, "PDF rendering blocked the main thread")
        started.signal()
        guard release.wait(timeout: .now() + 10) == .success else { return nil }
        return URL(fileURLWithPath: "/" + locationName + "/" + selectedStaff[0].name + "/" + assignments[0].note)
    }
}
@main struct Runner {
    @MainActor static func main() async {
        let store = TestStore()
        let task = Task { await store.exportShiftPDFAsync(month: Date()) }
        let started = await Task.detached { TestStore.started.wait(timeout: .now() + 10) == .success }.value
        precondition(started, "Worker did not start")
        store.selectedStaff[0].name = "changed-staff"
        store.data.assignments[0].note = "changed-shift"
        store.selectedLocation?.name = "changed-hotel"
        TestStore.release.signal()
        let result = await task.value
        precondition(result?.path == "/before-hotel/before-staff/before-shift", "Snapshot changed during rendering")
        print("Background rendering and snapshot isolation passed")
    }
}
'''
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'AsyncPDFTests.swift'
            binary = Path(tmp) / 'test'
            source.write_text(program)
            compile_result = subprocess.run([
                'swiftc', '-parse-as-library', '-swift-version', '5',
                '-strict-concurrency=complete', '-module-cache-path', tmp + '/cache',
                str(ROOT / 'HOTEL_SHIFT/Models/ShiftModels.swift'), str(source),
                '-o', str(binary)], capture_output=True, text=True, timeout=60)
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)

if __name__ == '__main__':
    unittest.main()
