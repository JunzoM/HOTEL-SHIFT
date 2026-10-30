#!/usr/bin/env bash
# Build and launch this checkout's Catalyst app, not the iPad app on Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo 'Full Xcode is required.' >&2
    exit 2
fi
if pgrep -x HOTEL_SHIFT >/dev/null 2>&1; then
    echo 'Quit the running HOTEL SHIFT app, then run this script again.' >&2
    exit 2
fi
build_root="$PWD/build-catalyst"
xcodebuild -project HOTEL_SHIFT.xcodeproj -scheme HOTEL_SHIFT \
    -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath "$build_root" build
app_bundle="$build_root/Build/Products/Debug-maccatalyst/HOTEL_SHIFT.app"
if [[ ! -d "$app_bundle" ]]; then
    echo "Expected Catalyst app was not found: $app_bundle" >&2
    exit 1
fi
open -n "$app_bundle"
echo 'Launched FIXED560. Check View menu for FIXED560 / Mac Catalyst.'
