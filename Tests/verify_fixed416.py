#!/usr/bin/env python3
import unittest
from local_diagnostic_center import PAGE

class ErrorDetailsTests(unittest.TestCase):
    def test_collapsible_summary(self):
        self.assertIn('エラーの要点を見る', PAGE)
        self.assertIn("el('details',undefined,'error-summary')", PAGE)
    def test_only_errors(self):
        self.assertIn("if(check.status==='passed')return []", PAGE)
        self.assertIn("if(check.status==='passed')return;", PAGE)
    def test_limited_log_snippets(self):
        self.assertIn('selected.length>=6', PAGE)
        self.assertIn('slice(0,80000)', PAGE)
        self.assertIn('slice(0,350)', PAGE)
    def test_safe_text_rendering(self):
        self.assertIn("li.append(el('code'", PAGE)
        self.assertNotIn('innerHTML', PAGE)
    def test_connected_to_results(self):
        self.assertIn('addErrorHighlights(section,name,check);addRepairHints', PAGE)
    def test_previous_navigation(self):
        self.assertIn('次の問題へ', PAGE)
        self.assertIn('全診断結果をコピー', PAGE)

if __name__ == '__main__': unittest.main()
