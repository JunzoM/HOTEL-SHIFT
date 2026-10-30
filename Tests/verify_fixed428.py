#!/usr/bin/env python3
"""FIXED428 trend indicator regression tests."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed428(unittest.TestCase):
 def test_trend_function(self): self.assertIn('function historyTrend(entries)',PAGE)
 def test_insufficient(self): self.assertIn("entries.length<2",PAGE)
 def test_improved(self): self.assertIn("difference<0?'improved'",PAGE)
 def test_worsened(self): self.assertIn("difference>0?'worsened'",PAGE)
 def test_unchanged(self): self.assertIn("'unchanged'",PAGE)
 def test_visible_only(self): self.assertIn('renderHistoryTrend(container,entries)',PAGE);self.assertIn('renderHistoryChart(chart,visibleEntries)',PAGE)
 def test_accessible_text(self): self.assertIn('前回との比較：',PAGE)
 def test_clear_explanation(self): self.assertIn('エラー件数のみの判定',PAGE)
 def test_no_html_injection(self): self.assertNotIn('innerHTML',PAGE)
 def test_no_network(self): self.assertNotIn('Chart.js',PAGE)
if __name__=='__main__': unittest.main()
