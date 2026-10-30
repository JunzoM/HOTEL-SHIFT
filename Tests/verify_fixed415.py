#!/usr/bin/env python3
import unittest
from local_diagnostic_center import PAGE

class PriorityNavigationTests(unittest.TestCase):
    def test_navigation_controls(self):
        for marker in ('前の問題へ', '次の問題へ', 'この問題を確認', '確認中 ', 'priority-position'):
            self.assertIn(marker, PAGE)
    def test_wrap_around(self):
        self.assertIn('selected=(index+items.length)%items.length', PAGE)
        self.assertIn('selected<0?items.length-1:selected-1', PAGE)
    def test_only_failed(self):
        self.assertIn("check.status==='passed')continue", PAGE)
        self.assertIn("if(!items.length){", PAGE)
    def test_focus_and_scroll(self):
        self.assertIn("target.scrollIntoView({behavior:'smooth',block:'start'})", PAGE)
        self.assertIn("target.focus({preventScroll:true})", PAGE)
        self.assertIn("section.id='check-'+name", PAGE)
    def test_no_mutation_or_unsafe_markup(self):
        self.assertNotIn('innerHTML', PAGE)
        self.assertNotIn('eval(', PAGE)
        self.assertIn('function focusPriority(name)', PAGE)
    def test_previous_features_preserved(self):
        for marker in ('addAllCopyButton(data)', 'addRepairPromptButton(section,name,check)', 'addPrioritySection(data)', '診断を実行'):
            self.assertIn(marker, PAGE)

if __name__ == '__main__': unittest.main()
