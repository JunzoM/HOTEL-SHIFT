#!/usr/bin/env python3
"""Static Xcode project audit; does not replace an Xcode build."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
project = (root / 'HOTEL_SHIFT.xcodeproj/project.pbxproj').read_text()
source_root = root / 'HOTEL_SHIFT'
checks = []
def check(label, condition):
    checks.append((label, bool(condition)))
    print(f"{'PASS' if condition else 'FAIL'} {label}")

references = re.findall(r'([A-F0-9]{24})(?:\s*/\*.*?\*/)?\s*=\s*\{isa = PBXFileReference;[^}]*?path = ([^;]+);', project)
source_refs = {identifier: name.strip().strip('"') for identifier, name in references if name.strip().endswith('.swift')}
build_refs = re.findall(r'([A-F0-9]{24})(?:\s*/\*.*?\*/)?\s*=\s*\{isa = PBXBuildFile; fileRef = ([A-F0-9]{24})(?:\s*/\*.*?\*/)?;', project)
source_phase = re.search(r'isa = PBXSourcesBuildPhase;[^}]*?files = \((.*?)\);', project, re.S)
phase_ids = set(re.findall(r'[A-F0-9]{24}', source_phase.group(1))) if source_phase else set()
check('PBXSourcesBuildPhase exists', source_phase is not None)
check('Swift file references exist', bool(source_refs))
check('No duplicate PBXFileReference IDs', len(references) == len({x[0] for x in references}))
check('No duplicate PBXBuildFile IDs', len(build_refs) == len({x[0] for x in build_refs}))
check('Every build phase entry resolves to a build file', phase_ids <= {x[0] for x in build_refs})
check('All Swift build files resolve to file references', all(ref in source_refs for bid, ref in build_refs if bid in phase_ids))
registered = [source_refs[ref] for bid, ref in build_refs if bid in phase_ids and ref in source_refs]
actual = sorted(p.name for p in source_root.rglob('*.swift'))
check('No duplicate Swift filenames', len(actual) == len(set(actual)))
check('All Swift sources included in Xcode target', sorted(registered) == actual)
check('Every registered Swift source exists', all((source_root / name).exists() or any(p.name == name for p in source_root.rglob('*.swift')) for name in registered))
check('Required Info.plist settings present', 'GENERATE_INFOPLIST_FILE = YES' in project)
check('Swift language version set', 'SWIFT_VERSION' in project)
check('iPad target family configured', 'TARGETED_DEVICE_FAMILY' in project and '2' in project)
check('No unresolved merge conflict markers', not any(re.search(r'^(<<<<<<<|=======|>>>>>>>)', p.read_text(), re.M) for p in source_root.rglob('*.swift')))
print(f'RESULT {sum(ok for _, ok in checks)}/{len(checks)}')
raise SystemExit(0 if all(ok for _, ok in checks) else 1)
