#!/usr/bin/env python3
"""FIXED419: manual, non-persistent diagnostic progress tracker."""
import pathlib, re, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed419(unittest.TestCase):
 def test_progress_tracker(self): self.assertIn('function addProgressTracker(section,items)',PAGE)
 def test_priority_wiring(self): self.assertIn('addProgressTracker(section,items);results.prepend(section)',PAGE)
 def test_checkboxes(self): self.assertIn("checkbox.type='checkbox'",PAGE)
 def test_count(self): self.assertIn("'対応済み '+done+' / '+items.length+'件 ・ 未対応 '",PAGE)
 def test_reset(self): self.assertIn('チェックをすべて解除',PAGE)
 def test_local_only_persistence(self):
  self.assertIn('localStorage',PAGE);self.assertNotIn('sessionStorage',PAGE)
 def test_no_status_mutation(self): self.assertNotIn('item.check.status=',PAGE)
 def test_existing_copy(self): self.assertIn('この修正候補だけをChatGPTに相談',PAGE)
if __name__=='__main__': unittest.main()
