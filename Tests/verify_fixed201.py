#!/usr/bin/env python3
"""Static checks of the Xcode project, without claiming an Apple SDK build."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
project = (root / 'HOTEL_SHIFT.xcodeproj/project.pbxproj').read_text()
source_dir = root / 'HOTEL_SHIFT'
swift_files = sorted(source_dir.rglob('*.swift'))
assert swift_files, 'No Swift sources found'

# Every Swift file on disk must be included exactly once in the build phase.
file_refs = dict(re.findall(r'([A-F0-9]{24}) = \{isa = PBXFileReference; lastKnownFileType = sourcecode\.swift; path = ([^;]+);', project))
build_refs = re.findall(r'[A-F0-9]{24} = \{isa = PBXBuildFile; fileRef = ([A-F0-9]{24}); \};', project)
sources_phase = re.search(r'isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);', project)
assert sources_phase, 'Missing Sources build phase'
phase_ids = re.findall(r'[A-F0-9]{24}', sources_phase.group(1))
build_file_map = dict(re.findall(r'([A-F0-9]{24}) = \{isa = PBXBuildFile; fileRef = ([A-F0-9]{24}); \};', project))
phase_swift_refs = [build_file_map[x] for x in phase_ids if x in build_file_map and build_file_map[x] in file_refs]
actual_names = sorted(p.name for p in swift_files)
registered_names = sorted(file_refs[x] for x in phase_swift_refs)
assert actual_names == registered_names, f'Swift sources mismatch: on disk {actual_names}, in build {registered_names}'
assert len(set(phase_swift_refs)) == len(phase_swift_refs), 'Duplicate Swift source in build phase'

for ref in file_refs.values():
    matches = list(source_dir.rglob(ref))
    assert len(matches) == 1, f'Swift source missing or ambiguous: {ref}'
assert 'TARGETED_DEVICE_FAMILY = "2";' in project, 'Target is not iPad-only'
assert 'IPHONEOS_DEPLOYMENT_TARGET = 17.0;' in project, 'Unexpected deployment target'
assert project.count('SWIFT_VERSION = 5.0;') >= 2, 'Swift version not configured'
assert 'GENERATE_INFOPLIST_FILE = YES;' in project, 'Info.plist generation missing'
assert (source_dir / 'Assets.xcassets/Contents.json').is_file(), 'Asset catalog missing'
print(f'PASS: {len(swift_files)} Swift sources registered exactly once in Xcode target')
print('PASS: iPad-only target, iPadOS 17 minimum, Swift 5, generated Info.plist')
print('PASS: asset catalog and referenced source files exist')
