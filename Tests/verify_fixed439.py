#!/usr/bin/env python3
"""FIXED439: multi-selection comparison for saved diagnostic chart."""
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed439(unittest.TestCase):
 def test_multi_selection(self): self.assertIn('const comparisonIndices=new Set()',PAGE)
 def test_visible_chart_scope(self): self.assertIn('for(let i=0;i<counts.length;i++)',PAGE)
 def test_sort_chronological(self): self.assertIn('Array.from(comparisonIndices).sort((a,b)=>a-b)',PAGE)
 def test_min_two(self): self.assertIn('comparisonCopy.disabled=indices.length<2',PAGE)
 def test_copy(self): self.assertIn('copyToClipboard(value)',PAGE)
 def test_clear(self): self.assertIn('comparisonIndices.clear()',PAGE)
 def test_no_raw_logs(self):
  part=PAGE.split('// FIXED439:',1)[1].split('const copySelectedButton=',1)[0]
  self.assertNotIn('stdout',part);self.assertNotIn('stderr',part)
 def test_safe_dom(self): self.assertNotIn('innerHTML',PAGE)
 def test_mount(self): self.assertIn('jumpButton,comparisonPanel',PAGE)
 def test_js_syntax(self):
  js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
  with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
   f.write(js);f.flush();r=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
  self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__': unittest.main()
