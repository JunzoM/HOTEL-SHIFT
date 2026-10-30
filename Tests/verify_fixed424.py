#!/usr/bin/env python3
"""FIXED424 history filter regression checks."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed424(unittest.TestCase):
 def test_filters(self): self.assertIn("['all','すべて']",PAGE);self.assertIn("['issues','エラーあり']",PAGE);self.assertIn("['passed','正常のみ']",PAGE)
 def test_non_destructive(self): self.assertIn("item.hidden=!match",PAGE);self.assertIn("view-only filtering",PAGE)
 def test_status(self): self.assertIn("li.dataset.hasIssues=String(failures>0)",PAGE)
 def test_counts(self): self.assertIn("表示中：",PAGE);self.assertIn("保存済み：",PAGE)
 def test_accessibility(self): self.assertIn("aria-pressed",PAGE)
 def test_csv_unfiltered(self): self.assertIn("const entries=readHistory();",PAGE)
 def test_reset_on_delete(self): self.assertIn("filterBar.remove();filterCount.remove()",PAGE)
 def test_privacy(self): self.assertIn("ログ本文は保存しません",PAGE)
 def test_no_unsafe_html(self): self.assertNotIn('innerHTML',PAGE)
if __name__=='__main__': unittest.main()
