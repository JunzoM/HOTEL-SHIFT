#!/usr/bin/env python3
"""FIXED385: imported statuses reject malformed/stale data without mutation."""
import importlib.util, json, subprocess, sys, tempfile
from pathlib import Path
root=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('manager',root/'Tests/manage_xcode_triage_status.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
checks=[]
def check(name, ok):
    checks.append(bool(ok)); print(('PASS' if ok else 'FAIL'),name)
with tempfile.TemporaryDirectory() as tmp:
    d=Path(tmp)
    items=[{'category':'Swift','message':f'issue {i}','priority':'高'} for i in range(2)]
    ids=[m.issue_id(x) for x in items]
    (d/'triage.json').write_text(json.dumps({'items':items}),encoding='utf-8')
    cmd=[sys.executable,str(root/'Tests/manage_xcode_triage_status.py'),str(d/'triage.json'),'--statuses',str(d/'manual.json'),'--output',str(d/'out.json'),'--html',str(d/'out.html')]
    run=lambda extra=[]: subprocess.run(cmd+extra,capture_output=True,text=True)
    check('create valid initial state',run(['--set-id',ids[0],'--status','対応中']).returncode==0)
    initial=(d/'manual.json').read_bytes()
    def imported(payload):
        (d/'import.json').write_text(payload if isinstance(payload,str) else json.dumps(payload,ensure_ascii=False),encoding='utf-8')
        result=run(['--import-statuses',str(d/'import.json')]);return result.returncode
    bad=[
        ('invalid json','{broken'),
        ('duplicate key','{"schema_version":1,"statuses":{},"statuses":{}}'),
        ('unknown schema',{'schema_version':2,'statuses':{}}),
        ('unknown field',{'schema_version':1,'statuses':{},'extra':1}),
        ('unknown ID',{'schema_version':1,'statuses':{'unknown':'未対応'}}),
        ('invalid status',{'schema_version':1,'statuses':{ids[0]:'invalid'}}),
        ('baseline not mapping',{'schema_version':1,'statuses':{ids[0]:'対応中'},'base_statuses':[]}),
        ('baseline mismatch',{'schema_version':1,'statuses':{ids[0]:'対応中'},'base_statuses':{}}),
        ('invalid baseline value',{'schema_version':1,'statuses':{ids[0]:'対応中'},'base_statuses':{ids[0]:'invalid'}}),
    ]
    for label,data in bad:
        check('reject '+label,imported(data)==2)
        check('preserve data after '+label,(d/'manual.json').read_bytes()==initial)
    # Browser initially saw 未対応, but an independent edit changed it to 対応中.
    stale={'schema_version':1,'statuses':{ids[0]:'修正済み'},'base_statuses':{ids[0]:'未対応'}}
    check('reject stale conflicting edit',imported(stale)==2)
    check('stale conflict preserves data',(d/'manual.json').read_bytes()==initial)
    # An untouched row in the exported snapshot must not undo a newer manual edit.
    untouched={'schema_version':1,'statuses':{ids[0]:'未対応',ids[1]:'対応中'},'base_statuses':{ids[0]:'未対応',ids[1]:'未対応'}}
    check('import changed rows only',imported(untouched)==0)
    state=json.loads((d/'manual.json').read_text())['statuses']
    check('preserve newer untouched row',state[ids[0]]=='対応中')
    check('apply edited row',state[ids[1]]=='対応中')
    check('legacy import remains supported',imported({'schema_version':1,'statuses':{ids[0]:'修正済み'}})==0)
    check('legacy import applied',json.loads((d/'manual.json').read_text())['statuses'][ids[0]]=='修正済み')
    (d/'triage.json').write_text(json.dumps({'items':[items[0],{}]}))
    previous=(d/'manual.json').read_bytes()
    check('reject malformed triage before write',imported({'schema_version':1,'statuses':{ids[0]:'未対応'}})==2)
    check('malformed triage leaves data unchanged',(d/'manual.json').read_bytes()==previous)
check('editor exports baseline','base_statuses:initialStatuses' in (root/'Tests/enable_triage_html_editor.py').read_text())
assert all(checks), f'{sum(checks)}/{len(checks)} passed'
print(f'FIXED385: {len(checks)}/{len(checks)} passed')
