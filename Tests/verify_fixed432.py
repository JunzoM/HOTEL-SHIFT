#!/usr/bin/env python3
"""FIXED432 clickable, keyboard-accessible chart point details."""
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed432(unittest.TestCase):
 def test_chronological(self): self.assertIn('const chronological=entries.slice().reverse();',PAGE)
 def test_detail(self): self.assertIn('function selectHistoryPoint(i)',PAGE)
 def test_delta(self): self.assertIn('current-previous',PAGE)
 def test_improvement(self): self.assertIn("'改善 '+Math.abs(difference)+'件減少'",PAGE)
 def test_worsening(self): self.assertIn("'悪化 '+difference+'件増加'",PAGE)
 def test_unchanged(self): self.assertIn('変化なし（±0件）',PAGE)
 def test_first(self): self.assertIn('最初の診断（比較対象なし）',PAGE)
 def test_keyboard(self): self.assertIn("event.key==='Enter'||event.key===' '",PAGE)
 def test_filtered(self): self.assertIn('renderHistoryChart(chart,visibleEntries)',PAGE)
 def test_safe_dom(self): self.assertNotIn('innerHTML',PAGE)
 def test_js(self):
  js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
  with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
   f.write(js);f.flush();r=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
  self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__':unittest.main()
