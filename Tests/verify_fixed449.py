#!/usr/bin/env python3
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
SWIFT=(ROOT/'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed449(unittest.TestCase):
    def test_optional_fix(self): self.assertIn('breakMinutes: defaultTimes == nil ? nil : pattern.customBreakMinutes,',SWIFT)
    def test_old_optional_error_removed(self): self.assertNotIn('defaultTimes.map { _ in pattern.customBreakMinutes }',SWIFT)
    def test_stacked_bar(self): self.assertIn("'chart-transition-bar'",PAGE)
    def test_three_trends(self): self.assertIn("['改善',improved,'improved'],['悪化',worsened,'worsened'],['変化なし',unchanged,'unchanged']",PAGE)
    def test_correct_denominator(self): self.assertIn('segment.style.width=(count/intervalCount*100)',PAGE)
    def test_accessible(self): self.assertIn("bar.setAttribute('aria-label'",PAGE)
    def test_live_refresh(self): self.assertIn('updateComparisonTransitionTotals(indices);',PAGE)
    def test_no_empty_division(self): self.assertLess(PAGE.index('if(indices.length<2){',PAGE.index('function updateComparisonTransitionTotals')),PAGE.index('const intervalCount=indices.length-1'))
    def test_legend(self): self.assertIn("'chart-transition-legend'",PAGE)
    def test_js_syntax(self):
        js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
        with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
            f.write(js);f.flush();r=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
        self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__':unittest.main()
