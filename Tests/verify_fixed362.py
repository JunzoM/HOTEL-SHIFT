#!/usr/bin/env python3
"""FIXED362 preflight: validate build script contract and Xcode configuration references."""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
pbx = (root / 'HOTEL_SHIFT.xcodeproj/project.pbxproj').read_text()
script = (root / 'Tests/run_xcode_build_check.sh').read_text()
# PBX comments and line breaks do not alter reference semantics.
normalized_pbx = re.sub(r'/\*.*?\*/', '', pbx, flags=re.S)
checks = {
    'build uses actual xcodebuild': 'xcodebuild \\' in script,
    'project explicitly selected': '-project HOTEL_SHIFT.xcodeproj' in script,
    'scheme explicitly selected': '-scheme HOTEL_SHIFT' in script,
    'simulator SDK selected': '-sdk iphonesimulator' in script,
    'generic simulator destination': "generic/platform=iOS Simulator" in script,
    'code signing disabled only for build': 'CODE_SIGNING_ALLOWED=NO' in script,
    'temporary build products cleaned': "trap 'rm -rf \"$build_dir\"' EXIT" in script,
    'missing Xcode detected': 'command -v xcodebuild' in script,
    'full Xcode required': '*/CommandLineTools' in script,
    'Xcode target exists': 'isa = PBXNativeTarget;' in pbx and 'name = HOTEL_SHIFT;' in pbx,
    'project points to target': bool(re.search(r'targets\s*=\s*\(\s*A10000000000000000000040\s*,?\s*\);', normalized_pbx)),
    'debug and release target configurations': len(re.findall(r'isa = XCBuildConfiguration;.*?name = (?:Debug|Release);', normalized_pbx, re.S)) >= 4,
    'iOS deployment target set': 'IPHONEOS_DEPLOYMENT_TARGET = 17.0;' in pbx,
    'app bundle identifier configured': 'PRODUCT_BUNDLE_IDENTIFIER = jp.hotelshift.app;' in pbx,
    'asset catalog exists': (root / 'HOTEL_SHIFT/Assets.xcassets').is_dir(),
    'Swift app entry point exists': (root / 'HOTEL_SHIFT/HOTELSHIFTApp.swift').is_file(),
}
for label, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ' ' + label)
print(f'RESULT {sum(checks.values())}/{len(checks)}')
raise SystemExit(0 if all(checks.values()) else 1)
