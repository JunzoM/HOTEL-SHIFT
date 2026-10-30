#!/usr/bin/env python3
"""FIXED407 automatic diagnostics history tests."""
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('diag407', ROOT / 'Tests/run_diagnostics.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.dir = Path(self.temp.name)
        self.report = {'schema_version': 1, 'checks': {'swift_syntax': {'status': 'passed'}}}

    def test_initial_history_empty(self):
        self.assertEqual(mod.latest_history(self.dir), (None, None))

    def test_archive_and_load(self):
        path = mod.archive_report(self.dir, self.report)
        self.assertTrue(path.exists())
        self.assertEqual(mod.latest_history(self.dir)[1], self.report)

    def test_unique_names(self):
        a = mod.archive_report(self.dir, self.report)
        b = mod.archive_report(self.dir, self.report)
        self.assertNotEqual(a, b)
        self.assertEqual(len(mod.history_files(self.dir)), 2)

    def test_retention(self):
        for _ in range(5):
            mod.archive_report(self.dir, self.report, keep=2)
        self.assertEqual(len(mod.history_files(self.dir)), 2)

    def test_invalid_retention(self):
        with self.assertRaises(ValueError):
            mod.archive_report(self.dir, self.report, keep=0)

    def test_corrupt_latest_skipped(self):
        mod.archive_report(self.dir, self.report)
        (self.dir / 'diagnostics_zzzz.json').write_text('{bad')
        self.assertEqual(mod.latest_history(self.dir)[1], self.report)

    def test_unrelated_files_preserved(self):
        unrelated = self.dir / 'notes.json'
        unrelated.write_text('important')
        for _ in range(3):
            mod.archive_report(self.dir, self.report, keep=1)
        self.assertEqual(unrelated.read_text(), 'important')

    def test_comparison_previous(self):
        mod.archive_report(self.dir, self.report)
        _, previous = mod.latest_history(self.dir)
        current = {'checks': {'swift_syntax': {'status': 'failed'}}}
        self.assertTrue(mod.compare_baseline(current, previous)['swift_syntax']['new_failure'])

    def test_cli_help(self):
        result = subprocess.run([sys.executable, 'Tests/run_diagnostics.py', '--help'], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        for option in ('--history-dir', '--history-keep', '--no-history'):
            self.assertIn(option, result.stdout)

if __name__ == '__main__':
    unittest.main()
