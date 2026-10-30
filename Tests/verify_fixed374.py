#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path
root=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('triage',root/'Tests/triage_xcode_persistent_errors.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
checks=[]
def check(name, ok):
    checks.append(bool(ok)); print(('PASS' if ok else 'FAIL'),name)
def entry(cat, msg, builds, streak):
    return dict(category=cat,message=msg,builds=builds,consecutive_latest=streak,suggested_check='Check <settings>')
report={'schema_version':1,'analyzed_builds':5,'scope':'top 10','recurring':[entry('Swiftコンパイル','A <B>',5,4),entry('ファイル参照','missing',4,4),entry('署名・プロビジョニング','sign',3,1),entry('Swiftコンパイル','gone',2,0)]}
r=mod.triage(report)
check('four entries',len(r['items'])==4)
check('counts',r['counts']=={'高':2,'中':1,'要確認':1})
check('file references prioritized',r['items'][0]['category']=='ファイル参照')
check('streak is high',r['items'][1]['priority']=='高')
check('short streak is medium',r['items'][2]['priority']=='中')
check('not observed is not resolved',r['items'][3]['status']=='最新履歴では未検出')
check('HTML escaping', '&lt;B&gt;' in mod.render(r) and '&lt;settings&gt;' in mod.render(r))
check('HTML disclaimer', '未検出は解消を意味しません' in mod.render(r))
check('empty',not mod.triage({'schema_version':1,'recurring':[]})['items'])
for label,bad in [('bad schema',{'schema_version':2,'recurring':[]}),('bad list',{'schema_version':1,'recurring':{}}),('bad counter',{'schema_version':1,'recurring':[entry('x','y',2,3)]}),('bool counter',{'schema_version':1,'recurring':[entry('x','y',True,0)]})]:
    try:mod.triage(bad);ok=False
    except ValueError:ok=True
    check(label,ok)
with tempfile.TemporaryDirectory() as d:
    d=Path(d); (d/'input.json').write_text(json.dumps(report),encoding='utf-8')
    import subprocess,sys
    result=subprocess.run([sys.executable,str(root/'Tests/triage_xcode_persistent_errors.py'),str(d/'input.json'),'--output',str(d/'triage.json'),'--html',str(d/'triage.html')],capture_output=True,text=True)
    check('CLI success',result.returncode==0)
    check('JSON output',json.loads((d/'triage.json').read_text())['counts']['高']==2)
    check('HTML output','<table>' in (d/'triage.html').read_text())
check('pipeline integration','triage_xcode_persistent_errors.py' in (root/'Tests/run_xcode_report_pipeline.sh').read_text())
assert all(checks)
print(f'FIXED374: {len(checks)}/{len(checks)} passed')
