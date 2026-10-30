#!/usr/bin/env python3
"""FIXED417: jump from condensed errors to repair hints safely."""
import unittest
from local_diagnostic_center import PAGE

class HintNavigationTests(unittest.TestCase):
    def test_jump_button_exists(self):
        self.assertIn('修正候補へ移動', PAGE)
    def test_jump_targets_first_hint(self):
        self.assertIn("section.querySelector('.hint-list li')", PAGE)
    def test_no_target_is_safe(self):
        self.assertIn('if(!target)return;', PAGE)
    def test_focus_and_scroll(self):
        self.assertIn("target.scrollIntoView({behavior:'smooth',block:'start'})", PAGE)
        self.assertIn("target.focus({preventScroll:true})", PAGE)
    def test_highlight_reset(self):
        self.assertIn("section.querySelectorAll('.hint-target')", PAGE)
    def test_hint_list_marker(self):
        self.assertIn("list.className='hint-list'", PAGE)
    def test_button_only_on_failed_check(self):
        self.assertIn("function addErrorHighlights(section,name,check){\n  if(check.status==='passed')return;", PAGE)
    def test_no_unsafe_html(self):
        self.assertNotIn('innerHTML', PAGE)

if __name__=='__main__': unittest.main()
