#!/usr/bin/env python3
"""FIXED397: forward/backward unresolved navigation and safe wraparound."""
from pathlib import Path
import re, subprocess, sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from render_xcode_import_conflicts import render

def report(n):
    return {'schema_version':1,'conflict_count':n,'conflicts':[{'issue_id':str(i),'category':'Swift','message':'error','baseline_status':'未対応','current_status':'対応中','imported_status':'修正済み'} for i in range(n)],'resolution':'Review'}
page=render(report(3))
empty=render(report(0))
checks={
 'previous button': 'id="previous-unreviewed"' in page,
 'next button preserved': 'id="next-unreviewed"' in page,
 'shared help': page.count('aria-describedby="next-unreviewed-help"')==2,
 'both disabled when complete': 'previousButton.disabled=remaining===0;' in page and 'nextButton.disabled=remaining===0;' in page,
 'previous count': "'前の未確認項目へ（残り '+remaining+' 件）'" in page,
 'next count': "'次の未確認項目へ（残り '+remaining+' 件）'" in page,
 'forward skip': 'item.index>lastFocusedIndex' in page,
 'backward skip': 'item.index<lastFocusedIndex' in page,
 'forward wrap': '|| candidates[0]' in page,
 'backward wrap': '|| candidates[candidates.length-1]' in page,
 'next handler': "()=>navigateUnreviewed(1)" in page,
 'previous handler': "()=>navigateUnreviewed(-1)" in page,
 'no auto-review': ".checked=true" not in page,
 'search reset': "search.value='';" in page,
 'filter reset': 'only.checked=false;' in page,
 'focus': 'entry.row.focus();' in page,
 'scroll': "entry.row.scrollIntoView({block:'center',behavior:'auto'});" in page,
 'empty report': 'id="previous-unreviewed"' in empty,
 'progress schema unchanged': "schema_version:2,kind:'conflict_review_progress'" in page,
 'offline': 'https://' not in page and 'http://' not in page,
}
js=re.search(r'<script type="text/javascript">(.*?)</script>',page,re.S).group(1)
checks['javascript syntax']=subprocess.run(['node','--check','-'],input=js,text=True,capture_output=True).returncode==0
for label,ok in checks.items(): print(('PASS' if ok else 'FAIL'),label)
print(f'FIXED397: {sum(checks.values())}/{len(checks)} passed')
assert all(checks.values())
