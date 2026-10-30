#!/usr/bin/env python3
"""FIXED386: report all stale import conflicts without mutating saved statuses."""
import importlib.util, json, subprocess, sys, tempfile
from pathlib import Path
root=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('manager',root/'Tests/manage_xcode_triage_status.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
checks=[]
def check(label,ok):
    checks.append(ok); print(('PASS' if ok else 'FAIL'),label)
with tempfile.TemporaryDirectory() as tmp:
    d=Path(tmp)
    items=[{'category':'Swift','message':f'error {i}','priority':'高'} for i in range(3)]
    ids=[m.issue_id(x) for x in items]
    (d/'triage.json').write_text(json.dumps({'items':items}))
    (d/'manual.json').write_text(json.dumps({'schema_version':1,'statuses':{ids[0]:'対応中',ids[1]:'対応中'}},ensure_ascii=False))
    original=(d/'manual.json').read_bytes()
    base=[sys.executable,str(root/'Tests/manage_xcode_triage_status.py'),str(d/'triage.json'),'--statuses',str(d/'manual.json'),'--output',str(d/'out.json'),'--html',str(d/'out.html')]
    def run(payload, extra=()):
        (d/'import.json').write_text(json.dumps(payload,ensure_ascii=False))
        return subprocess.run(base+['--import-statuses',str(d/'import.json'),*extra],capture_output=True,text=True)
    stale={'schema_version':1,'statuses':{ids[0]:'修正済み',ids[1]:'修正済み',ids[2]:'対応中'},'base_statuses':{x:'未対応' for x in ids}}
    r=run(stale,['--conflicts-json',str(d/'conflicts.json')])
    check('conflicts return nonzero',r.returncode==2)
    check('all conflicts listed in stderr',all(x in r.stderr for x in ids[:2]))
    check('manual data unchanged',(d/'manual.json').read_bytes()==original)
    check('no successful output written',not (d/'out.json').exists())
    report=json.loads((d/'conflicts.json').read_text())
    check('report contains both conflicts',report['conflict_count']==2 and len(report['conflicts'])==2)
    check('conflicts are correctly identified',{x['issue_id'] for x in report['conflicts']}==set(ids[:2]))
    check('reports category and message',all(x['category']=='Swift' and x['message'].startswith('error ') for x in report['conflicts']))
    check('reports baseline/current/imported states',all(x['baseline_status']=='未対応' and x['current_status']=='対応中' and x['imported_status']=='修正済み' for x in report['conflicts']))
    check('report provides resolution guidance',bool(report['resolution']))
    check('report schema version',report['schema_version']==1)
    check('reject report flag without import',subprocess.run(base+['--conflicts-json',str(d/'invalid.json')],capture_output=True).returncode==2)
    check('no report on invalid flag',not (d/'invalid.json').exists())
    # Resolve conflict by using latest baseline; a successful retry can update both rows.
    fresh={'schema_version':1,'statuses':{ids[0]:'修正済み',ids[1]:'修正済み'},'base_statuses':{ids[0]:'対応中',ids[1]:'対応中'}}
    r=run(fresh,['--conflicts-json',str(d/'new-conflicts.json')])
    check('fresh retry succeeds',r.returncode==0)
    check('fresh retry updates both',all(json.loads((d/'manual.json').read_text())['statuses'][x]=='修正済み' for x in ids[:2]))
    check('success does not create conflict report',not (d/'new-conflicts.json').exists())
    check('successful output written',(d/'out.json').exists())
assert all(checks),f'{sum(checks)}/{len(checks)} passed'
print(f'FIXED386: {len(checks)}/{len(checks)} passed')
