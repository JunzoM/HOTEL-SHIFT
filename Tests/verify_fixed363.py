#!/usr/bin/env python3
"""FIXED363: check build script with a mock Xcode binary, including failures."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
script = root / 'Tests/run_xcode_build_check.sh'
checks = []
with tempfile.TemporaryDirectory() as tmp:
    mock = Path(tmp) / 'xcodebuild'
    mock.write_text('#!/usr/bin/env bash\necho "Views/ShiftCalendarView.swift:42:8: error: test failure"\nexit 65\n')
    mock.chmod(0o755)
    env = os.environ.copy()
    env['PATH'] = tmp + os.pathsep + env['PATH']
    log = Path(tmp) / 'logs/build.log'
    env['XCODE_BUILD_LOG'] = str(log)
    failed = subprocess.run(['bash', str(script)], cwd=root, env=env, capture_output=True, text=True)
    checks += [
        ('compiler failure exit code preserved', failed.returncode == 65),
        ('diagnostic includes Swift path and line', 'ShiftCalendarView.swift:42:8' in failed.stderr),
        ('diagnostic includes compiler error', 'error: test failure' in failed.stderr),
        ('full log retained on request', log.exists() and 'test failure' in log.read_text()),
    ]
    mock.write_text('#!/usr/bin/env bash\necho "** BUILD SUCCEEDED **"\nexit 0\n')
    succeeded = subprocess.run(['bash', str(script)], cwd=root, env=env, capture_output=True, text=True)
    checks += [
        ('successful build returns zero', succeeded.returncode == 0),
        ('success confirmation shown', 'build succeeded' in succeeded.stdout),
    ]
    env.pop('XCODE_BUILD_LOG')
    mock.write_text('#!/usr/bin/env bash\necho "error: ephemeral failure"\nexit 2\n')
    no_log = subprocess.run(['bash', str(script)], cwd=root, env=env, capture_output=True, text=True)
    checks += [
        ('failure without persistent log preserves status', no_log.returncode == 2),
        ('failure provides log retention instructions', 'XCODE_BUILD_LOG=' in no_log.stderr),
    ]
source = script.read_text()
checks += [
    ('real simulator target retained', "generic/platform=iOS Simulator" in source),
    ('signing disabled for validation', 'CODE_SIGNING_ALLOWED=NO' in source),
    ('build products cleaned', 'trap ' in source and 'rm -rf "$build_dir"' in source),
]
for label, result in checks:
    print(('PASS' if result else 'FAIL') + ' ' + label)
print(f'RESULT {sum(bool(result) for _, result in checks)}/{len(checks)}')
raise SystemExit(0 if all(result for _, result in checks) else 1)
