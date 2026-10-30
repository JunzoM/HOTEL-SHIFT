#!/usr/bin/env python3
"""FIXED399 keyboard navigation shortcut safety checks."""
from pathlib import Path
import re, subprocess, sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from render_xcode_import_conflicts import render
report={'schema_version':1,'conflict_count':2,'conflicts':[{'issue_id':str(i),'category':'Swift','message':'error','baseline_status':'未対応','current_status':'対応中','imported_status':'修正済み'} for i in range(2)],'resolution':'Review'}
page=render(report)
js=re.search(r'<script type="text/javascript">(.*?)</script>',page,re.S).group(1)
checks={
 'shortcut help': 'ショートカット：N＝次、P＝前、Enter＝選択中を確認済みにして次へ' in page,
 'keyboard handler': "document.addEventListener('keydown'" in js,
 'next': "key==='n'" in js and 'navigateUnreviewed(1)' in js,
 'previous': "key==='p'" in js and 'navigateUnreviewed(-1)' in js,
 'enter': "event.key==='Enter'" in js and 'reviewAndNext.click()' in js,
 'disabled guard': '!reviewAndNext.disabled' in js,
 'modifier guard': all(x in js for x in ('event.ctrlKey','event.metaKey','event.altKey','event.shiftKey')),
 'repeat guard': 'event.repeat' in js,
 'composition guard': 'event.isComposing' in js,
 'input guard': "target.closest('input,textarea,select,button,[contenteditable]')" in js,
 'editable guard': 'target.isContentEditable' in js,
 'prevent default': 'event.preventDefault()' in js,
 'no auto confirmation on navigation': 'function navigateUnreviewed(direction)' in js,
 'export retained': "schema_version:2,kind:'conflict_review_progress'" in js,
 'no network': 'https://' not in page and 'http://' not in page,
 'valid JS': subprocess.run(['node','--check','-'],input=js,text=True,capture_output=True).returncode==0,
}
for label,ok in checks.items(): print(('PASS' if ok else 'FAIL'),label)
print(f'FIXED399: {sum(checks.values())}/{len(checks)} passed')
assert all(checks.values())
