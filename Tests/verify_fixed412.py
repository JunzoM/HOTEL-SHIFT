#!/usr/bin/env python3
import unittest
from local_diagnostic_center import PAGE

class RepairHintTests(unittest.TestCase):
    def test_hint_extraction(self):
        self.assertIn('function repairHints(name,check)', PAGE)
        self.assertIn('matchAll(re)', PAGE)
        self.assertIn('\\.swift', PAGE)
        self.assertIn('verify_fixed', PAGE)
    def test_display(self):
        self.assertIn('function addRepairHints(section,name,check)', PAGE)
        self.assertIn('addRepairHints(section,name,check);', PAGE)
        self.assertIn('確認するファイル・修正候補', PAGE)
    def test_copy(self):
        self.assertIn('...repairHints(name,check).map', PAGE)
        self.assertIn('function allCopyText(data)', PAGE)
    def test_safe(self):
        self.assertNotIn('innerHTML', PAGE)
        self.assertIn('自動修正は行いません', PAGE)
        self.assertIn('hints.length>=8', PAGE)
    def test_existing(self):
        self.assertIn('全診断結果をコピー', PAGE)
        self.assertIn('診断を実行', PAGE)

if __name__=='__main__': unittest.main()
