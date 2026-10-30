#!/usr/bin/env python3
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from compare_xcode_diagnostic_reports import compare, validate
from export_xcode_diagnostic_report import build_report


def report(log, status=1):
    return build_report(log, status)


class ComparisonTests(unittest.TestCase):
    def test_same_reports(self):
        result = compare(report('error: A'), report('error: A'))
        self.assertEqual(result['diagnostic_count_change'], 0)
        self.assertEqual(result['new_prioritized_diagnostics'], [])
    def test_new_error(self):
        self.assertEqual(compare(report(''), report('error: A'))['diagnostic_count_change'], 1)
    def test_resolved_error(self):
        self.assertEqual(compare(report('error: A'), report(''))['diagnostic_count_change'], -1)
    def test_line_shift_not_new(self):
        self.assertEqual(compare(report('error: A'), report('note\nerror: A'))['new_prioritized_diagnostics'], [])
    def test_success_transition(self):
        self.assertEqual(compare(report('error: A'), report('BUILD SUCCEEDED', 0))['current_result'], 'success')
    def test_category_counts(self):
        comparison = compare(report('error: Build input file cannot be found'), report('error: A'))
        self.assertTrue(any(value['change'] for value in comparison['category_changes'].values()))
    def test_deduplication(self):
        self.assertEqual(compare(report('error: A\nerror: A'), report('error: A'))['diagnostic_count_change'], 0)
    def test_unsupported_schema(self):
        with self.assertRaises(ValueError): validate({'schema_version': 2})
    def test_invalid_counts(self):
        item = report('error: A'); item['category_counts'] = {'x': -1}
        with self.assertRaises(ValueError): validate(item)
    def test_invalid_diagnostic(self):
        item = report('error: A'); item['prioritized_diagnostics'][0]['log_line'] = 0
        with self.assertRaises(ValueError): validate(item)
    def test_cli_and_json(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root/'a.json').write_text(json.dumps(report('error: A')))
            (root/'b.json').write_text(json.dumps(report('error: B')))
            output = root/'nested'/'diff.json'
            command = [sys.executable, str(Path(__file__).parent/'compare_xcode_diagnostic_reports.py'), str(root/'a.json'), str(root/'b.json'), '--output', str(output)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(json.loads(output.read_text())['new_prioritized_diagnostics']), 1)
    def test_missing_file_fails(self):
        result = subprocess.run([sys.executable, str(Path(__file__).parent/'compare_xcode_diagnostic_reports.py'), '/nonexistent/a', '/nonexistent/b'], capture_output=True)
        self.assertEqual(result.returncode, 2)
    def test_top_ten_limit_disclosed(self):
        self.assertIn('最大10件', compare(report(''), report(''))['note'])


if __name__ == '__main__':
    unittest.main()
