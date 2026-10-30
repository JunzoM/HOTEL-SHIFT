#!/usr/bin/env python3
"""FIXED434: navigate from history details back to the exact chart point."""
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed434(unittest.TestCase):
 def test_chart_callback(self): self.assertIn('function renderHistoryChart(container,entries,onNavigate)',PAGE)
 def test_identity(self): self.assertIn('chronological.indexOf(entry)',PAGE)
 def test_no_match(self): self.assertIn('if(index<0)return false',PAGE)
 def test_chart_select(self): self.assertIn('selectHistoryPoint(index)',PAGE)
 def test_callback_ready(self): self.assertIn('selectChartEntry=select',PAGE)
 def test_return_button(self): self.assertIn('この診断をグラフで表示',PAGE)
 def test_scroll(self): self.assertIn("chart.scrollIntoView({behavior:'smooth',block:'center'})",PAGE)
 def test_focus(self): self.assertIn("selected.focus({preventScroll:true})",PAGE)
 def test_no_html_injection(self): self.assertNotIn('innerHTML',PAGE)
 def test_js(self):
  js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
  with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
   f.write(js);f.flush();r=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
  self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__':unittest.main()
