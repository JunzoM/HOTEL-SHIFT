#!/usr/bin/env python3
"""FIXED400 accessibility, layout, and previous behavior smoke tests."""
from pathlib import Path
import re, subprocess, sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from render_xcode_import_conflicts import render
report={'schema_version':1,'conflict_count':2,'conflicts':[{'issue_id':str(i),'category':'Swift','message':'error','baseline_status':'未対応','current_status':'対応中','imported_status':'修正済み'} for i in range(2)],'resolution':'Review'}
page=render(report)
js=re.search(r'<script type="text/javascript">(.*?)</script>',page,re.S).group(1)
checks={
 'jump to table': 'href="#conflict-table"' in page and 'id="conflict-table"' in page,
 'keyboard guide': '<details class="keyboard-guide">' in page,
 'grouped review tools': 'class="review-panel"' in page,
 'toolbar': 'class="toolbar"' in page,
 'responsive layout': '@media(max-width:650px)' in page,
 'print layout': '@media print' in page,
 'selected row CSS': '.selected-row{' in page,
 'selection live text': 'id="selected-conflict" role="status"' in page,
 'selection updates': 'function setSelection(index)' in js,
 'selection aria': "row.setAttribute('aria-selected',String(i===index))" in js,
 'selection classes': "row.classList.toggle('selected-row',i===index)" in js,
 'click selection': "row.addEventListener('click',()=>setSelection(index))" in js,
 'focus selection': "row.addEventListener('focusin',()=>setSelection(index))" in js,
 'navigation selection': 'setSelection(entry.index)' in js,
 'import preserved': 'function validateReviewSnapshot(value)' in js,
 'export preserved': "schema_version:2,kind:'conflict_review_progress'" in js,
 'keyboard preserved': "document.addEventListener('keydown'" in js,
 'valid JS': subprocess.run(['node','--check','-'],input=js,text=True,capture_output=True).returncode==0,
}
for label,ok in checks.items(): print(('PASS' if ok else 'FAIL'),label)
print(f'FIXED400: {sum(checks.values())}/{len(checks)} passed')
assert all(checks.values())
