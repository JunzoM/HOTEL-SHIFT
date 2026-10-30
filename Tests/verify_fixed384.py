#!/usr/bin/env python3
"""FIXED384: exercise real editor exports after undo/redo in a Node DOM harness."""
import subprocess
import tempfile
from pathlib import Path
from enable_triage_html_editor import render

page = render({'items': [
    {'issue_id': 'a', 'manual_status': '未対応', 'priority': '高', 'category': 'Swift'},
    {'issue_id': 'b', 'manual_status': '対応中', 'priority': '中', 'category': '署名'},
    {'issue_id': 'c', 'manual_status': '修正済み', 'priority': '要確認', 'category': 'その他'},
]})
script = page.split('<script>', 1)[1].split('</script>', 1)[0]
harness = r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
class Element {
  constructor(value='') {this.value=value;this.dataset={};this.hidden=false;this.disabled=false;this.textContent='';this.listeners={};this.children=[];this.download='';}
  addEventListener(name,fn){this.listeners[name]=fn;}
  fire(name){assert.ok(this.listeners[name],name);this.listeners[name]();}
  appendChild(el){this.children=this.children.filter(x=>x!==el);this.children.push(el);}
  click(){if(this.download) downloads.push({name:this.download,blob:blobs.get(this.href)});}
}
const ids=new Map();
for(const id of ['export-statuses','filter-query','filter-category','filter-priority','filter-status','visible-count','sort-mode','bulk-status','bulk-apply','bulk-message','edit-undo','edit-redo','change-history','history-count','export-history']) ids.set(id,new Element());
ids.get('sort-mode').value='status';
const sels=['未対応','対応中','修正済み'].map((value,i)=>{const e=new Element(value);e.dataset.issueId=['a','b','c'][i];return e;});
const rows=sels.map((sel,i)=>{const e=new Element();e.dataset.category=['Swift','署名','その他'][i];e.dataset.priority=['高','中','要確認'][i];e.textContent=['error A','error B','error C'][i];e.querySelector=()=>sel;return e;});
const tbody=new Element();
const document={getElementById:id=>ids.get(id),querySelectorAll:q=>q==='select[data-issue-id]'?sels:rows,querySelector:()=>tbody,createElement:()=>new Element()};
const downloads=[];const blobs=new Map();let nextUrl=0;
const context={document,window:{confirm:()=>true},Blob:class{constructor(parts,options){this.parts=parts;this.options=options;}},URL:{createObjectURL:b=>{const url='blob:'+ ++nextUrl;blobs.set(url,b);return url;},revokeObjectURL:()=>{}},setTimeout:()=>{},console};
vm.runInNewContext(fs.readFileSync(process.argv[2],'utf8'),context);
let checks=0;
function check(name,fn){fn();checks++;console.log('PASS '+name);}
function exportJSON(id){ids.get(id).fire('click');const d=downloads.at(-1);assert.ok(d);assert.equal(d.blob.options.type,'application/json');return {name:d.name,data:JSON.parse(d.blob.parts.join(''))};}
check('initial export includes all statuses',()=>{const x=exportJSON('export-statuses');assert.equal(x.name,'manual_statuses.json');assert.deepEqual(JSON.parse(JSON.stringify(x.data.statuses)),{a:'未対応',b:'対応中',c:'修正済み'});});
check('empty audit exports valid JSON',()=>{const x=exportJSON('export-history');assert.equal(x.name,'status_change_history.json');assert.equal(x.data.schema_version,1);assert.equal(x.data.changes.length,0);});
check('individual edit is exported',()=>{sels[0].value='対応中';sels[0].fire('change');assert.equal(exportJSON('export-statuses').data.statuses.a,'対応中');});
check('bulk respects filtering in export',()=>{ids.get('filter-category').value='Swift';ids.get('filter-category').fire('change');ids.get('bulk-status').value='修正済み';ids.get('bulk-apply').fire('click');const x=exportJSON('export-statuses').data.statuses;assert.equal(x.a,'修正済み');assert.equal(x.b,'対応中');assert.equal(x.c,'修正済み');});
check('audit records individual and bulk with before/after',()=>{const a=exportJSON('export-history').data.changes;assert.equal(a.length,2);assert.equal(a[0].kind,'個別変更');assert.equal(a[0].changes[0].before,'未対応');assert.equal(a[0].changes[0].after,'対応中');assert.equal(a[1].kind,'一括変更');assert.equal(a[1].changes[0].before,'対応中');assert.equal(a[1].changes[0].after,'修正済み');});
check('undo bulk reflected in export',()=>{ids.get('edit-undo').fire('click');assert.equal(exportJSON('export-statuses').data.statuses.a,'対応中');});
check('undo individual reflected in export',()=>{ids.get('edit-undo').fire('click');assert.equal(exportJSON('export-statuses').data.statuses.a,'未対応');});
check('redo individual reflected in export',()=>{ids.get('edit-redo').fire('click');assert.equal(exportJSON('export-statuses').data.statuses.a,'対応中');});
check('redo bulk reflected in export',()=>{ids.get('edit-redo').fire('click');assert.equal(exportJSON('export-statuses').data.statuses.a,'修正済み');});
check('audit tracks undo and redo transitions',()=>{const a=exportJSON('export-history').data.changes;assert.equal(a.length,6);assert.deepEqual(Array.from(a,x=>x.sequence),[1,2,3,4,5,6]);assert.deepEqual(Array.from(a,x=>x.kind),['個別変更','一括変更','取り消し','取り消し','やり直し','やり直し']);assert.equal(a[2].changes[0].before,'修正済み');assert.equal(a[2].changes[0].after,'対応中');});
check('new edit clears redo and exports current state',()=>{ids.get('edit-undo').fire('click');sels[1].value='未対応';sels[1].fire('change');assert.equal(ids.get('edit-redo').disabled,true);const x=exportJSON('export-statuses').data.statuses;assert.equal(x.a,'対応中');assert.equal(x.b,'未対応');assert.equal(x.c,'修正済み');});
check('filtered-out items are still in status export',()=>{ids.get('filter-status').value='未対応';ids.get('filter-status').fire('change');assert.equal(rows[0].hidden,true);assert.equal(Object.keys(exportJSON('export-statuses').data.statuses).length,3);});
check('audit export remains independent of status export',()=>{const history=exportJSON('export-history').data;assert.equal(history.changes.length,8);assert.equal(history.changes.at(-1).kind,'個別変更');assert.equal(history.changes.at(-1).changes[0].issue_id,'b');assert.equal(exportJSON('export-statuses').data.schema_version,1);});
console.log(`FIXED384: ${checks}/${checks} runtime export checks passed`);
'''
with tempfile.TemporaryDirectory() as td:
    script_file = Path(td) / 'editor.js'
    runner_file = Path(td) / 'runner.cjs'
    script_file.write_text(script, encoding='utf-8')
    runner_file.write_text(harness, encoding='utf-8')
    result = subprocess.run(['node', str(runner_file), str(script_file)], capture_output=True, text=True)
    print(result.stdout, end='')
    if result.returncode:
        print(result.stderr)
        raise SystemExit(result.returncode)
