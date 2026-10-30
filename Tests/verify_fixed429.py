#!/usr/bin/env python3
"""FIXED429: recent trend summary regression tests."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed429(unittest.TestCase):
 def test_summary(self): self.assertIn('function historyRecentSummary(entries)',PAGE)
 def test_last_five(self): self.assertIn('entries.slice(0,5)',PAGE)
 def test_insufficient(self): self.assertIn("kind:'insufficient',runs:recent.length",PAGE)
 def test_improved(self): self.assertIn('if(counts[i]<counts[i+1])improved++',PAGE)
 def test_worsened(self): self.assertIn('else if(counts[i]>counts[i+1])worsened++',PAGE)
 def test_unchanged(self): self.assertIn('else unchanged++',PAGE)
 def test_rendered(self): self.assertIn('renderHistoryRecentSummary(container,entries);',PAGE)
 def test_filter_aware(self): self.assertIn('renderHistoryChart(chart,visibleEntries)',PAGE)
 def test_no_html_injection(self): self.assertNotIn('innerHTML',PAGE)
 def test_no_external_chart(self): self.assertNotIn('Chart.js',PAGE)
if __name__=='__main__': unittest.main()
