#!/usr/bin/env python3
"""FIXED443: print-only trend chart regression checks."""
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
PART=PAGE.split('// FIXED443:',1)[1].split('  const comparisonPrint=',1)[0]
class Fixed443(unittest.TestCase):
    def test_svg(self): self.assertIn("createElementNS('http://www.w3.org/2000/svg','svg')",PART)
    def test_accessibility(self): self.assertIn("'aria-label','選択した診断のエラー件数の推移'",PART)
    def test_selected_only(self): self.assertIn('indices.map(i=>counts[i])',PART)
    def test_chart_line(self): self.assertIn("svgNode('polyline'",PART)
    def test_points(self): self.assertIn("svgNode('circle'",PART)
    def test_labels(self): self.assertIn("svgNode('text'",PART)
    def test_minimum_two(self): self.assertIn('if(indices.length<2)return false',PAGE)
    def test_no_html_injection(self): self.assertNotIn('innerHTML',PAGE)
    def test_print_only(self): self.assertIn('body>*:not(#comparison-print-report)',PAGE)
    def test_print_css(self): self.assertIn('#comparison-print-report svg{',PAGE)
    def test_existing_report(self): self.assertIn('report.append(table)',PAGE)
    def test_js_syntax(self):
        js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
        with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
            f.write(js);f.flush();result=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
if __name__=='__main__':unittest.main()
