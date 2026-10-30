#!/usr/bin/env python3
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from suggest_xcode_fixes import ADVICE, suggestions

class FixSuggestionTests(unittest.TestCase):
    def test_categories(self):
        samples = {
            'Swiftコンパイル': '/tmp/Foo.swift:12:3: error: cannot find x in scope',
            'ファイル参照': 'error: Build input file cannot be found: /tmp/a.swift',
            '署名・プロビジョニング': 'error: Signing for "HOTEL_SHIFT" requires a development team',
            'プロジェクト設定・スキーム': 'error: The project does not contain a scheme named HOTEL_SHIFT',
            '依存関係・モジュール': 'error: Failed to resolve package dependencies',
            'その他のエラー': 'error: unexpected failure',
        }
        for category, log in samples.items():
            with self.subTest(category=category):
                self.assertIn('[' + category + ']', suggestions(log))
                self.assertIn(ADVICE[category], suggestions(log))
    def test_deduplicate(self):
        self.assertEqual(suggestions('error: unexpected\nerror: another').count('[その他のエラー]'), 1)
    def test_no_error(self):
        self.assertIn('分類できません', suggestions('BUILD SUCCEEDED'))
    def test_multiple(self):
        self.assertEqual(suggestions('error: Signing for x\nerror: Failed to resolve package dependencies').count('\n'), 1)
    def test_script_connected(self):
        self.assertIn('python3 Tests/suggest_xcode_fixes.py "$log_file"', (Path(__file__).parent / 'run_xcode_build_check.sh').read_text())

if __name__ == '__main__':
    unittest.main()
