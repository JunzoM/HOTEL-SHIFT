#!/usr/bin/env python3
"""FIXED395: progress is accessible, consistent, and computed from all conflicts."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from render_xcode_import_conflicts import render

def report(n):
    return {'schema_version':1,'conflict_count':n,'conflicts':[{'issue_id':str(i),'category':'Swift','message':'error','baseline_status':'未対応','current_status':'対応中','imported_status':'修正済み'} for i in range(n)],'resolution':'Review'}
page=render(report(3))
empty=render(report(0))
checks={
 'progressbar accessibility': 'role="progressbar"' in page,
 'progress accessible name': 'aria-label="競合確認の進捗"' in page,
 'progress bounds': 'aria-valuemin="0" aria-valuemax="100"' in page,
 'progress value': 'aria-valuenow="0"' in page,
 'progress fill': 'id="review-progress-fill"' in page,
 'progress label': 'id="review-progress-label"' in page,
 'percentage computation': 'Math.round(reviewed*100/rows.length)' in page,
 'zero count handling': 'rows.length?Math.round(reviewed*100/rows.length):100' in page,
 'remaining count': 'const remaining=rows.length-reviewed;' in page,
 'all rows independent of filters': 'if(done) reviewed++;' in page,
 'progress label updates': "progressLabel.textContent='確認進捗 '" in page,
 'progress aria updates': "progress.setAttribute('aria-valuenow',String(percentage));" in page,
 'progress fill updates': "progressFill.style.width=percentage+'%';" in page,
 'refresh on checkbox': "addEventListener('change',refresh)" in page,
 'refresh on import': 'refresh();\n      importResult.dataset.error' in page,
 'no change to snapshot schema': "schema_version:2,kind:'conflict_review_progress'" in page,
 'empty report': '競合なし' in empty and 'rows.length?Math.round' in empty,
 'offline': 'https://' not in page and 'http://' not in page,
}
for label,ok in checks.items(): print(('PASS' if ok else 'FAIL'),label)
print(f'FIXED395: {sum(checks.values())}/{len(checks)} passed')
assert all(checks.values())
