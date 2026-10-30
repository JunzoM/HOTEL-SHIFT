#!/usr/bin/env python3
"""FIXED441: selected comparison CSV export regression checks."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
PAGE = (ROOT / 'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''", 1)[1].split("'''", 1)[0]
PART = PAGE.split('// FIXED441:', 1)[1].split('  const comparisonConsult=', 1)[0]

class Fixed441(unittest.TestCase):
    def test_selected_only(self): self.assertIn('Array.from(comparisonIndices).sort((a,b)=>a-b)', PART)
    def test_minimum_two(self): self.assertIn("if(indices.length<2)return '';", PART)
    def test_uses_visible_chronological(self): self.assertIn('chronological[i].at', PART)
    def test_delta_between_selected(self): self.assertIn('counts[indices[j-1]]', PART)
    def test_formula_safe_csv(self): self.assertIn('row.map(csvCell)', PART)
    def test_utf8_bom(self): self.assertIn("return '\\uFEFF'", PART)
    def test_revoke_url(self): self.assertIn('URL.revokeObjectURL(url)', PART)
    def test_export_button(self): self.assertIn('選択した診断の比較をCSV出力', PART)
    def test_disabled_for_single(self): self.assertIn('comparisonCsv.disabled=indices.length<2', PAGE)
    def test_attached_to_panel(self): self.assertIn('comparisonCopy,comparisonConsult,comparisonCsv,comparisonClear', PAGE)
    def test_safe_dom(self): self.assertNotIn('innerHTML', PAGE)
    def test_js_syntax(self):
        js = PAGE.split('<script>', 1)[1].split('</script>', 1)[0]
        with tempfile.NamedTemporaryFile('w', suffix='.js') as f:
            f.write(js); f.flush()
            r = subprocess.run(['node', '--check', f.name], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)

if __name__ == '__main__': unittest.main()
