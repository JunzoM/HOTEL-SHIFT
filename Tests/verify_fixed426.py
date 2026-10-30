#!/usr/bin/env python3
"""FIXED426 filtered CSV export checks."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed426(unittest.TestCase):
 def test_button(self): self.assertIn('表示中の履歴をCSV出力',PAGE)
 def test_original_export(self): self.assertIn('診断履歴をCSV出力',PAGE)
 def test_visible_only(self): self.assertIn('!item.hidden&&item.dataset.historyIndex!==undefined',PAGE)
 def test_original_index(self): self.assertIn('li.dataset.historyIndex=String(i)',PAGE)
 def test_no_empty_export(self): self.assertIn('selectedIndices!==null&&!selectedIndices.length',PAGE)
 def test_original_comparison(self): self.assertIn('i+1<entries.length?entries[i+1].checks:null',PAGE)
 def test_csv_formula_guard(self): self.assertIn("if(/^[\\s]*[=+@-]/.test(s))",PAGE)
 def test_utf8_bom(self): self.assertIn("return '\\uFEFF'",PAGE)
 def test_clear_disables_both(self): self.assertIn('exportButton.disabled=true;filteredExport.disabled=true',PAGE)
 def test_no_html_injection(self): self.assertNotIn('innerHTML',PAGE)
if __name__=='__main__': unittest.main()
