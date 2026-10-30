#!/usr/bin/env python3
"""FIXED420: local-only progress persistence and stale-status cleanup."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed420(unittest.TestCase):
 def test_storage_key(self): self.assertIn("progressKey='hotel-shift-diagnostic-progress-v420'",PAGE)
 def test_store_checks(self): self.assertIn('localStorage.setItem(progressKey,JSON.stringify(value))',PAGE)
 def test_restore_checks(self): self.assertIn('checkbox.checked=current[keys[index]]===true',PAGE)
 def test_changed_error_resets(self): self.assertIn('const keys=items.map(fingerprint)',PAGE);self.assertIn('writeProgress(current)',PAGE)
 def test_passed_clears(self): self.assertIn('if(!items.length){writeProgress({});',PAGE)
 def test_privacy(self): self.assertIn('const input=item.name+',PAGE);self.assertIn('return item.name+\':\'+(hash>>>0).toString(16)',PAGE)
 def test_storage_fallback(self): self.assertIn('catch(e){return {};}',PAGE);self.assertIn('catch(e){/* private mode / storage unavailable */}',PAGE)
 def test_no_status_mutation(self): self.assertNotIn('item.check.status=',PAGE)
if __name__=='__main__': unittest.main()
