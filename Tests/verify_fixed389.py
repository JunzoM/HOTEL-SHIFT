#!/usr/bin/env python3
"""FIXED389: focused conflict review must not alter import safety."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from render_xcode_import_conflicts import render
checks=[]
def check(name,ok):
    checks.append(bool(ok)); print(('PASS' if ok else 'FAIL'),name)
items=[{'issue_id':f'id-{n}','category':'Swift' if n==0 else '設定','message':f'error {n} <img src=x onerror=alert(1)>','baseline_status':'未対応','current_status':'対応中','imported_status':'修正済み'} for n in range(2)]
page=render({'schema_version':1,'conflict_count':2,'conflicts':items,'resolution':'Review'})
for name,needle in [('search input','id="conflict-search"'),('unreviewed toggle','id="unreviewed-only"'),('visible count','id="review-count"'),('live update','aria-live="polite"'),('review checkbox','class="review-check"'),('filter logic','row.hidden=!show'),('no automatic status changes','row.querySelector(\'.review-check\').checked'),('reviewed counter','確認済み'),('recovery guide','安全に再編集・再取り込みする手順')]:
    check(name,needle in page)
check('two review rows',page.count('data-conflict-row>')==2)
check('escaped hostile content','&lt;img src=x onerror=alert(1)&gt;' in page and '<img src=x onerror=alert(1)>' not in page)
check('unique IDs rendered',all(item['issue_id'] in page for item in items))
check('empty report supported','競合なし' in render({'schema_version':1,'conflict_count':0,'conflicts':[],'resolution':''}))
print(f'FIXED389: {sum(checks)}/{len(checks)} passed')
assert all(checks)
