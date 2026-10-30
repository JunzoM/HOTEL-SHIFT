#!/usr/bin/env python3
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
module_path=root/'Tests/classify_xcode_diagnostics.py'
spec=importlib.util.spec_from_file_location('classifier',module_path)
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
cases=[
('Swift error', 'Views/Foo.swift:12:3: error: cannot convert value', 'Swiftコンパイル'),
('missing module', 'error: No such module SwiftCharts', 'Swiftコンパイル'),
('missing source', 'error: Build input file cannot be found: missing.swift', 'ファイル参照'),
('signing', 'error: Signing for HOTEL_SHIFT requires a development team.', '署名・プロビジョニング'),
('scheme', 'xcodebuild: error: The project does not contain a scheme named HOTEL_SHIFT', 'プロジェクト設定・スキーム'),
('destination', 'error: Unable to find a destination matching the provided destination specifier', 'プロジェクト設定・スキーム'),
('package', 'error: Failed to resolve package dependencies', '依存関係・モジュール'),
('other', 'error: unexpected error happened', 'その他のエラー'),
('non-error', '** BUILD SUCCEEDED **', None),
]
checks=[(name,module.classify(line)==expected) for name,line,expected in cases]
report=module.report('error: Build input file cannot be found\nerror: Signing for HOTEL_SHIFT requires a development team.\n')
checks.append(('multiple categories', '[ファイル参照]' in report and '[署名・プロビジョニング]' in report))
checks.append(('duplicate errors grouped', '1件' in module.report('error: unexpected\nerror: unexpected')))
with tempfile.TemporaryDirectory() as temp:
    fake=Path(temp)/'xcodebuild'
    fake.write_text('#!/bin/sh\necho "error: Build input file cannot be found: Foo.swift"\nexit 65\n')
    fake.chmod(0o755)
    env=os.environ.copy();env['PATH']=temp+os.pathsep+env['PATH']
    run=subprocess.run(['bash',str(root/'Tests/run_xcode_build_check.sh')],cwd=root,env=env,text=True,capture_output=True)
    checks.append(('integrated classification',run.returncode==65 and '[ファイル参照]' in run.stderr))
for name,passed in checks:print(('PASS' if passed else 'FAIL')+' '+name)
print(f'RESULT {sum(x for _,x in checks)}/{len(checks)}')
raise SystemExit(0 if all(x for _,x in checks) else 1)
