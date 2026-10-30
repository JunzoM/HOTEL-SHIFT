#!/usr/bin/env python3
"""FIXED421: browser-only comparison of successive diagnostic runs."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed421(unittest.TestCase):
 def test_storage_version(self): self.assertIn("comparisonKey='hotel-shift-diagnostic-comparison-v421'",PAGE)
 def test_three_categories(self):
  for label in ['新規・内容変更','継続','解消']: self.assertIn(label,PAGE)
 def test_first_run(self): self.assertIn('if(previous===null)',PAGE)
 def test_changed_fingerprint(self): self.assertIn('before.fingerprint===now.fingerprint',PAGE)
 def test_no_false_resolution(self): self.assertIn('for(const [name,now] of Object.entries(current))',PAGE)
 def test_privacy(self): self.assertIn('fingerprint:failed?fingerprint({name,check}):null',PAGE);self.assertIn('JSON.stringify({version:1,checks:current})',PAGE)
 def test_wired(self): self.assertIn('addPrioritySection(data);addComparisonSection(data);',PAGE)
 def test_safe_text(self): self.assertIn("li.append(el('span',name))",PAGE);self.assertNotIn('innerHTML',PAGE)
if __name__=='__main__': unittest.main()
