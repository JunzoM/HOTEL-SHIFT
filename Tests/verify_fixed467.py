#!/usr/bin/env python3
"""Execute production async preparation to verify coalescing and cache invalidation."""
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
S = (ROOT / 'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()

class PDFPreparationTests(unittest.TestCase):
 def test_reuse_and_invalidation(self):
  state = S[S.index('    private struct PDFPreparationKey:'):S.index('    @Published var selectedLocationID:')]
  start = S.index('    func exportShiftPDFAsync(')
  end = S.index('    nonisolated private static func renderShiftPDF(', start)
  method = S[start:end]
  renderer = S[end:S.index(' {', end)]
  program = '''import Foundation
final class Counter: @unchecked Sendable {
 let lock = NSLock()
 private var count = 0
 func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
 func read() -> Int { lock.lock(); defer { lock.unlock() }; return count }
}
@MainActor final class StoreCheck {
 var pdfRevision: UInt64 = 0
 var selectedStaff: [StaffMember] = []
 var data = ShiftData(locations: [], staff: [], assignments: [])
 var selectedLocationID = UUID()
 var selectedLocation: HotelLocation? = HotelLocation(name: "Test")
 nonisolated static let counter = Counter()
 nonisolated static let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
''' + state + method + renderer + ''' {
   precondition(!Thread.isMainThread)
   let count = counter.next()
   Thread.sleep(forTimeInterval: 0.05)
   try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
   let url = directory.appendingPathComponent(String(count) + ".pdf")
   try! Data("test PDF".utf8).write(to: url)
   return url
 }
}
@main struct Runner {
 @MainActor static func main() async {
  defer { try? FileManager.default.removeItem(at: StoreCheck.directory) }
  let store = StoreCheck()
  let month = Date(timeIntervalSince1970: 1790812800)
  async let first = store.exportShiftPDFAsync(month: month)
  async let second = store.exportShiftPDFAsync(month: month)
  let (a, b) = await (first, second)
  precondition(a != nil && a == b && StoreCheck.counter.read() == 1, "Concurrent calls generated twice")
  let reused = await store.exportShiftPDFAsync(month: month)
  precondition(reused == a && StoreCheck.counter.read() == 1, "Completed file not reused")
  let paper = await store.exportShiftPDFAsync(month: month, paperSize: "A3")
  precondition(paper != a && StoreCheck.counter.read() == 2)
  store.pdfRevision += 1
  let edited = await store.exportShiftPDFAsync(month: month, paperSize: "A3")
  precondition(edited != paper && StoreCheck.counter.read() == 3, "Stale data reused")
  store.selectedLocationID = UUID()
  let hotel = await store.exportShiftPDFAsync(month: month, paperSize: "A3")
  precondition(hotel != edited && StoreCheck.counter.read() == 4, "Other hotel reused")
  try! FileManager.default.removeItem(at: hotel!)
  let recreated = await store.exportShiftPDFAsync(month: month, paperSize: "A3")
  precondition(recreated != hotel && StoreCheck.counter.read() == 5, "Missing temporary file not regenerated")
  let options = await store.exportShiftPDFAsync(month: month, paperSize: "A3", showStaffName: false)
  precondition(options != recreated && StoreCheck.counter.read() == 6, "Changed display setting reused")
  print("Concurrent requests, completed cache, paper/data/hotel/options changes and missing file: passed")
 }
}
'''
  with tempfile.TemporaryDirectory() as tmp:
   source = Path(tmp)/'main.swift'
   binary = Path(tmp)/'test'
   source.write_text(program)
   r = subprocess.run(['swiftc', '-parse-as-library', '-swift-version', '5', '-strict-concurrency=complete', '-module-cache-path', tmp+'/cache', str(ROOT/'HOTEL_SHIFT/Models/ShiftModels.swift'), str(source), '-o', str(binary)], capture_output=True, text=True, timeout=60)
   self.assertEqual(r.returncode,0,r.stderr)
   r = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
   self.assertEqual(r.returncode,0,r.stderr)
if __name__ == '__main__': unittest.main()
