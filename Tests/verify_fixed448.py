#!/usr/bin/env python3
"""FIXED448: percentages for selected diagnostic transitions."""
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
PART=PAGE.split('// FIXED448:',1)[1].split('  function updateComparison(){',1)[0]
class Fixed448(unittest.TestCase):
    def test_heading(self): self.assertIn('改善・悪化・変化なしの割合',PART)
    def test_interval_denominator(self): self.assertIn('const intervalCount=indices.length-1',PART)
    def test_percent_formula(self): self.assertIn('count/intervalCount*100',PART)
    def test_one_decimal(self): self.assertIn('.toFixed(1)',PART)
    def test_improved(self): self.assertIn("['改善',improved,'improved']",PART)
    def test_worsened(self): self.assertIn("['悪化',worsened,'worsened']",PART)
    def test_unchanged(self): self.assertIn("['変化なし',unchanged,'unchanged']",PART)
    def test_counts_displayed(self): self.assertIn("'区間）'",PART)
    def test_in_panel(self): self.assertIn('comparisonTransitionTotals.append(percentageRows)',PART)
    def test_live_update(self): self.assertIn('updateComparisonTransitionTotals(indices);',PAGE)
    def test_safe_dom(self): self.assertNotIn('innerHTML',PART)
    def test_js_syntax(self):
        js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
        with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
            f.write(js);f.flush();r=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
        self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__': unittest.main()
