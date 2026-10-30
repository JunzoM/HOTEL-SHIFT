#!/usr/bin/env python3
"""FIXED371 history regression checks."""
import importlib.util
import json
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('history', root / 'Tests/archive_xcode_diagnostic_report.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
checks = []
def check(label, condition):
    checks.append((label, condition))
    print(('PASS' if condition else 'FAIL'), label)
with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    source = tmp / 'current.json'
    directory = tmp / 'history'
    source.write_text(json.dumps({'schema_version': 1, 'result': 'failure', 'diagnostic_count': 3}), encoding='utf-8')
    first = mod.archive(source, directory, stamp='20261025T150000000000Z')
    check('first archive created', first.exists())
    check('archived failure preserved', json.loads(first.read_text())['result'] == 'failure')
    source.write_text(json.dumps({'schema_version': 1, 'result': 'success', 'diagnostic_count': 0}), encoding='utf-8')
    second = mod.archive(source, directory, stamp='20261025T150100000000Z')
    check('second archive created', second.exists())
    check('first archive unchanged', json.loads(first.read_text())['result'] == 'failure')
    index = json.loads((directory/'index.json').read_text())
    check('index has two builds', len(index['builds']) == 2)
    check('history chronological', [v['file'] for v in index['builds']] == [first.name, second.name])
    check('counts retained', [v['diagnostic_count'] for v in index['builds']] == [3, 0])
    try:
        mod.archive(source, directory, stamp='20261025T150100000000Z')
    except FileExistsError:
        check('duplicate timestamp never overwrites', True)
    else:
        check('duplicate timestamp never overwrites', False)
    check('index still intact after collision', len(json.loads((directory/'index.json').read_text())['builds']) == 2)
    invalid = tmp/'invalid.json'
    invalid.write_text('{"schema_version": 0, "result": "success"}')
    try:
        mod.archive(invalid, directory)
    except ValueError:
        check('invalid schema rejected', True)
    else:
        check('invalid schema rejected', False)
    check('invalid report did not add entry', len(list(directory.glob('build-*.json'))) == 2)
    command = subprocess.run(['python3', str(root/'Tests/archive_xcode_diagnostic_report.py'), str(source), '--directory', str(tmp/'cli')], capture_output=True, text=True)
    check('CLI succeeds', command.returncode == 0)
    check('CLI index created', (tmp/'cli/index.json').exists())
    missing = subprocess.run(['python3', str(root/'Tests/archive_xcode_diagnostic_report.py'), str(tmp/'missing.json')], capture_output=True, text=True)
    check('CLI missing report fails', missing.returncode == 2)
    pipeline = (root/'Tests/run_xcode_report_pipeline.sh').read_text()
    check('pipeline archives report', 'archive_xcode_diagnostic_report.py "$current"' in pipeline)
    check('pipeline keeps original build exit status', 'exit "$build_status"' in pipeline)
assert all(ok for _, ok in checks)
print(f'FIXED371: {len(checks)}/{len(checks)} passed')
