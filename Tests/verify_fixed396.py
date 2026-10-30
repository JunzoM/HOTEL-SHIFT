#!/usr/bin/env python3
"""FIXED396: next unresolved navigation is safe and accessible."""
from pathlib import Path
import re, subprocess, sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from render_xcode_import_conflicts import render

def report(n):
    return {'schema_version':1,'conflict_count':n,'conflicts':[{'issue_id':str(i),'category':'Swift','message':'error','baseline_status':'未対応','current_status':'対応中','imported_status':'修正済み'} for i in range(n)],'resolution':'Review'}
page=render(report(3))
empty=render(report(0))
checks={
 'next button': 'id="next-unreviewed"' in page,
 'help text': 'id="next-unreviewed-help"' in page,
 'accessible help link': 'aria-describedby="next-unreviewed-help"' in page,
 'disabled when complete': 'nextButton.disabled=remaining===0;' in page,
 'remaining count': "'次の未確認項目へ（残り '+remaining+' 件）'" in page,
 'forward navigation': 'index>lastFocusedIndex' in page,
 'wrap navigation': 'candidates[0]' in page,
 'no auto-review': "target.querySelector('.review-check').checked=true" not in page,
 'clear search': "search.value='';" in page,
 'clear filter': 'only.checked=false;' in page,
 'refresh visibility': "only.checked=false;\n    refresh();" in page,
 'keyboard focus': 'entry.row.focus();' in page,
 'scroll into view': "entry.row.scrollIntoView({block:'center',behavior:'auto'});" in page,
 'empty case': 'id="next-unreviewed"' in empty,
 'preserve progress schema': "schema_version:2,kind:'conflict_review_progress'" in page,
 'offline': 'https://' not in page and 'http://' not in page,
}
js=re.search(r'<script type="text/javascript">(.*?)</script>',page,re.S).group(1)
checks['javascript syntax']=subprocess.run(['node','--check','-'],input=js,text=True,capture_output=True).returncode==0
for label,ok in checks.items(): print(('PASS' if ok else 'FAIL'),label)
print(f'FIXED396: {sum(checks.values())}/{len(checks)} passed')
assert all(checks.values())
