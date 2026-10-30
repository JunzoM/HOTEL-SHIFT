#!/usr/bin/env python3
"""Execute shared toolbar state: repeated commands, editing and reset semantics."""
from pathlib import Path
import tempfile,subprocess,unittest
ROOT=Path(__file__).resolve().parents[1]
class ToolbarStateTests(unittest.TestCase):
 def test_shared_controls(self):
  source=(ROOT/'HOTEL_SHIFT/Views/ShiftWorkspaceControls.swift').read_text().split('// Explicit flat styling')[0].replace('import SwiftUI','import Foundation\nimport Combine',1)
  runner='''
@main struct Runner {
 @MainActor static func main() {
  let shared=ShiftWorkspaceControls()
  let gridReference=shared, dailyReference=shared
  shared.editing=true; shared.department="Front"; shared.canUndo=true; shared.selecting=true
  precondition(gridReference.editing && dailyReference.editing && dailyReference.department=="Front")
  shared.send(.undo)
  let first=shared.request!.id
  shared.send(.undo)
  precondition(shared.request!.id != first && shared.request!.command == .undo)
  shared.send(.copyWeek)
  precondition(shared.request!.command == .copyWeek)
  shared.reset()
  precondition(!shared.editing && !shared.selecting && !shared.canUndo && !shared.canRedo && shared.request==nil)
  precondition(shared.department=="Front")
  print("Shared edit/filter state, repeated command identity and reset passed")
 }
}
'''
  with tempfile.TemporaryDirectory() as tmp:
   src=Path(tmp)/'Toolbar.swift';src.write_text(source+runner)
   r=subprocess.run(['swiftc','-parse-as-library','-module-cache-path',tmp+'/cache',str(src),'-o',tmp+'/test'],capture_output=True,text=True,timeout=60)
   self.assertEqual(r.returncode,0,r.stderr)
   r=subprocess.run([tmp+'/test'],capture_output=True,text=True,timeout=20)
   self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__': unittest.main()
