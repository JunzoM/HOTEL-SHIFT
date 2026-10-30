#!/usr/bin/env python3
"""FIXED431 chart improvement-rate overlay checks."""
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed431(unittest.TestCase):
 def test_chart_rate(self): self.assertIn('const chartRate=historyImprovementRate(entries);',PAGE)
 def test_percentage(self): self.assertIn("chartRate.percentage.toFixed(1)+'%'",PAGE)
 def test_zero_stable(self): self.assertIn("chartRate.kind==='zero-stable'?'直近の改善率 0%'",PAGE)
 def test_zero_baseline(self): self.assertIn("chartRate.kind==='zero-baseline'?'直近の改善率 算出不可'",PAGE)
 def test_insufficient(self): self.assertIn("'直近の改善率 比較データ不足'",PAGE)
 def test_svg_text(self): self.assertIn("class:'chart-rate'},chartRateText",PAGE)
 def test_recent_window(self): self.assertIn('const recent=entries.slice(0,5)',PAGE)
 def test_filter(self): self.assertIn('renderHistoryChart(chart,visibleEntries)',PAGE)
 def test_safe_dom(self): self.assertNotIn('innerHTML',PAGE)
 def test_javascript_syntax(self):
  js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
  with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
   f.write(js);f.flush();r=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
  self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__':unittest.main()
