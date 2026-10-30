#!/usr/bin/env python3
"""FIXED430: improvement-rate behavior and safe rendering."""
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed430(unittest.TestCase):
 def test_function(self): self.assertIn('function historyImprovementRate(entries)',PAGE)
 def test_recent_window(self): self.assertIn('const summary=historyRecentSummary(entries);',PAGE)
 def test_denominator(self): self.assertIn('(summary.first-summary.latest)/summary.first*100',PAGE)
 def test_zero_baseline(self): self.assertIn("kind:summary.latest===0?'zero-stable':'zero-baseline'",PAGE)
 def test_insufficient(self): self.assertIn("if(summary.kind==='insufficient')return",PAGE)
 def test_render(self): self.assertIn('renderHistoryImprovementRate(line,entries);',PAGE)
 def test_format(self): self.assertIn("rate.percentage.toFixed(1)",PAGE)
 def test_filter(self): self.assertIn('renderHistoryChart(chart,visibleEntries)',PAGE)
 def test_safe_dom(self): self.assertNotIn('innerHTML',PAGE)
 def test_runtime(self):
  js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
  snippet=js[js.index('function historyFailureCount('):js.index('function renderHistoryChart(')]
  tests='''
const e=n=>({checks:Object.fromEntries(Array.from({length:n},(_,i)=>[String(i),{failed:true}]))});
const assert=(x,msg)=>{if(!x)throw Error(msg)};
assert(historyImprovementRate([e(2),e(4)]).percentage===50,'improvement');
assert(historyImprovementRate([e(4),e(2)]).percentage===-100,'worsening');
assert(historyImprovementRate([e(0),e(0)]).kind==='zero-stable','zero stable');
assert(historyImprovementRate([e(3),e(0)]).kind==='zero-baseline','zero baseline');
assert(historyImprovementRate([e(3)]).kind==='insufficient','insufficient');
assert(historyImprovementRate([e(1),e(2),e(4)]).percentage===75,'three runs');
'''
  with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
   f.write(snippet+'\n'+tests);f.flush()
   r=subprocess.run(['node',f.name],capture_output=True,text=True)
  self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__':unittest.main()
