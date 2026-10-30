#!/usr/bin/env python3
"""FIXED381: audit history for manual, bulk, undo, and independent export."""
import importlib.util
from pathlib import Path
p = Path(__file__).with_name('enable_triage_html_editor.py')
spec = importlib.util.spec_from_file_location('triage_editor', p)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
page = mod.render({'items': [{'issue_id': 'a', 'manual_status': '未対応'}, {'issue_id': 'b', 'manual_status': '対応中'}]})
checks = {
    'history heading': 'このページでの変更履歴' in page,
    'history list': 'id="change-history"' in page,
    'history count': 'id="history-count"' in page,
    'history export button': 'id="export-history"' in page,
    'session-only array': 'const changeHistory = [];' in page,
    'manual edits tracked': "commitEdit('個別変更'" in page,
    'bulk edits tracked': "commitEdit('一括変更'" in page,
    'undo tracked': "recordChange(backwards ? '取り消し' : 'やり直し'" in page,
    'unchanged entries excluded': 'entry.before !== entry.after' in page,
    'stable issue id recorded': 'issue_id:select.dataset.issueId' in page,
    'old and new values': 'before:select.value, after:target' in page,
    'export separate from statuses': "downloadJSON('status_change_history.json'" in page and "downloadJSON('manual_statuses.json'" in page,
    'schema version': '{schema_version:1, changes:changeHistory}' in page,
    'no local storage': 'localStorage' not in page and 'sessionStorage' not in page,
    'empty report still shows history': 'id="change-history"' in mod.render({'items': []}),
    'escaped issue text': '&lt;script&gt;' in mod.render({'items': [{'issue_id': 'x', 'message': '<script>'}]}),
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL'), name)
assert all(checks.values())
print(f'FIXED381: {len(checks)}/{len(checks)} passed')
