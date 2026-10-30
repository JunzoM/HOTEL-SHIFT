#!/usr/bin/env python3
"""FIXED445: selected history comparison on-screen print summary."""
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
PART=PAGE.split('// FIXED445:',1)[1].split('  function updateComparison(){',1)[0]
class Fixed445(unittest.TestCase):
    def test_preview_heading(self): self.assertIn('印刷前の改善率・総合判定',PART)
    def test_requires_two(self): self.assertIn('if(indices.length<2)',PART)
    def test_zero_baseline(self): self.assertIn('first===0',PART)
    def test_zero_stable(self): self.assertIn('last===0',PART)
    def test_zero_unavailable(self): self.assertIn('算出不可（比較元が0件）',PART)
    def test_percentage(self): self.assertIn('((first-last)/first*100).toFixed(1)',PART)
    def test_direction(self): self.assertIn("difference<0?'改善':difference>0?'悪化':'変化なし'",PART)
    def test_status(self): self.assertIn("setAttribute('aria-live','polite')",PART)
    def test_disclaimer(self): self.assertIn('修正完了・ビルド成功を保証しません',PART)
    def test_updates_on_selection(self): self.assertIn('updateComparisonSummaryPreview(indices);',PAGE)
    def test_preview_in_panel(self): self.assertIn('comparisonList,comparisonSummaryPreview,comparisonControls',PAGE)
    def test_no_inner_html(self): self.assertNotIn('innerHTML',PAGE)
    def test_js_syntax(self):
        js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
        with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
            f.write(js);f.flush();r=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
        self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__': unittest.main()
