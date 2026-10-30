#!/usr/bin/env python3
import importlib.util
from pathlib import Path
root=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('editor',root/'enable_triage_html_editor.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
items=[{'issue_id':'one','category':'Swift','priority':'高','manual_status':'未対応','message':'bad variable'}, {'issue_id':'two','category':'署名','priority':'中','manual_status':'対応中','message':'team error'}]
page=m.render({'items':items})
checks={
 'search control':'id="filter-query"' in page,
 'category control':'id="filter-category"' in page,
 'priority control':'id="filter-priority"' in page,
 'status control':'id="filter-status"' in page,
 'category option':'<option value="Swift">Swift</option>' in page,
 'priority option':'<option value="高">高</option>' in page,
 'row metadata':'data-category="Swift" data-priority="高"' in page,
 'live count':'aria-live="polite"' in page,
 'filter on status change':"select.addEventListener('change', () =>" in page and "updateFilters();" in page,
 'search lower case':'toLocaleLowerCase()' in page,
 'hide nonmatching':'row.hidden = !match' in page,
 'exports all statuses':'for (const select of selections)' in page,
 'empty still works':'診断対象なし' in m.render({'items':[]}),
 'escaped option':'&lt;evil&gt;' in m.render({'items':[{'issue_id':'x','category':'<evil>'}]}),
}
for k,v in checks.items():print(('PASS' if v else 'FAIL'),k)
assert all(checks.values())
print(f'FIXED377: {len(checks)}/{len(checks)} passed')
