#!/usr/bin/env python3
"""FIXED442 print report checks."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
PART=PAGE.split('// FIXED442:',1)[1].split('  const comparisonCsv=',1)[0]
class Fixed442(unittest.TestCase):
    def test_button(self): self.assertIn('選択した診断の比較を印刷',PART)
    def test_minimum_two(self): self.assertIn('if(indices.length<2)return false',PART)
    def test_chronological(self): self.assertIn('Array.from(comparisonIndices).sort((a,b)=>a-b)',PART)
    def test_delta(self): self.assertIn('counts[indices[j-1]]',PART)
    def test_no_raw_logs(self): self.assertNotIn('stdout',PART); self.assertNotIn('stderr',PART)
    def test_safe_dom(self): self.assertNotIn('innerHTML',PAGE); self.assertIn("el('td',value)",PART)
    def test_print_css(self): self.assertIn('@media print',PAGE);self.assertIn('A4 landscape',PAGE)
    def test_only_print_report(self): self.assertIn('body>*:not(#comparison-print-report)',PAGE)
    def test_disabled(self): self.assertIn('comparisonPrint.disabled=indices.length<2',PAGE)
    def test_print_action(self): self.assertIn('window.print()',PART)
    def test_existing_controls(self): self.assertIn('comparisonCopy,comparisonConsult,comparisonCsv,comparisonClear',PAGE)
    def test_js_syntax(self):
        js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
        with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
            f.write(js);f.flush();r=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
        self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__':unittest.main()
