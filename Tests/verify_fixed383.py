#!/usr/bin/env python3
"""FIXED383: execute the real generated editor JavaScript in a minimal DOM harness."""
import json
import subprocess
import tempfile
from pathlib import Path
from enable_triage_html_editor import render

page = render({'items': [
    {'issue_id':'a', 'manual_status':'未対応', 'priority':'高', 'category':'Swift'},
    {'issue_id':'b', 'manual_status':'対応中', 'priority':'中', 'category':'署名'},
    {'issue_id':'c', 'manual_status':'修正済み', 'priority':'要確認', 'category':'その他'},
]})
script = page.split('<script>', 1)[1].split('</script>', 1)[0]
harness = r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
class Element {
  constructor(value='') { this.value=value; this.dataset={}; this.hidden=false; this.disabled=false; this.textContent=''; this.listeners={}; this.children=[]; }
  addEventListener(name, fn) { this.listeners[name]=fn; }
  fire(name) { assert.ok(this.listeners[name],name); this.listeners[name](); }
  appendChild(el) { this.children=this.children.filter(x=>x!==el); this.children.push(el); }
  click() {}
}
const ids = new Map();
for (const id of ['export-statuses','filter-query','filter-category','filter-priority','filter-status','visible-count','sort-mode','bulk-status','bulk-apply','bulk-message','edit-undo','edit-redo','change-history','history-count','export-history']) ids.set(id,new Element());
ids.get('sort-mode').value='status';
ids.get('edit-undo').disabled=true; ids.get('edit-redo').disabled=true;
const sels = ['未対応','対応中','修正済み'].map((value,i)=>{const e=new Element(value);e.dataset.issueId=['a','b','c'][i];return e;});
const rows = sels.map((sel,i)=>{const e=new Element();e.dataset.category=['Swift','署名','その他'][i];e.dataset.priority=['高','中','要確認'][i];e.textContent=['error A','error B','error C'][i];e.querySelector=()=>sel;return e;});
const tbody=new Element();
const document={getElementById:id=>ids.get(id),querySelectorAll:q=>q==='select[data-issue-id]'?sels:rows,querySelector:q=>tbody,createElement:()=>new Element()};
const downloads=[];
const context={document,window:{confirm:()=>true},Blob:class{constructor(parts){this.parts=parts}},URL:{createObjectURL:()=> 'blob:test',revokeObjectURL:()=>{}},setTimeout:()=>{},console};
vm.runInNewContext(fs.readFileSync(process.argv[2],'utf8'),context);
let checks=0;
function check(label,fn){fn();checks++;console.log('PASS '+label);}
check('initial undo/redo disabled',()=>{assert.equal(ids.get('edit-undo').disabled,true);assert.equal(ids.get('edit-redo').disabled,true)});
check('individual edit',()=>{sels[0].value='対応中';sels[0].fire('change');assert.equal(ids.get('edit-undo').disabled,false);assert.equal(ids.get('history-count').textContent.includes('1操作'),true)});
check('undo individual',()=>{ids.get('edit-undo').fire('click');assert.equal(sels[0].value,'未対応');assert.equal(ids.get('edit-redo').disabled,false)});
check('redo individual',()=>{ids.get('edit-redo').fire('click');assert.equal(sels[0].value,'対応中')});
check('bulk only filtered items',()=>{ids.get('filter-category').value='Swift';ids.get('filter-category').fire('change');assert.equal(rows[1].hidden,true);ids.get('bulk-status').value='修正済み';ids.get('bulk-apply').fire('click');assert.equal(sels[0].value,'修正済み');assert.equal(sels[1].value,'対応中');assert.equal(sels[2].value,'修正済み')});
check('undo bulk restores exact values',()=>{ids.get('edit-undo').fire('click');assert.equal(sels[0].value,'対応中');assert.equal(sels[1].value,'対応中')});
check('undo previous individual',()=>{ids.get('edit-undo').fire('click');assert.equal(sels[0].value,'未対応')});
check('redo chain',()=>{ids.get('edit-redo').fire('click');ids.get('edit-redo').fire('click');assert.equal(sels[0].value,'修正済み')});
check('new edit invalidates redo',()=>{ids.get('edit-undo').fire('click');sels[1].value='未対応';sels[1].fire('change');assert.equal(ids.get('edit-redo').disabled,true)});
check('filter and sorting remain operational',()=>{ids.get('filter-category').value='';ids.get('filter-category').fire('change');ids.get('sort-mode').value='priority';ids.get('sort-mode').fire('change');assert.equal(tbody.children.length,3)});
check('audit includes undo redo',()=>{assert.ok(ids.get('change-history').children.length>=8)});
console.log(`FIXED383: ${checks}/${checks} runtime checks passed`);
'''
with tempfile.TemporaryDirectory() as td:
    js = Path(td)/'editor.js'
    runner = Path(td)/'runner.cjs'
    js.write_text(script)
    runner.write_text(harness)
    result = subprocess.run(['node',str(runner),str(js)],capture_output=True,text=True)
    print(result.stdout,end='')
    if result.returncode:
        print(result.stderr)
        raise SystemExit(result.returncode)
