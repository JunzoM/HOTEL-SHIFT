#!/usr/bin/env python3
"""FIXED380: last bulk operation undo and protection of subsequent manual edits."""
import importlib.util
from pathlib import Path
p = Path(__file__).with_name('enable_triage_html_editor.py')
spec = importlib.util.spec_from_file_location('triage_editor', p)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
page = mod.render({'items': [{'issue_id': 'a', 'manual_status': '未対応'}, {'issue_id': 'b', 'manual_status': '対応中'}]})
checks = {
    'undo initially disabled': 'id="edit-undo" disabled' in page,
    'undo listener': "undoButton.addEventListener('click'" in page,
    'undo restores previous value': 'backwards ? change.before : change.after' in page,
    'undo stack bounded': 'undoStack.length > 100' in page,
    'redo cleared after new edit': 'redoStack.length = 0' in page,
    'bulk captures original status': 'before:select.value, after:target' in page,
    'bulk changes visible rows only': 'rows.filter(row => !row.hidden)' in page,
    'bulk requires confirmation': 'if (!window.confirm(' in page,
    'individual changes are undoable': "commitEdit('個別変更'" in page,
    'export still covers all': 'for (const select of selections)' in page,
    'empty report has undo': 'id="edit-undo" disabled' in mod.render({'items': []}),
    'escape unsafe text': '&lt;script&gt;' in mod.render({'items': [{'issue_id': 'x', 'message': '<script>'}]}),
}

for name, ok in checks.items():
    print(('PASS' if ok else 'FAIL'), name)
assert all(checks.values())
print(f'FIXED380: {len(checks)}/{len(checks)} passed')
