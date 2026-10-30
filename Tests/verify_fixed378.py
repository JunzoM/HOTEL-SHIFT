#!/usr/bin/env python3
"""Regression checks for triage editor sorting and status-safe exports."""
import importlib.util
from pathlib import Path
root = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('editor', root / 'enable_triage_html_editor.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
page = module.render({'items': [
    {'issue_id': 'a', 'priority': '高', 'manual_status': '修正済み'},
    {'issue_id': 'b', 'priority': '中', 'manual_status': '未対応'},
    {'issue_id': 'c', 'priority': '要確認', 'manual_status': '対応中'},
]})
checks = {
    'sort selector': 'id="sort-mode"' in page,
    'default unresolved first': '<option value="status">未対応を優先</option>' in page,
    'priority sort': '<option value="priority">優先度順</option>' in page,
    'original order': '<option value="original">元の順序</option>' in page,
    'priority rank': "'高': 0, '中': 1, '要確認': 2" in page,
    'status rank': "'未対応': 0, '対応中': 1, '修正済み': 2" in page,
    'stable original ordering': 'a.index - b.index' in page,
    'unknown rank safe': 'hasOwnProperty.call(map, value)' in page,
    'sort listener': "sortMode.addEventListener('change', updateFilters)" in page,
    'sort when filtering': 'function updateFilters() {\n    sortRows();' in page,
    'sort when editing': "select.addEventListener('change', () =>" in page and "updateFilters();" in page,
    'reorder rows': 'tableBody.appendChild(item.row)' in page,
    'status from current selector': "a.row.querySelector('select[data-issue-id]').value" in page,
    'hidden statuses exported': 'for (const select of selections)' in page,
    'no items works': '診断対象なし' in module.render({'items': []}),
    'escaping maintained': '&lt;script&gt;' in module.render({'items': [{'issue_id':'x','message':'<script>'}]}),
}
for name, ok in checks.items():
    print(('PASS' if ok else 'FAIL'), name)
assert all(checks.values())
print(f'FIXED378: {len(checks)}/{len(checks)} passed')
