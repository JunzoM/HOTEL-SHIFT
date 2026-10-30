#!/usr/bin/env python3
"""FIXED422: bounded local diagnostic history."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed422(unittest.TestCase):
 def test_key(self): self.assertIn("historyKey='hotel-shift-diagnostic-history-v422'",PAGE)
 def test_bounded(self): self.assertIn('slice(0,20)',PAGE)
 def test_privacy(self): self.assertIn('checks:current',PAGE);self.assertNotIn('logs:current',PAGE)
 def test_comparison(self): self.assertIn('function historyDifference(before,current)',PAGE)
 def test_missing_not_resolved(self): self.assertIn('for(const [name,now] of Object.entries(current))',PAGE)
 def test_display(self): self.assertIn('診断履歴（最新20回）',PAGE)
 def test_delete_confirmation(self): self.assertIn("window.confirm('このブラウザに保存した診断履歴を削除しますか？')",PAGE)
 def test_wiring(self): self.assertIn('addComparisonSection(data);addHistorySection(data);',PAGE)
 def test_safe_dom(self): self.assertIn('list.replaceChildren()',PAGE);self.assertNotIn('innerHTML',PAGE)
if __name__=='__main__': unittest.main()
