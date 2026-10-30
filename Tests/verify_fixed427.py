#!/usr/bin/env python3
"""FIXED427 offline chart and filtering regression checks."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed427(unittest.TestCase):
 def test_svg(self): self.assertIn("document.createElementNS(ns,'svg')",PAGE)
 def test_accessible(self): self.assertIn("setAttribute('aria-label','診断履歴 '",PAGE)
 def test_oldest_first(self): self.assertIn('entries.slice().reverse().map(historyFailureCount)',PAGE)
 def test_zero_safe(self): self.assertIn('Math.max(1,...counts)',PAGE)
 def test_single_safe(self): self.assertIn('counts.length===1?',PAGE)
 def test_filter_sync(self): self.assertIn('renderHistoryChart(chart,visibleEntries)',PAGE)
 def test_privacy(self): self.assertIn('Object.values(entry.checks||{})',PAGE)
 def test_cleanup(self): self.assertIn('chart.remove();exportButton.disabled=true',PAGE)
 def test_no_external_library(self): self.assertNotIn('Chart.js',PAGE)
 def test_no_injection(self): self.assertNotIn('innerHTML',PAGE)
if __name__=='__main__': unittest.main()
