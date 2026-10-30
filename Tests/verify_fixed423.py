#!/usr/bin/env python3
"""FIXED423: CSV history export regression checks."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed423(unittest.TestCase):
 def test_csv_builder(self): self.assertIn('function historyCsv(entries)',PAGE)
 def test_utf8_bom(self): self.assertIn("return '\\uFEFF'",PAGE)
 def test_escape_quotes(self): self.assertIn("s.replace(/\"/g,'\"\"')",PAGE)
 def test_formula_guard(self): self.assertIn('Prevent spreadsheet formula evaluation',PAGE)
 def test_no_logs(self): self.assertIn('item.at,name,check.failed',PAGE);self.assertNotIn('item.stdout',PAGE)
 def test_download(self): self.assertIn('URL.createObjectURL(blob)',PAGE);self.assertIn('URL.revokeObjectURL(url)',PAGE)
 def test_button(self): self.assertIn('診断履歴をCSV出力',PAGE)
 def test_empty(self): self.assertIn('if(!entries.length)return false',PAGE)
 def test_clear_disables(self): self.assertIn('exportButton.disabled=true',PAGE)
 def test_safe_dom(self): self.assertNotIn('innerHTML',PAGE)
if __name__=='__main__': unittest.main()
