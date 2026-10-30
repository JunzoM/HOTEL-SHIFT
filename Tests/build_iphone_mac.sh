#!/usr/bin/env bash
# Build checks only: does not sign, archive, install, or validate runtime behavior.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo 'Xcode is required. Run this script on a Mac with full Xcode selected.' >&2
    exit 2
fi
build_root="$(mktemp -d)"
trap 'rm -rf "$build_root"' EXIT
for destination in 'generic/platform=iOS Simulator' 'platform=macOS,variant=Mac Catalyst'; do
    xcodebuild -project HOTEL_SHIFT.xcodeproj -scheme HOTEL_SHIFT \
        -configuration Debug -destination "$destination" \
        -derivedDataPath "$build_root/DerivedData" CODE_SIGNING_ALLOWED=NO build
done
