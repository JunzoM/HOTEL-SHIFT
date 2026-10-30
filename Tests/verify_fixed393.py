#!/usr/bin/env python3
"""FIXED393: precise, accessible errors for importing conflict review progress."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from render_xcode_import_conflicts import render
item={'issue_id':'abc','category':'Swift','message':'error','baseline_status':'未対応','current_status':'対応中','imported_status':'修正済み'}
page=render({'schema_version':1,'conflict_count':1,'conflicts':[item],'resolution':'Review'})
checks={
 'invalid JSON message':'JSONの構文が不正です。' in page,
 'legacy format message':'旧形式の確認状況JSONです。' in page,
 'wrong report message':'別の競合レポートの確認状況です。' in page,
 'count mismatch message':'競合件数が現在のレポートと一致しません。' in page,
 'wrong version message':'種類またはバージョンが対応していません。' in page,
 'unknown ID message':'現在のレポートにない識別ID' in page,
 'duplicate ID message':'重複した識別ID' in page,
 'invalid ID list message':'確認済みIDの一覧が不正' in page,
 'oversized file message':'ファイルが大きすぎます' in page,
 'malformed object message':'確認状況データではありません。' in page,
 'safe JSON parse':'try{payload=JSON.parse(await file.text());}' in page,
 'validation before mutation':'const selected=validateReviewSnapshot(payload);' in page and page.index('const selected=validateReviewSnapshot(payload);') < page.index('rows.forEach(row=>{\n        const check='),
 'failure indicator':'importResult.dataset.error=\'true\'' in page,
 'success indicator':'importResult.dataset.error=\'false\'' in page,
 'accessible status':'role="status" aria-live="polite"' in page,
 'no server dependencies':'https://' not in page and 'http://' not in page,
 'progress export intact':'conflict_review_progress.json' in page,
 'fingerprint guard intact':'value.report_fingerprint!==reportFingerprint' in page,
}
for name,ok in checks.items(): print(('PASS' if ok else 'FAIL'),name)
print(f'FIXED393: {sum(checks.values())}/{len(checks)} passed')
assert all(checks.values())
