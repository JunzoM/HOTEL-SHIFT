#!/usr/bin/env python3
"""FIXED370: pipeline contract and end-to-end report rendering checks."""
import json
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
script = (root / 'Tests/run_xcode_report_pipeline.sh').read_text()
checks = [
    ('strict bash', 'set -euo pipefail' in script),
    ('one previous argument', '(( $# != 1 ))' in script),
    ('missing previous guard', 'Previous report not found' in script),
    ('report output override', 'XCODE_REPORT_DIR:-reports' in script),
    ('stale output cleanup', 'rm -f "$current" "$diff" "$html"' in script),
    ('build result preserved', 'build_status=$?' in script and 'exit "$build_status"' in script),
    ('missing current guard', 'if [[ ! -f "$current" ]]' in script),
    ('JSON comparison', 'compare_xcode_diagnostic_reports.py' in script),
    ('HTML rendering', 'render_xcode_diagnostic_comparison.py' in script),
]
with tempfile.TemporaryDirectory() as td:
    td = Path(td)
    def report(code, message):
        diagnostics = [{'category':'Swift', 'message':message, 'log_line':5}] if code else []
        return {'schema_version':1,'result':'failure' if code else 'success','exit_code':code,
                'category_counts':{'Swift':len(diagnostics)},'diagnostic_count':len(diagnostics),
                'prioritized_diagnostics':diagnostics}
    before, after = td/'before.json', td/'after.json'
    before.write_text(json.dumps(report(1, 'Missing symbol')), encoding='utf-8')
    after.write_text(json.dumps(report(0, '')), encoding='utf-8')
    diff, html = td/'diff.json', td/'diff.html'
    p = subprocess.run(['python3', str(root/'Tests/compare_xcode_diagnostic_reports.py'),str(before),str(after),'--output',str(diff)],capture_output=True,text=True)
    checks.append(('comparison command',p.returncode == 0 and diff.exists()))
    p = subprocess.run(['python3',str(root/'Tests/render_xcode_diagnostic_comparison.py'),str(diff),'--output',str(html)],capture_output=True,text=True)
    checks.append(('HTML command',p.returncode == 0 and html.exists()))
    if html.exists():
        page=html.read_text(encoding='utf-8')
        checks.append(('result visible', 'failure' in page and 'success' in page))
        checks.append(('resolved diagnostic visible', 'Missing symbol' in page))
    p = subprocess.run(['bash',str(root/'Tests/run_xcode_report_pipeline.sh')],cwd=root,capture_output=True,text=True)
    checks.append(('missing argument fails',p.returncode == 2))
    p = subprocess.run(['bash',str(root/'Tests/run_xcode_report_pipeline.sh'),str(td/'missing.json')],cwd=root,capture_output=True,text=True)
    checks.append(('missing file fails',p.returncode == 2))
for label, ok in checks:
    print(('PASS' if ok else 'FAIL'),label)
assert all(ok for _,ok in checks)
print(f'FIXED370: {len(checks)}/{len(checks)} passed')
