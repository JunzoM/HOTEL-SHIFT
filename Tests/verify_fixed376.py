#!/usr/bin/env python3
import importlib.util,json,subprocess,sys,tempfile
from pathlib import Path
root=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('editor',root/'Tests/enable_triage_html_editor.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
checks=[]
def check(label,value):
 checks.append(bool(value));print(('PASS' if value else 'FAIL'),label)
item={'issue_id':'abc123','manual_status':'対応中','priority':'高','status':'継続','category':'Swift','message':'<script>alert(1)</script>','suggested_check':'A & B'}
html=m.render({'items':[item]})
check('HTML escaped','&lt;script&gt;' in html and '<script>alert(1)</script>' not in html)
check('selected state','value="対応中" selected' in html)
check('download handler','manual_statuses.json' in html and 'Blob' in html)
check('ID attribute','data-issue-id="abc123"' in html)
check('empty table','診断対象なし' in m.render({'items':[]}))
for bad in [{}, {'items':[{'issue_id':'x','manual_status':'bad'}]}, {'items':[{}]}]:
 try:m.render(bad);ok=False
 except ValueError:ok=True
 check('invalid data rejected',ok)
with tempfile.TemporaryDirectory() as td:
 d=Path(td);triage={'items':[{'category':'Swift','message':'error','priority':'高','status':'継続'}]};(d/'triage.json').write_text(json.dumps(triage))
 spec2=importlib.util.spec_from_file_location('manager',root/'Tests/manage_xcode_triage_status.py');mgr=importlib.util.module_from_spec(spec2);spec2.loader.exec_module(mgr)
 issue=mgr.issue_id(triage['items'][0]);(d/'import.json').write_text(json.dumps({'schema_version':1,'statuses':{issue:'修正済み'}}))
 cmd=[sys.executable,str(root/'Tests/manage_xcode_triage_status.py'),str(d/'triage.json'),'--statuses',str(d/'manual.json'),'--output',str(d/'status.json'),'--html',str(d/'status.html')]
 run=lambda extra:subprocess.run(cmd+extra,capture_output=True,text=True)
 check('import valid statuses',run(['--import-statuses',str(d/'import.json')]).returncode==0)
 check('persist imported statuses',json.loads((d/'manual.json').read_text())['statuses'][issue]=='修正済み')
 check('generate editable HTML',subprocess.run([sys.executable,str(root/'Tests/enable_triage_html_editor.py'),str(d/'status.json'),'--output',str(d/'editor.html')]).returncode==0)
 check('editor contains persisted status','value="修正済み" selected' in (d/'editor.html').read_text())
 (d/'import.json').write_text(json.dumps({'schema_version':1,'statuses':{'unknown':'対応中'}}))
 check('reject unknown IDs',run(['--import-statuses',str(d/'import.json')]).returncode==2)
 check('failed import preserves statuses',json.loads((d/'manual.json').read_text())['statuses'][issue]=='修正済み')
 check('reject conflicting actions',run(['--import-statuses',str(d/'import.json'),'--set-id',issue,'--status','未対応']).returncode==2)
check('pipeline editor integration','enable_triage_html_editor.py' in (root/'Tests/run_xcode_report_pipeline.sh').read_text())
assert all(checks)
print(f'FIXED376: {len(checks)}/{len(checks)} passed')
