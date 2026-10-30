#!/usr/bin/env python3
"""Regression test for forward-compatible regression runner and diagnostic output."""
import subprocess
import sys
import tempfile
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class Fixed403Tests(unittest.TestCase):
    def test_legacy_401_forward_compatibility(self):
        result = subprocess.run([sys.executable, 'Tests/verify_fixed401.py'], cwd=ROOT, capture_output=True, text=True, timeout=40)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('7/7 passed', result.stdout)

    def test_runner_lists_current_version(self):
        script = (ROOT / 'Tests/run_triage_editor_regression.sh').read_text()
        self.assertIn('latest=$(find Tests', script)
        self.assertIn('versions=("${versions[@]: -recent}")', script)

    def test_diagnostics_render(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('diagnostics403', ROOT / 'Tests/run_diagnostics.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        report = {'overall_status': 'passed', 'checks': {
            'swift_syntax': {'status': 'passed', 'stdout': '9/9 passed', 'stderr': ''},
            'triage_regression': {'status': 'passed', 'stdout': 'passed', 'stderr': ''}}}
        page = module.render(report)
        self.assertIn('実行ログ', page)
        self.assertIn('失敗時は実行ログ', page)


if __name__ == '__main__':
    unittest.main()
