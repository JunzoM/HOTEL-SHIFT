#!/usr/bin/env python3
"""FIXED433 chart point -> exact filtered history entry navigation."""
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed433(unittest.TestCase):
 def test_callback(self): self.assertIn('function renderHistoryChart(container,entries,onNavigate)',PAGE)
 def test_button(self): self.assertIn('選択した診断の履歴へ移動',PAGE)
 def test_hidden_until_selection(self): self.assertIn('jumpButton.hidden=true',PAGE)
 def test_selected_entry(self): self.assertIn('selectedEntry=chronological[i];jumpButton.hidden=false',PAGE)
 def test_exact_identity(self): self.assertIn('updated.indexOf(entry)',PAGE)
 def test_filtered_guard(self): self.assertIn('&&!item.hidden',PAGE)
 def test_open_detail(self): self.assertIn('details.open=true',PAGE)
 def test_scroll(self): self.assertIn("scrollIntoView({behavior:'smooth',block:'center'})",PAGE)
 def test_keyboard_focus(self): self.assertIn('summary.focus({preventScroll:true})',PAGE)
 def test_safe_dom(self): self.assertNotIn('innerHTML',PAGE)
 def test_js(self):
  js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
  with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
   f.write(js);f.flush();r=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
  self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__':unittest.main()
