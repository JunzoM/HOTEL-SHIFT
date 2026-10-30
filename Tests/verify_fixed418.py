#!/usr/bin/env python3
"""FIXED418: scoped copy for each repair suggestion."""
import unittest
from local_diagnostic_center import PAGE

class ScopedHintCopyTests(unittest.TestCase):
    def test_per_hint_button(self):
        self.assertIn('この修正候補だけをChatGPTに相談', PAGE)
    def test_scoped_prompt_function(self):
        self.assertIn('function singleHintPrompt(name,check,hint)', PAGE)
    def test_single_hint_data(self):
        self.assertIn("'対象：'+hint.file", PAGE)
        self.assertIn("'検出内容：'+hint.reason", PAGE)
        self.assertIn("'修正候補：'+hint.action", PAGE)
    def test_scoped_logs(self):
        self.assertIn('logs.filter(line=>line.includes(file)||line.includes(hint.reason)).slice(0,8)', PAGE)
        self.assertIn("matching.join('\\n').slice(0,1800)", PAGE)
    def test_clipboard_error_handled(self):
        self.assertIn('catch(e){msg.textContent=', PAGE)
    def test_no_auto_send(self):
        self.assertIn('copyToClipboard(singleHintPrompt(name,check,hint))', PAGE)
    def test_no_unsafe_html(self):
        self.assertNotIn('innerHTML', PAGE)
    def test_existing_bulk_copy(self):
        self.assertIn('全診断結果をコピー', PAGE)

if __name__=='__main__':unittest.main()
