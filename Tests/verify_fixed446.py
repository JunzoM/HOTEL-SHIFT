#!/usr/bin/env python3
"""FIXED446: on-screen selected-diagnosis stepwise comparison."""
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
PART=PAGE.split('// FIXED446:',1)[1].split('  function updateComparison(){',1)[0]
class Fixed446(unittest.TestCase):
    def test_heading(self): self.assertIn('診断ごとのエラー増減',PART)
    def test_two_required(self): self.assertIn('if(indices.length<2)',PART)
    def test_previous_selected(self): self.assertIn('counts[indices[j-1]]',PART)
    def test_first_no_comparison(self): self.assertIn('比較元なし',PART)
    def test_improvement(self): self.assertIn("difference<0?'改善'",PART)
    def test_worsening(self): self.assertIn("difference>0?'悪化'",PART)
    def test_unchanged(self): self.assertIn("'変化なし'",PART)
    def test_time_and_count(self): self.assertIn("chronological[i].at,counts[i]+'件'",PART)
    def test_live_updates(self): self.assertIn('updateComparisonSteps(indices);',PAGE)
    def test_in_panel(self): self.assertIn('comparisonControls.before(comparisonSteps)',PAGE)
    def test_safe_dom(self): self.assertNotIn('innerHTML',PAGE)
    def test_js_syntax(self):
        js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
        with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
            f.write(js);f.flush();r=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
        self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__': unittest.main()
