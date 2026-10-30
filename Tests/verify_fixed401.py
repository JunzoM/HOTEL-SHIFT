#!/usr/bin/env python3
"""Regression checks for bounded syntax diagnostics and quick triage runs."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CHECK = ROOT / 'Tests/check_swift_syntax.py'
RUNNER = ROOT / 'Tests/run_triage_editor_regression.sh'
checks = {}
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    (root / 'Valid.swift').write_text('struct Sample { let number = 1 }\n')
    cmd = [sys.executable, str(CHECK), '--root', str(root), '--timeout', '3']
    result = subprocess.run(cmd, capture_output=True, text=True)
    checks['valid Swift'] = result.returncode == 0 and '1/1 passed' in result.stdout
    (root / 'Broken.swift').write_text('struct Broken {\n')
    result = subprocess.run(cmd, capture_output=True, text=True)
    checks['syntax failure isolated'] = result.returncode == 1 and 'Broken.swift' in result.stderr and '1/2 passed' in result.stdout
    (root / 'Broken.swift').unlink()
    result = subprocess.run(cmd + ['--swiftc', 'nonexistent-swiftc-401'], capture_output=True, text=True)
    checks['missing compiler diagnosed'] = result.returncode == 1 and 'Valid.swift' in result.stderr
    result = subprocess.run(cmd + ['--timeout', '0'], capture_output=True, text=True)
    checks['invalid timeout rejected'] = result.returncode != 0
    (root / 'Valid.swift').unlink()
    result = subprocess.run(cmd, capture_output=True, text=True)
    checks['empty sources rejected'] = result.returncode != 0
checks['latest regression mode'] = 'versions=("${versions[@]: -recent}")' in RUNNER.read_text() and 'latest=$(find Tests' in RUNNER.read_text()
result = subprocess.run(['bash', str(RUNNER), '--recent', 'abc'], capture_output=True, text=True)
checks['invalid regression argument rejected'] = result.returncode == 2
for label, ok in checks.items():
    print(('PASS' if ok else 'FAIL'), label)
print(f'FIXED401: {sum(checks.values())}/{len(checks)} passed')
assert all(checks.values())
