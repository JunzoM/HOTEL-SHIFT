#!/usr/bin/env python3
"""FIXED435: selected history point compares with adjacent visible runs."""
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed435(unittest.TestCase):
 def test_neighbor_panel(self): self.assertIn('選択した診断の前後を比較',PAGE)
 def test_previous(self): self.assertIn("neighborLine('前の診断',i-1)",PAGE)
 def test_next(self): self.assertIn("neighborLine('次の診断',i+1)",PAGE)
 def test_missing(self): self.assertIn('比較対象なし',PAGE)
 def test_current(self): self.assertIn('選択中：',PAGE)
 def test_safe_text(self): self.assertNotIn('innerHTML',PAGE)
 def test_reselection_clears(self): self.assertIn('neighborDetail.replaceChildren()',PAGE)
 def test_visible_scope(self): self.assertIn('const chronological=entries.slice().reverse()',PAGE)
 def test_identity_navigation(self): self.assertIn('chronological.indexOf(entry)',PAGE)
 def test_js_syntax(self):
  js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
  with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
   f.write(js);f.flush();r=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
  self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__':unittest.main()
