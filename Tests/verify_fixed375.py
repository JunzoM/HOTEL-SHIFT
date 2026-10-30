#!/usr/bin/env python3
import importlib.util, json, subprocess, sys, tempfile
from pathlib import Path
root=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('statuses',root/'Tests/manage_xcode_triage_status.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
checks=[]
def check(name, condition):
    checks.append(bool(condition));print(('PASS' if condition else 'FAIL'),name)
triage={'items':[{'category':'Swiftコンパイル','message':'<missing>','priority':'高','status':'継続中','suggested_check':'A & B'}]}
issue=m.issue_id(triage['items'][0]);initial={'schema_version':1,'statuses':{}}
check('stable issue id',issue==m.issue_id(dict(triage['items'][0],consecutive_latest=5)))
check('default status',m.combine(triage,initial)['items'][0]['manual_status']=='未対応')
for state in m.STATUSES:
    check('status '+state,m.combine(triage,{'schema_version':1,'statuses':{issue:state}})['items'][0]['manual_status']==state)
check('HTML escaping','&lt;missing&gt;' in m.render(m.combine(triage,initial)) and 'A &amp; B' in m.render(m.combine(triage,initial)))
for bad in [{},{'schema_version':2,'statuses':{}},{'schema_version':1,'statuses':[]},{'schema_version':1,'statuses':{'x':'完了'}}]:
    try:m.validate_manual(bad);ok=False
    except ValueError:ok=True
    check('reject malformed manual state',ok)
with tempfile.TemporaryDirectory() as tmp:
    d=Path(tmp);(d/'triage.json').write_text(json.dumps(triage),encoding='utf-8')
    base=[sys.executable,str(root/'Tests/manage_xcode_triage_status.py'),str(d/'triage.json'),'--statuses',str(d/'manual.json'),'--output',str(d/'result.json'),'--html',str(d/'result.html')]
    run=lambda args:subprocess.run(base+args,capture_output=True,text=True)
    check('first generation',run([]).returncode==0)
    check('first run does not create manual file',not (d/'manual.json').exists())
    check('update status',run(['--set-id',issue,'--status','対応中']).returncode==0)
    check('status persisted',json.loads((d/'manual.json').read_text())['statuses'][issue]=='対応中')
    check('subsequent generation preserves manual status',run([]).returncode==0 and json.loads((d/'result.json').read_text())['items'][0]['manual_status']=='対応中')
    check('unknown issue rejected',run(['--set-id','unknown','--status','修正済み']).returncode==2)
    check('failed update preserves file',json.loads((d/'manual.json').read_text())['statuses'][issue]=='対応中')
    check('missing paired status rejected',run(['--set-id',issue]).returncode==2)
    check('HTML output exists','対応中' in (d/'result.html').read_text())
check('pipeline integration','manage_xcode_triage_status.py' in (root/'Tests/run_xcode_report_pipeline.sh').read_text())
assert all(checks)
print(f'FIXED375: {len(checks)}/{len(checks)} passed')
