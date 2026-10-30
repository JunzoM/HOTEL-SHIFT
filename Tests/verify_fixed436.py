#!/usr/bin/env python3
"""FIXED436: accessible previous/next history chart selection."""
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed436(unittest.TestCase):
 def test_previous_label(self): self.assertIn("'前の診断へ'",PAGE)
 def test_next_label(self): self.assertIn("'次の診断へ'",PAGE)
 def test_previous_guard(self): self.assertIn('if(selectedIndex>0)selectHistoryPoint(selectedIndex-1)',PAGE)
 def test_next_guard(self): self.assertIn('selectedIndex<counts.length-1',PAGE)
 def test_boundary_previous(self): self.assertIn('previousButton.disabled=i===0',PAGE)
 def test_boundary_next(self): self.assertIn('nextButton.disabled=i===counts.length-1',PAGE)
 def test_initial_disabled(self): self.assertIn('previousButton.disabled=true;nextButton.disabled=true',PAGE)
 def test_shared_selection(self): self.assertIn('selectHistoryPoint(selectedIndex+1)',PAGE)
 def test_panel_wired(self): self.assertIn('pointDetail,pointNav,neighborDetail',PAGE)
 def test_no_unsafe_html(self): self.assertNotIn('innerHTML',PAGE)
 def test_js_syntax(self):
  js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
  with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
   f.write(js);f.flush();r=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
  self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__':unittest.main()
