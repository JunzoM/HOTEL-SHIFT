#!/usr/bin/env python3
"""FIXED388: actionable, escaped recovery guidance and no partial writes."""
import sys, json, tempfile, subprocess
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from render_xcode_import_conflicts import render
from manage_xcode_triage_status import issue_id
checks=[]
def check(name, condition):
    checks.append(bool(condition)); print(('PASS' if condition else 'FAIL'),name)
item={'issue_id':'abc','category':'Swift','message':'<script>alert(1)</script>', 'baseline_status':'未対応','current_status':'対応中','imported_status':'修正済み'}
r={'schema_version':1,'conflict_count':1,'conflicts':[item],'resolution':'Review & retry'}
p=render(r)
for phrase in ['安全に再編集・再取り込みする手順','現在の保存状態','取り込み予定','triage_editor.html','base_statuses','修正済み','競合件数：<strong>1</strong>']:
    check('guide: '+phrase,phrase in p)
check('escapes error', '<script>' not in p and '&lt;script&gt;' in p)
check('escapes guidance','Review &amp; retry' in p)
for bad in [{**r,'conflicts':[item,item],'conflict_count':2},{**r,'conflicts':[{**item,'issue_id':''}]},{**r,'schema_version':True},{**r,'conflict_count':True}]:
    try: render(bad); rejected=False
    except ValueError: rejected=True
    check('rejects malformed report',rejected)
with tempfile.TemporaryDirectory() as temp:
    d=Path(temp); root=Path(__file__).resolve().parent
    issue={'category':'Swift','message':'type mismatch'}; ident=issue_id(issue)
    (d/'triage.json').write_text(json.dumps({'items':[issue]}))
    (d/'manual.json').write_text(json.dumps({'schema_version':1,'statuses':{ident:'対応中'}},ensure_ascii=False))
    (d/'import.json').write_text(json.dumps({'schema_version':1,'statuses':{ident:'修正済み'},'base_statuses':{ident:'未対応'}},ensure_ascii=False))
    before=(d/'manual.json').read_bytes()
    args=[sys.executable,str(root/'manage_xcode_triage_status.py'),str(d/'triage.json'),'--statuses',str(d/'manual.json'),'--import-statuses',str(d/'import.json'),'--conflicts-json',str(d/'conflicts.json'),'--conflicts-html',str(d/'conflicts.html'),'--output',str(d/'output.json'),'--html',str(d/'output.html')]
    result=subprocess.run(args,capture_output=True,text=True)
    check('conflict stops import',result.returncode==2)
    check('stored data unchanged',(d/'manual.json').read_bytes()==before)
    check('no success outputs',not (d/'output.json').exists() and not (d/'output.html').exists())
    check('recovery guide generated','安全に再編集・再取り込みする手順' in (d/'conflicts.html').read_text())
    (d/'import.json').write_text(json.dumps({'schema_version':1,'statuses':{ident:'修正済み'},'base_statuses':{ident:'対応中'}},ensure_ascii=False))
    check('fresh re-export imports',subprocess.run(args,capture_output=True).returncode==0)
    check('fresh status persisted',json.loads((d/'manual.json').read_text())['statuses'][ident]=='修正済み')
print(f'FIXED388: {sum(checks)}/{len(checks)} passed')
assert all(checks)
