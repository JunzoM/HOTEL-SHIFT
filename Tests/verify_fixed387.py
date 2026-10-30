#!/usr/bin/env python3
"""FIXED387: verify escaped offline HTML and conflict CLI integration."""
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path
root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root/'Tests'))
from render_xcode_import_conflicts import render
from manage_xcode_triage_status import issue_id
checks=[]
def check(name, ok):
    checks.append(ok)
    print(('PASS' if ok else 'FAIL'), name)
report={'schema_version':1,'conflict_count':1,'conflicts':[{'issue_id':'abc','category':'Swift','message':'<script>alert("x")</script>','baseline_status':'未対応','current_status':'対応中','imported_status':'修正済み'}], 'resolution':'Review <issues> & retry'}
page=render(report)
check('html document',page.startswith('<!doctype html>'))
check('escaped script','<script>' not in page and '&lt;script&gt;' in page)
check('escaped resolution','&lt;issues&gt; &amp; retry' in page)
check('all three statuses',all(s in page for s in ('未対応','対応中','修正済み')))
check('count displayed','競合件数：<strong>1</strong>' in page)
check('empty list supported','競合なし' in render({**report,'conflict_count':0,'conflicts':[]}))
for payload in ({**report,'conflict_count':2},{**report,'schema_version':2},{**report,'conflicts':[{}]},{**report,'resolution':None}):
    try: render(payload); valid=False
    except ValueError: valid=True
    check('invalid payload rejected',valid)
with tempfile.TemporaryDirectory() as tmp:
    d=Path(tmp)
    item={'category':'Swift','message':'<b>bad</b>','priority':'高'}
    ident=issue_id(item)
    (d/'triage.json').write_text(json.dumps({'items':[item]},ensure_ascii=False))
    (d/'manual.json').write_text(json.dumps({'schema_version':1,'statuses':{ident:'対応中'}},ensure_ascii=False))
    original=(d/'manual.json').read_bytes()
    (d/'import.json').write_text(json.dumps({'schema_version':1,'statuses':{ident:'修正済み'},'base_statuses':{ident:'未対応'}},ensure_ascii=False))
    cmd=[sys.executable,str(root/'Tests/manage_xcode_triage_status.py'),str(d/'triage.json'),'--statuses',str(d/'manual.json'),'--import-statuses',str(d/'import.json'),'--conflicts-json',str(d/'conflicts.json'),'--conflicts-html',str(d/'conflicts.html'),'--output',str(d/'out.json'),'--html',str(d/'out.html')]
    proc=subprocess.run(cmd,capture_output=True,text=True)
    check('stale import rejected',proc.returncode==2)
    check('manual statuses untouched',(d/'manual.json').read_bytes()==original)
    check('json report exists',(d/'conflicts.json').exists())
    check('html report exists',(d/'conflicts.html').exists())
    check('escaped error in html','&lt;b&gt;bad&lt;/b&gt;' in (d/'conflicts.html').read_text())
    check('no successful output',(not (d/'out.json').exists()) and (not (d/'out.html').exists()))
    cmd[cmd.index('--import-statuses')+1]=str(d/'import.json')
    (d/'import.json').write_text(json.dumps({'schema_version':1,'statuses':{ident:'修正済み'},'base_statuses':{ident:'対応中'}},ensure_ascii=False))
    (d/'conflicts.html').unlink()
    check('fresh import succeeds',subprocess.run(cmd,capture_output=True).returncode==0)
    check('no conflict html on success',not (d/'conflicts.html').exists())
assert all(checks), f'{sum(checks)}/{len(checks)} passed'
print(f'FIXED387: {len(checks)}/{len(checks)} passed')
