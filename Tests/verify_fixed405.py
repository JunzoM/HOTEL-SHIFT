#!/usr/bin/env python3
"""FIXED405 timing and regression summary checks."""
import importlib.util
import subprocess
import sys
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('diagnostics405', ROOT / 'Tests/run_diagnostics.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class Fixed405Tests(unittest.TestCase):
    def test_duration_success(self):
        result = mod.execute([sys.executable, '-c', 'print(1)'], ROOT, 5)
        self.assertEqual(result['status'], 'passed')
        self.assertGreaterEqual(result['duration_seconds'], 0)

    def test_duration_failure(self):
        result = mod.execute([sys.executable, '-c', 'raise SystemExit(2)'], ROOT, 5)
        self.assertEqual(result['status'], 'failed')
        self.assertGreaterEqual(result['duration_seconds'], 0)

    def test_duration_timeout(self):
        result = mod.execute([sys.executable, '-c', 'import time;time.sleep(2)'], ROOT, .05)
        self.assertEqual(result['status'], 'timeout')
        self.assertGreaterEqual(result['duration_seconds'], 0)

    def test_duration_error(self):
        result = mod.execute(['/nonexistent/hs-test'], ROOT, 1)
        self.assertEqual(result['status'], 'error')
        self.assertGreaterEqual(result['duration_seconds'], 0)

    def test_counts(self):
        self.assertEqual(mod.regression_counts({'stdout':'Regression summary: 3 passed, 2 failed, 5 total', 'stderr':''}), {'passed':3,'failed':2,'total':5})

    def test_invalid_counts(self):
        self.assertIsNone(mod.regression_counts({'stdout':'Regression summary: 3 passed, 2 failed, 9 total', 'stderr':''}))

    def test_missing_counts(self):
        self.assertIsNone(mod.regression_counts({'stdout':'', 'stderr':''}))

    def test_html_metrics(self):
        r = {'overall_status':'failed','checks':{'triage_regression':{'status':'failed','stdout':'<bad>','stderr':'','duration_seconds':1.25,'test_counts':{'passed':2,'failed':1,'total':3}}}}
        output = mod.render(r)
        self.assertIn('1.25秒', output)
        self.assertIn('失敗 1件', output)
        self.assertNotIn('<bad>', output)

    def test_runner_summary(self):
        runner = (ROOT / 'Tests/run_triage_editor_regression.sh').read_text()
        self.assertIn('Regression summary: ${passed} passed, ${failures} failed', runner)
        self.assertIn('passed=$((passed + 1))', runner)

if __name__ == '__main__':
    unittest.main()
