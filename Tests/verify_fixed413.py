#!/usr/bin/env python3
import unittest
from local_diagnostic_center import PAGE

class RepairPromptTests(unittest.TestCase):
    def test_prompt_function(self):
        self.assertIn('function repairPrompt(name,check)', PAGE)
        self.assertIn('const hints=repairHints(name,check)', PAGE)
        self.assertIn('原因：', PAGE)
        self.assertIn('対処候補：', PAGE)
        self.assertIn('実行ログ：', PAGE)
    def test_copy_button(self):
        self.assertIn('function addRepairPromptButton(section,name,check)', PAGE)
        self.assertIn('修正方法をChatGPTに相談する文章をコピー', PAGE)
        self.assertIn('copyToClipboard(repairPrompt(name,check))', PAGE)
        self.assertIn('addRepairPromptButton(section,name,check);', PAGE)
    def test_safe_behavior(self):
        self.assertIn("if(check.status==='passed')return;", PAGE)
        self.assertIn('logs.slice(0,6000)', PAGE)
        self.assertIn('ログだけで断定できない場合', PAGE)
        self.assertIn('自動修正は行わないでください', PAGE)
        self.assertNotIn('innerHTML', PAGE)
    def test_legacy_features(self):
        self.assertIn('全診断結果をコピー', PAGE)
        self.assertIn('診断を実行', PAGE)
        self.assertIn('対処方法とログをコピー', PAGE)

if __name__=='__main__': unittest.main()
