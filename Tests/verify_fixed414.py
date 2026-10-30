#!/usr/bin/env python3
import unittest
from local_diagnostic_center import PAGE

class PriorityTests(unittest.TestCase):
    def test_priority_categories(self):
        for marker in ('function priorityItems(data)', "rank=1;label='開発環境・実行環境'", "rank=2;label='診断の時間制限'", "rank=3;label='Swift構文エラー'", "rank=4;label='回帰テストの失敗'"):
            self.assertIn(marker,PAGE)
    def test_deterministic_order(self):
        self.assertIn('a.rank-b.rank||a.name.localeCompare(b.name)',PAGE)
    def test_no_unsafe_html(self):
        self.assertNotIn('innerHTML',PAGE)
        self.assertIn("section.append(el('h2','修正する優先順位'))",PAGE)
    def test_integration(self):
        self.assertIn('addAllCopyButton(data);addPrioritySection(data);',PAGE)
        self.assertIn("header.push('','修正の優先順位：'",PAGE)
    def test_only_failed_checks(self):
        self.assertIn("check.status==='passed')continue",PAGE)
        self.assertIn('自動修正ではありません',PAGE)

if __name__=='__main__':unittest.main()
