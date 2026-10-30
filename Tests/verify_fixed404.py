#!/usr/bin/env python3
"""FIXED404 bounded runner regression checks."""
import subprocess
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / 'Tests/run_triage_editor_regression.sh'

class Fixed404Tests(unittest.TestCase):
    def test_dynamic_discovery(self):
        code = RUNNER.read_text()
        self.assertIn('latest=$(find Tests', code)
        self.assertIn('sort -n | tail -1', code)

    def test_per_test_timeout(self):
        code = RUNNER.read_text()
        self.assertIn('timeout "${timeout_seconds}s"', code)

    def test_invalid_arguments(self):
        for args in (['--recent', '0'], ['--timeout', '0'], ['--unknown']):
            p = subprocess.run(['bash', str(RUNNER), *args], cwd=ROOT, capture_output=True, text=True, timeout=10)
            self.assertEqual(p.returncode, 2, args)

    def test_recent_selection(self):
        code = RUNNER.read_text()
        self.assertIn('if (( recent > 0 && recent < ${#versions[@]} ))', code)
        self.assertIn('versions=("${versions[@]: -recent}")', code)

    def test_diagnostics_forwards_timeout(self):
        code = (ROOT / 'Tests/run_diagnostics.py').read_text()
        self.assertIn("'--timeout', str(args.per_test_timeout)", code)

if __name__ == '__main__':
    unittest.main()
