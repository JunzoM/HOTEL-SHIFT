#!/usr/bin/env python3
"""FIXED382 editor undo/redo smoke checks."""
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).parent))
from enable_triage_html_editor import render

html = render({'items': [{'issue_id':'issue-a','manual_status':'未対応'}, {'issue_id':'issue-b','manual_status':'対応中'}]})
js = html.split('<script>', 1)[1].split('</script>', 1)[0]
checks = {
    'undo control': 'id="edit-undo"' in html,
    'redo control': 'id="edit-redo"' in html,
    'undo stack': 'const undoStack = []' in js,
    'redo stack': 'const redoStack = []' in js,
    'bounded history': 'undoStack.length > 100' in js,
    'new edit clears redo': 'redoStack.length = 0' in js,
    'undo pops': 'undoStack.pop()' in js,
    'redo pops': 'redoStack.pop()' in js,
    'individual edits': "commitEdit('個別変更'" in js,
    'bulk edits': "commitEdit('一括変更'" in js,
    'no old bulk undo': 'bulk-undo' not in html,
    'history export': 'status_change_history.json' in js,
    'status export': 'manual_statuses.json' in js,
    'filter retained': 'function updateFilters()' in js,
    'priority sorting retained': 'function sortRows()' in js,
}
Path('/tmp/fixed382-editor.js').write_text(js)
checks['javascript syntax'] = subprocess.run(['node', '--check', '/tmp/fixed382-editor.js'], capture_output=True).returncode == 0
for name, result in checks.items():
    print(('PASS' if result else 'FAIL') + ' ' + name)
assert all(checks.values())
print(f'FIXED382: {len(checks)}/{len(checks)} passed')
