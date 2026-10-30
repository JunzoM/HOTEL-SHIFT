#!/usr/bin/env python3
"""FIXED406 diagnostic baseline comparison tests."""
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('diag406', ROOT / 'Tests/run_diagnostics.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class BaselineTests(unittest.TestCase):
    def setUp(self):
        self.old = {'schema_version': 1, 'checks': {'swift_syntax': {'status': 'passed', 'duration_seconds': 1.2}, 'triage_regression': {'status': 'passed', 'duration_seconds': 3.0, 'test_counts': {'failed': 0}}}}
        self.new = {'checks': {'swift_syntax': {'status': 'failed', 'duration_seconds': 1.8, 'stdout': '', 'stderr': ''}, 'triage_regression': {'status': 'passed', 'duration_seconds': 2.5, 'test_counts': {'passed': 1, 'failed': 1, 'total': 2}, 'stdout': '', 'stderr': ''}}, 'overall_status': 'failed'}
    def test_new_failure(self):
        result = mod.compare_baseline(self.new, self.old)
        self.assertTrue(result['swift_syntax']['new_failure'])
        self.assertFalse(result['triage_regression']['new_failure'])
    def test_duration_delta(self):
        result = mod.compare_baseline(self.new, self.old)
        self.assertEqual(result['swift_syntax']['duration_delta_seconds'], .6)
        self.assertEqual(result['triage_regression']['duration_delta_seconds'], -.5)
    def test_failure_count_delta(self):
        self.assertEqual(mod.compare_baseline(self.new, self.old)['triage_regression']['failed_delta'], 1)
    def test_html_comparison(self):
        self.new['baseline_comparison'] = mod.compare_baseline(self.new, self.old)
        page = mod.render(self.new)
        self.assertIn('新たな失敗', page)
        self.assertIn('+0.60秒', page)
        self.assertIn('失敗件数の変化: +1件', page)
    def test_no_baseline_unchanged(self):
        self.assertNotIn('前回比較', mod.render(self.new))
    def test_missing_check(self):
        self.old['checks'].pop('swift_syntax')
        self.assertEqual(mod.compare_baseline(self.new, self.old)['swift_syntax']['availability'], 'missing')
    def test_invalid_baseline(self):
        for bad in ({}, [], {'schema_version': 2, 'checks': {}}, {'schema_version': 1, 'checks': []}):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                mod.compare_baseline(self.new, bad)
    def test_malicious_status_not_rendered(self):
        self.old['checks']['swift_syntax']['status'] = '<script>alert(1)</script>'
        self.assertEqual(mod.compare_baseline(self.new, self.old)['swift_syntax']['availability'], 'missing')
    def test_bad_duration_ignored(self):
        self.old['checks']['swift_syntax']['duration_seconds'] = True
        self.assertNotIn('duration_delta_seconds', mod.compare_baseline(self.new, self.old)['swift_syntax'])
    def test_cli_help(self):
        r = subprocess.run([sys.executable, 'Tests/run_diagnostics.py', '--help'], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0)
        self.assertIn('--baseline-json', r.stdout)

if __name__ == '__main__':
    unittest.main()
