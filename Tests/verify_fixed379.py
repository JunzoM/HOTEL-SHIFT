#!/usr/bin/env python3
"""FIXED379: regression checks for visible-only bulk status edits."""
import importlib.util
from pathlib import Path
p = Path(__file__).with_name('enable_triage_html_editor.py')
spec = importlib.util.spec_from_file_location('triage_editor', p)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
page = mod.render({'items':[{'issue_id':'one','manual_status':'未対応'},{'issue_id':'two','manual_status':'対応中'}]})
checks = {
    'bulk selector': 'id="bulk-status"' in page,
    'bulk apply button': 'id="bulk-apply"' in page,
    'bulk feedback': 'id="bulk-message" role="status"' in page,
    'bulk target validated': 'if (!allowed.includes(target)) return;' in page,
    'only visible rows selected': 'rows.filter(row => !row.hidden)' in page,
    'empty result safe': "if (!visibleRows.length)" in page,
    'confirmation required': 'window.confirm(' in page,
    'cancel leaves data intact': 'if (!window.confirm(' in page and ') return;' in page,
    'update selected rows': "for (const row of visibleRows) {" in page and "select.value = target;" in page,
    'filters refreshed': 'updateFilters();\n    bulkMessage.textContent' in page,
    'all statuses still exported': 'for (const select of selections)' in page,
    'all choices': all(f'<option>{x}</option>' in page for x in ('未対応','対応中','修正済み')),
    'zero rows render': 'id="bulk-apply"' in mod.render({'items': []}),
    'HTML escaping': '&lt;script&gt;' in mod.render({'items':[{'issue_id':'safe','message':'<script>'}]}),
}
for k,v in checks.items(): print(('PASS' if v else 'FAIL'),k)
assert all(checks.values())
print(f'FIXED379: {len(checks)}/{len(checks)} passed')
