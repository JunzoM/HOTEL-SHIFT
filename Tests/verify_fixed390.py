#!/usr/bin/env python3
"""FIXED390 conflict review JSON export regression checks."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from render_xcode_import_conflicts import render
item={'issue_id':'id-<unsafe>','category':'Swift','message':'error','baseline_status':'未対応','current_status':'対応中','imported_status':'修正済み'}
page=render({'schema_version':1,'conflict_count':1,'conflicts':[item],'resolution':'Review'})
checks={
 'export button': 'id="export-review"' in page,
 'JSON type': "type:'application/json'" in page,
 'export filename': 'conflict_review_progress.json' in page,
 'review only marker': "kind:'conflict_review_progress'" in page,
 'checked only': "rows.filter(row=>row.querySelector('.review-check').checked)" in page,
 'ID not innerHTML': "getAttribute('data-issue-id')" in page,
 'safe ID attribute': 'data-issue-id="id-&lt;unsafe&gt;"' in page,
 'no status mutation': '保存済みの対応状況も変更しません' in page,
 'download trigger': 'anchor.click()' in page,
 'object URL cleanup': 'URL.revokeObjectURL(url)' in page,
 'empty report export': 'id="export-review"' in render({'schema_version':1,'conflict_count':0,'conflicts':[],'resolution':''}),
}
for name,ok in checks.items(): print(('PASS' if ok else 'FAIL'),name)
print(f'FIXED390: {sum(checks.values())}/{len(checks)} passed')
assert all(checks.values())
