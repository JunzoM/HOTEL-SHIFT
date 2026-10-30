#!/usr/bin/env python3
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from prioritize_xcode_diagnostics import ranked_diagnostics, report, PRIORITY

class PriorityTests(unittest.TestCase):
    def test_priority_order(self):
        log = '/tmp/A.swift:1:1: error: unknown symbol\nerror: Failed to resolve package dependencies\nerror: Build input file cannot be found: A.swift'
        self.assertEqual([r[0] for r in ranked_diagnostics(log)], ['ファイル参照', '依存関係・モジュール', 'Swiftコンパイル'])
    def test_log_line_numbers(self):
        self.assertEqual(ranked_diagnostics('note\nerror: Build input file cannot be found')[0][1], 2)
    def test_deduplication(self):
        self.assertEqual(len(ranked_diagnostics('error: unknown\nerror: unknown')), 1)
    def test_distinct_errors(self):
        self.assertEqual(len(ranked_diagnostics('error: unknown\nerror: different')), 2)
    def test_limit(self):
        self.assertEqual(len(ranked_diagnostics('error: first\nerror: second', 1)), 1)
    def test_zero_limit(self):
        self.assertEqual(ranked_diagnostics('error: first', 0), [])
    def test_negative_limit(self):
        with self.assertRaises(ValueError): ranked_diagnostics('error: first', -1)
    def test_stable_same_priority(self):
        self.assertEqual([r[1] for r in ranked_diagnostics('error: first\nerror: second')], [1, 2])
    def test_no_error(self):
        self.assertIn('ありません', report('BUILD SUCCEEDED'))
    def test_advice(self):
        self.assertIn('Build Phases', report('error: Build input file cannot be found'))
    def test_disclaimer(self):
        self.assertIn('確定診断ではありません', report('error: unknown'))
    def test_all_categories(self):
        self.assertEqual(len(PRIORITY), 6)
    def test_script_integration(self):
        self.assertIn('python3 Tests/prioritize_xcode_diagnostics.py "$log_file"', (Path(__file__).parent/'run_xcode_build_check.sh').read_text())

if __name__ == '__main__': unittest.main()
