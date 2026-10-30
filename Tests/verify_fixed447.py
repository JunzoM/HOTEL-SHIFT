#!/usr/bin/env python3
"""FIXED447: selected diagnostic transition summary regression."""
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
PART=PAGE.split('// FIXED447:',1)[1].split('  function updateComparison(){',1)[0]
class Fixed447(unittest.TestCase):
    def test_title(self): self.assertIn('診断間の改善・悪化回数',PART)
    def test_requires_two(self): self.assertIn('if(indices.length<2)',PART)
    def test_improved(self): self.assertIn('改善した回数',PART)
    def test_worsened(self): self.assertIn('悪化した回数',PART)
    def test_unchanged(self): self.assertIn('変化なしの回数',PART)
    def test_consecutive_selected(self): self.assertIn('counts[indices[j]]-counts[indices[j-1]]',PART)
    def test_first_not_counted(self): self.assertIn('for(let j=1;j<indices.length;j++)',PART)
    def test_total_intervals(self): self.assertIn('(indices.length-1)',PART)
    def test_live_update(self): self.assertIn('updateComparisonTransitionTotals(indices);',PAGE)
    def test_in_panel(self): self.assertIn('comparisonControls.before(comparisonTransitionTotals)',PAGE)
    def test_safe_dom(self): self.assertNotIn('innerHTML',PART)
    def test_js_syntax(self):
        js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
        with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
            f.write(js);f.flush();r=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
        self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__': unittest.main()
