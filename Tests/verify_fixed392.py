#!/usr/bin/env python3
"""FIXED392: bind saved review progress to the exact conflict report."""
import hashlib
import json
import re
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from render_xcode_import_conflicts import render

def report(items):
    return {'schema_version':1,'conflict_count':len(items),'conflicts':items,'resolution':'Review'}
def fingerprint(page):
    return re.search(r'const reportFingerprint="([0-9a-f]{64})";',page).group(1)
def item(id, current='対応中', message='error'):
    return {'issue_id':id,'category':'Swift','message':message,'baseline_status':'未対応','current_status':current,'imported_status':'修正済み'}
a=item('A'); b=item('B')
first=render(report([a,b])); reordered=render(report([b,a])); changed=render(report([item('A','修正済み'),b])); changed_message=render(report([item('A',message='different'),b])); swapped=render(report([item('A'),item('C')]))
checks={
 'sha256 fingerprint embedded':len(fingerprint(first))==64,
 'same report stable':fingerprint(first)==fingerprint(render(report([a,b]))),
 'reordered rows stable':fingerprint(first)==fingerprint(reordered),
 'changed status changes identity':fingerprint(first)!=fingerprint(changed),
 'changed message changes identity':fingerprint(first)!=fingerprint(changed_message),
 'different ids change identity':fingerprint(first)!=fingerprint(swapped),
 'sha256 expected':fingerprint(first)==hashlib.sha256(json.dumps(sorted([a,b],key=lambda x:x['issue_id']),ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
 'export version 2':'return {schema_version:2' in first,
 'export fingerprint':'report_fingerprint:reportFingerprint' in first,
 'import version guard':'value.schema_version!==2' in first,
 'import fingerprint guard':'value.report_fingerprint!==reportFingerprint' in first,
 'validate before checkbox mutation':('const selected=validateReviewSnapshot(JSON.parse(await file.text()));' in first or 'const selected=validateReviewSnapshot(payload);' in first),
 'legacy progress refused':'value.schema_version!==2' in first,
 'empty report stable':fingerprint(render(report([])))==fingerprint(render(report([]))),
 'script syntax closure':'</script></body></html>' in first,
}
for label,ok in checks.items(): print(('PASS' if ok else 'FAIL'),label)
print(f'FIXED392: {sum(checks.values())}/{len(checks)} passed')
assert all(checks.values())
