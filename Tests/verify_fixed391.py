#!/usr/bin/env python3
"""FIXED391 review progress import regression."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from render_xcode_import_conflicts import render
item={'issue_id':'issue-A','category':'Swift','message':'error','baseline_status':'未対応','current_status':'対応中','imported_status':'修正済み'}
page=render({'schema_version':1,'conflict_count':1,'conflicts':[item],'resolution':'Review'})
checks={
'file input':'id="import-review"' in page,
'feedback region':'id="import-result"' in page,
'file size limit':'file.size>1024*1024' in page,
'JSON parsing':'JSON.parse(await file.text())' in page,
'schema check':'value.schema_version!==2' in page,
'kind check':"value.kind!=='conflict_review_progress'" in page,
'count check':'value.conflict_count!==rows.length' in page,
'array check':'!Array.isArray(value.reviewed_ids)' in page,
'unknown ID guard':'!known.has(id)' in page,
'duplicate ID guard':'selected.has(id)' in page,
'validate before mutation':('const selected=validateReviewSnapshot(JSON.parse(await file.text()));' in page or 'const selected=validateReviewSnapshot(payload);' in page),
'restore checkboxes':'check.checked=selected.has(' in page,
'refresh view':('refresh();\n      importResult.textContent=' in page or "refresh();\n      importResult.dataset.error='false';" in page),
'error feedback':"importResult.textContent='読み込み中止：'" in page,
'input reset':"finally{importInput.value='';}" in page,
'export still present':'id="export-review"' in page,
'no server needed':'fetch(' not in page,
'empty report supported':'id="import-review"' in render({'schema_version':1,'conflict_count':0,'conflicts':[],'resolution':''}),
}
for label,ok in checks.items():print(('PASS' if ok else 'FAIL'),label)
print(f'FIXED391: {sum(checks.values())}/{len(checks)} passed')
assert all(checks.values())
