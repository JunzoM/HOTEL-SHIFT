#!/usr/bin/env python3
"""FIXED372 trend report integration and edge-case checks."""
import importlib.util
import json
import subprocess
import tempfile
from pathlib import Path
root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('trend', root/'Tests/render_xcode_history_trend.py')
mod = importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
checks=[]
def check(name, value):
    checks.append(bool(value)); print(('PASS' if value else 'FAIL'), name)
with tempfile.TemporaryDirectory() as tmp:
    tmp=Path(tmp); index=tmp/'index.json'; out=tmp/'trend.html'
    a='build-20261025T150000000000Z.json';b='build-20261025T150100000000Z.json';c='build-20261025T150200000000Z.json'
    records=[{'file':c,'result':'success','diagnostic_count':0},{'file':a,'result':'failure','diagnostic_count':8},{'file':b,'result':'failure','diagnostic_count':3}]
    index.write_text(json.dumps({'schema_version':1,'builds':records}))
    loaded=mod.load_history(index)
    check('chronological order', [x['file'] for x in loaded]==[a,b,c])
    check('counts preserved', [x['count'] for x in loaded]==[8,3,0])
    check('results preserved', [x['result'] for x in loaded]==['failure','failure','success'])
    html=mod.render(loaded)
    check('SVG chart present', '<svg ' in html and '<polyline ' in html)
    check('success and failure markers', '#16a34a' in html and '#dc2626' in html)
    check('latest count displayed', '最新のエラー数：0' in html)
    check('difference displayed', '-3 件' in html)
    check('accessible chart', 'aria-label=' in html)
    check('empty history renders', 'ビルド履歴がありません' in mod.render([]))
    check('single history renders', '比較対象なし' in mod.render(loaded[:1]))
    check('safe HTML escaping', '&lt;script&gt;' in mod.render([{'file':'<script>','result':'failure','count':1}]))
    cmd=subprocess.run(['python3',str(root/'Tests/render_xcode_history_trend.py'),str(index),'--output',str(out)],capture_output=True,text=True)
    check('CLI succeeds', cmd.returncode==0 and out.exists())
    check('CLI HTML contains all records', all(x in out.read_text() for x in (a,b,c)))
    for name, data in [('bad schema',{'schema_version':2,'builds':[]}),('bad count',{'schema_version':1,'builds':[dict(records[0],diagnostic_count=-1)]}),('path traversal',{'schema_version':1,'builds':[dict(records[0],file='../evil.json')]}),('duplicate entries',{'schema_version':1,'builds':[records[0],records[0]]})]:
        index.write_text(json.dumps(data))
        try:mod.load_history(index);ok=False
        except ValueError:ok=True
        check(name+' rejected',ok)
    pipeline=(root/'Tests/run_xcode_report_pipeline.sh').read_text()
    check('pipeline renders trend', 'render_xcode_history_trend.py' in pipeline)
    check('pipeline retains build exit code', 'exit "$build_status"' in pipeline)
assert all(checks)
print(f'FIXED372: {len(checks)}/{len(checks)} passed')
