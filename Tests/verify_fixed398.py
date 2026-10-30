#!/usr/bin/env python3
"""FIXED398: explicit confirm-and-advance navigation."""
from pathlib import Path
import re, subprocess, sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from render_xcode_import_conflicts import render
report={'schema_version':1,'conflict_count':2,'conflicts':[{'issue_id':str(i),'category':'Swift','message':'error','baseline_status':'未対応','current_status':'対応中','imported_status':'修正済み'} for i in range(2)],'resolution':'Review'}
page=render(report)
js=re.search(r'<script type="text/javascript">(.*?)</script>',page,re.S).group(1)
checks={
 'confirm button': 'id="review-and-next" type="button" disabled' in page,
 'explicit label': '選択中を確認済みにして次へ' in page,
 'confirm click': "reviewAndNext.addEventListener('click'" in js,
 'mark checked': 'check.checked = true;' in js,
 'advance': 'refresh();\n    navigateUnreviewed(1);' in js,
 'guard already reviewed': 'if(check.checked) return;' in js,
 'guard no selection': 'if(!row) return;' in js,
 'disable no selection': 'lastFocusedIndex<0' in js,
 'disable reviewed': "rows[lastFocusedIndex].querySelector('.review-check').checked" in js,
 'row click selection': "row.addEventListener('click'" in js,
 'keyboard selection': "row.addEventListener('focusin'" in js,
 'preserve navigation': "nextButton.addEventListener('click'" in js and "previousButton.addEventListener('click'" in js,
 'preserve progress export': "schema_version:2,kind:'conflict_review_progress'" in js,
 'no external network': 'https://' not in page and 'http://' not in page,
 'valid JS': subprocess.run(['node','--check','-'],input=js,text=True,capture_output=True).returncode==0,
}
for label,ok in checks.items(): print(('PASS' if ok else 'FAIL'),label)
print(f'FIXED398: {sum(checks.values())}/{len(checks)} passed')
assert all(checks.values())
