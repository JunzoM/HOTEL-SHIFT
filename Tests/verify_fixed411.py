#!/usr/bin/env python3
import unittest
from local_diagnostic_center import PAGE
from verify_fixed410 import CopyGuidanceTests

class FullCopyTests(unittest.TestCase):
    def test_aggregate_button(self):
        self.assertIn('全診断結果をコピー', PAGE)
        self.assertIn('addAllCopyButton(data);', PAGE)
    def test_aggregate_sections(self):
        self.assertIn('function allCopyText(data)', PAGE)
        self.assertIn('Object.keys(checks).sort()', PAGE)
        self.assertIn("'総合結果：'", PAGE)
        self.assertIn("'対処方法：'+advice(name,check)", PAGE)
    def test_log_limits(self):
        self.assertIn('logs.length>6000', PAGE)
    def test_user_prompt_and_privacy(self):
        self.assertIn('ChatGPTへの依頼：', PAGE)
        self.assertIn('秘密情報', PAGE)
        self.assertIn('送信前', PAGE)
    def test_only_user_click_copies(self):
        self.assertIn("copy.addEventListener('click'", PAGE)
        self.assertNotIn('innerHTML', PAGE)
    def test_error_copy_fallback(self):
        self.assertIn('各検査のログを手動でコピーしてください', PAGE)

if __name__=='__main__': unittest.main()
