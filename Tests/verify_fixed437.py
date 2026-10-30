#!/usr/bin/env python3
"""FIXED437: selected history summary copy controls."""
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed437(unittest.TestCase):
 def test_button(self): self.assertIn('選択した診断結果をコピー',PAGE)
 def test_initially_disabled(self): self.assertIn('copySelectedButton.disabled=true',PAGE)
 def test_enabled_on_selection(self): self.assertIn('copySelectedButton.disabled=false',PAGE)
 def test_guard(self): self.assertIn('if(selectedIndex<0)return;',PAGE)
 def test_sanitized_only(self):
  part=PAGE.split('function selectedHistoryCopyText(i){',1)[1].split('const copySelectedButton=',1)[0]
  self.assertIn('chronological[i].at',part)
  self.assertNotIn('stdout',part)
  self.assertNotIn('stderr',part)
 def test_copy_function(self): self.assertIn('copyToClipboard(selectedHistoryCopyText(selectedIndex))',PAGE)
 def test_feedback(self): self.assertIn('コピーできませんでした。ブラウザのコピー権限',PAGE)
 def test_accessible_status(self): self.assertIn("copySelectedStatus.setAttribute('role','status')",PAGE)
 def test_navigation_preserved(self): self.assertIn('pointNav.append(previousButton,nextButton,copySelectedButton,copySelectedStatus)',PAGE)
 def test_no_inner_html(self): self.assertNotIn('innerHTML',PAGE)
 def test_js_syntax(self):
  js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
  with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
   f.write(js);f.flush();r=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
  self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__':unittest.main()
