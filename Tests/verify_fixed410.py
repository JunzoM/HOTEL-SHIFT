#!/usr/bin/env python3
import unittest
from local_diagnostic_center import PAGE, make_handler
from verify_fixed409 import LocalCenterTests

class CopyGuidanceTests(unittest.TestCase):
    def test_copy_button(self):
        self.assertIn('対処方法とログをコピー', PAGE)
        self.assertIn('addCopyButton(section,name,check)', PAGE)
    def test_copy_contains_advice_and_log(self):
        self.assertIn("'対処方法：'+advice(name,check)", PAGE)
        self.assertIn("'実行ログ：'", PAGE)
    def test_log_length_limited(self):
        self.assertIn('logs.length>6000', PAGE)
    def test_no_untrusted_html_insertion(self):
        self.assertNotIn('innerHTML', PAGE)
        self.assertIn('textContent=text', PAGE)
    def test_clipboard_fallback(self):
        self.assertIn('navigator.clipboard.writeText(value)', PAGE)
        self.assertIn("document.execCommand('copy')", PAGE)
    def test_failure_guidance(self):
        self.assertIn('手動でコピーしてください', PAGE)
    def test_copy_requires_click(self):
        self.assertIn("copy.addEventListener('click'", PAGE)

if __name__=='__main__':unittest.main()
