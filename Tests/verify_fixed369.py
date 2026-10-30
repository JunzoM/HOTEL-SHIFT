#!/usr/bin/env python3
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from compare_xcode_diagnostic_reports import compare
from export_xcode_diagnostic_report import build_report
from render_xcode_diagnostic_comparison import render, validate_comparison

class HTMLComparisonTests(unittest.TestCase):
    def setUp(self):
        self.data = compare(build_report('error: first', 1), build_report('error: second', 1))
    def test_document(self): self.assertIn('<!doctype html>', render(self.data))
    def test_japanese_language(self): self.assertIn('lang="ja"', render(self.data))
    def test_counts(self): self.assertIn('診断件数', render(self.data))
    def test_new(self): self.assertIn('second', render(self.data))
    def test_resolved(self): self.assertIn('first', render(self.data))
    def test_category_table(self): self.assertIn('<table>', render(self.data))
    def test_empty(self): self.assertIn('該当なし', render(compare(build_report('', 0), build_report('', 0))))
    def test_html_escaping(self):
        self.data['new_prioritized_diagnostics'] = [{'category': '<img>', 'message': '<script>alert("x")</script>'}]
        page = render(self.data)
        self.assertNotIn('<script>', page)
        self.assertNotIn('<img>', page)
        self.assertIn('&lt;script&gt;', page)
    def test_bad_schema(self):
        self.data['schema_version'] = 9
        with self.assertRaises(ValueError): validate_comparison(self.data)
    def test_bad_delta(self):
        self.data['diagnostic_count_change'] = 99
        with self.assertRaises(ValueError): validate_comparison(self.data)
    def test_bad_diagnostics(self):
        self.data['new_prioritized_diagnostics'] = [{'category': 123, 'message': 'x'}]
        with self.assertRaises(ValueError): validate_comparison(self.data)
    def test_cli(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'diff.json').write_text(json.dumps(self.data), encoding='utf-8')
            output = root/'reports'/'diff.html'
            proc = subprocess.run([sys.executable, str(Path(__file__).parent/'render_xcode_diagnostic_comparison.py'), str(root/'diff.json'), '--output', str(output)], capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn('first', output.read_text(encoding='utf-8'))
    def test_missing_file(self):
        with tempfile.TemporaryDirectory() as temp:
            proc = subprocess.run([sys.executable, str(Path(__file__).parent/'render_xcode_diagnostic_comparison.py'), str(Path(temp)/'missing'), '--output', str(Path(temp)/'out.html')], capture_output=True)
            self.assertEqual(proc.returncode, 2)

if __name__ == '__main__': unittest.main()
