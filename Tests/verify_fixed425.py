#!/usr/bin/env python3
"""FIXED425 local history search regression checks."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed425(unittest.TestCase):
 def test_search_input(self): self.assertIn("historySearch.type='search'",PAGE)
 def test_accessibility(self): self.assertIn("setAttribute('aria-label','診断履歴を検索')",PAGE)
 def test_search_fields(self): self.assertIn("label+' '+item.at+' '+Object.keys(item.checks).join(' ')",PAGE)
 def test_case_insensitive(self): self.assertIn("toLocaleLowerCase('ja-JP')",PAGE)
 def test_combined_filters(self): self.assertIn('matchesStatus&&matchesSearch',PAGE)
 def test_view_only(self): self.assertIn('item.hidden=!match',PAGE)
 def test_search_event(self): self.assertIn("addEventListener('input',applyHistoryFilter)",PAGE)
 def test_delete_cleanup(self): self.assertIn('historySearch.remove()',PAGE)
 def test_export_unfiltered(self): self.assertIn('const entries=readHistory();',PAGE)
 def test_safe_dom(self): self.assertNotIn('innerHTML',PAGE)
if __name__=='__main__': unittest.main()
