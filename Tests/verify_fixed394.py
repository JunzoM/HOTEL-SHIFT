#!/usr/bin/env python3
"""FIXED394: actionable recovery guidance without unsafe state mutation."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from render_xcode_import_conflicts import render
item={'issue_id':'abc','category':'Swift','message':'error','baseline_status':'未対応','current_status':'対応中','imported_status':'修正済み'}
page=render({'schema_version':1,'conflict_count':1,'conflicts':[item],'resolution':'Review'})
checks={
 'recovery panel': 'id="import-help" role="note" hidden' in page,
 'recovery content': 'id="import-help-text"' in page,
 'legacy guidance': '旧形式をこの画面に強制適用しないでください' in page,
 'wrong report guidance': '現在のレポートには適用できません' in page,
 'count guidance': '正しい組み合わせで再度読み込んでください' in page,
 'ID guidance': 'JSONのIDを手動で書き換えないでください' in page,
 'syntax guidance': 'ファイルが壊れている場合' in page,
 'size guidance': '1MB以下' in page,
 'fallback guidance': '新しく保存し直してください' in page,
 'guidance function': 'function recoveryGuidance(message)' in page,
 'failure reveals guidance': 'importHelp.hidden=false;' in page,
 'success clears guidance': 'importHelp.hidden=true;' in page and "importHelpText.textContent='';" in page,
 'safe text only': 'importHelpText.textContent=recoveryGuidance(message)' in page,
 'validate before checkbox updates': page.index('const selected=validateReviewSnapshot(payload);') < page.index('rows.forEach(row=>{\n        const check='),
 'existing fingerprint check': 'value.report_fingerprint!==reportFingerprint' in page,
 'offline': 'https://' not in page and 'http://' not in page,
}
for name,ok in checks.items(): print(('PASS' if ok else 'FAIL'),name)
print(f'FIXED394: {sum(checks.values())}/{len(checks)} passed')
assert all(checks.values())
