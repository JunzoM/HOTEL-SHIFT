#!/usr/bin/env python3
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from export_xcode_diagnostic_report import build_report, write_report

class ReportTests(unittest.TestCase):
    def test_success(self):
        report = build_report('BUILD SUCCEEDED', 0)
        self.assertEqual(report['result'], 'success')
        self.assertEqual(report['diagnostic_count'], 0)
        self.assertEqual(report['prioritized_diagnostics'], [])
    def test_failure(self):
        self.assertEqual(build_report('error: failed', 65)['result'], 'failure')
    def test_exit_code(self):
        self.assertEqual(build_report('', 7)['exit_code'], 7)
    def test_invalid_code(self):
        with self.assertRaises(ValueError): build_report('', -1)
    def test_counts_deduplicate(self):
        self.assertEqual(build_report('error: bad\nerror: bad', 1)['diagnostic_count'], 1)
    def test_priorities(self):
        report = build_report('/tmp/A.swift:1:1: error: missing\nerror: Build input file cannot be found', 1)
        self.assertEqual(report['prioritized_diagnostics'][0]['category'], 'ファイル参照')
    def test_line_number(self):
        self.assertEqual(build_report('note\nerror: failed', 1)['prioritized_diagnostics'][0]['log_line'], 2)
    def test_suggestion(self):
        self.assertTrue(build_report('error: Build input file cannot be found', 1)['prioritized_diagnostics'][0]['suggested_check'])
    def test_json_unicode(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder)/'nested'/'report.json'
            write_report(target, build_report('error: Build input file cannot be found', 1))
            self.assertIn('ファイル参照', target.read_text())
            self.assertEqual(json.loads(target.read_text())['schema_version'], 1)
    def test_cli(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder)/'build.log'; log.write_text('error: failure')
            out = Path(folder)/'report.json'
            subprocess.run([sys.executable, str(Path(__file__).parent/'export_xcode_diagnostic_report.py'), str(log), '65', str(out)], check=True, capture_output=True)
            self.assertEqual(json.loads(out.read_text())['exit_code'], 65)
    def test_missing_log(self):
        with tempfile.TemporaryDirectory() as folder:
            result = subprocess.run([sys.executable, str(Path(__file__).parent/'export_xcode_diagnostic_report.py'), str(Path(folder)/'missing'), '1', str(Path(folder)/'out')], capture_output=True)
            self.assertEqual(result.returncode, 2)
    def test_build_script_integration(self):
        script = (Path(__file__).parent/'run_xcode_build_check.sh').read_text()
        self.assertIn('XCODE_DIAGNOSTIC_REPORT', script)
        self.assertIn('"$build_status"', script)

if __name__ == '__main__': unittest.main()
