#!/usr/bin/env bash
# FIXED363: Xcode simulator build with a concise diagnostic report on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'ERROR: xcodebuild is unavailable. Run this script on a Mac with Xcode installed.' >&2
  exit 2
fi
if command -v xcode-select >/dev/null 2>&1; then
  developer_dir="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$developer_dir" == */CommandLineTools ]]; then
    echo 'ERROR: Select full Xcode with xcode-select before building.' >&2
    exit 2
  fi
fi
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
log_file="$build_dir/xcodebuild.log"
# A stable log path can be requested explicitly; avoid leaving artifacts by default.
if [[ -n "${XCODE_BUILD_LOG:-}" ]]; then
  log_file="$XCODE_BUILD_LOG"
  mkdir -p "$(dirname "$log_file")"
fi
printf 'Running Xcode simulator build...\n'
# Preserve xcodebuild's exit status even while teeing the full log.
set +e
xcodebuild \
  -project HOTEL_SHIFT.xcodeproj \
  -scheme HOTEL_SHIFT \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$build_dir/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tee "$log_file"
build_status=${PIPESTATUS[0]}
set -e
# FIXED367: Opt-in machine-readable report, retained for both successful and failed builds.
# Set XCODE_DIAGNOSTIC_REPORT to an output .json path.
if [[ -n "${XCODE_DIAGNOSTIC_REPORT:-}" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 Tests/export_xcode_diagnostic_report.py "$log_file" "$build_status" "$XCODE_DIAGNOSTIC_REPORT" || echo 'WARNING: Diagnostic report could not be saved.' >&2
  else
    echo 'WARNING: Python 3 is required to save the diagnostic report.' >&2
  fi
fi
if (( build_status != 0 )); then
  echo >&2
  echo 'Xcode build failed. Relevant diagnostics (up to 40 lines):' >&2
  # Match Swift/compiler errors and common project configuration failures.
  if ! grep -nE '(^|[[:space:]])(error:|fatal error:)|\.swift:[0-9]+:[0-9]+:|BUILD FAILED|No such module|Signing for|Unable to find a destination|does not contain a scheme' "$log_file" | tail -n 40 >&2; then
    tail -n 40 "$log_file" >&2
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf '\nClassified build errors:\n' >&2
    python3 Tests/classify_xcode_diagnostics.py "$log_file" >&2 || true
    printf '\nSuggested checks:\n' >&2
    python3 Tests/suggest_xcode_fixes.py "$log_file" >&2 || true
    printf '\nPrioritized checks:\n' >&2
    python3 Tests/prioritize_xcode_diagnostics.py "$log_file" >&2 || true
  fi
  if [[ -n "${XCODE_BUILD_LOG:-}" ]]; then
    printf 'Full build log: %s\n' "$log_file" >&2
  else
    echo 'To retain the full log, rerun with XCODE_BUILD_LOG=/path/to/build.log.' >&2
  fi
  exit "$build_status"
fi
printf '\nFIXED363 Xcode simulator build succeeded.\n'
if [[ -n "${XCODE_BUILD_LOG:-}" ]]; then
  printf 'Full build log: %s\n' "$log_file"
fi
