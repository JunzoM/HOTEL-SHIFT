#!/usr/bin/env bash
# Bounded regression runner. Supports --recent N and --timeout SECONDS.
set -euo pipefail
cd "$(dirname "$0")/.."
latest=$(find Tests -maxdepth 1 -name 'verify_fixed[0-9]*.py' -printf '%f\n' | sed -n 's/^verify_fixed\([0-9][0-9]*\)\.py$/\1/p' | sort -n | tail -1)
[[ -n $latest ]] || { echo 'No regression tests found' >&2; exit 2; }
versions=($(seq 375 "$latest"))
recent=0
timeout_seconds=60
while (( $# )); do
  case "$1" in
    --recent) [[ $# -ge 2 && $2 =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid --recent' >&2; exit 2; }; recent=$2; shift 2 ;;
    --timeout) [[ $# -ge 2 && $2 =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid --timeout' >&2; exit 2; }; timeout_seconds=$2; shift 2 ;;
    *) echo 'Usage: run_triage_editor_regression.sh [--recent N] [--timeout SECONDS]' >&2; exit 2 ;;
  esac
done
if (( recent > 0 && recent < ${#versions[@]} )); then
  versions=("${versions[@]: -recent}")
fi
failures=0
passed=0
for version in "${versions[@]}"; do
  echo "=== FIXED${version} ==="
  if timeout "${timeout_seconds}s" python3 "Tests/verify_fixed${version}.py" > /tmp/hotel_shift_regression_$$.log 2>&1; then
    tail -1 /tmp/hotel_shift_regression_$$.log
    passed=$((passed + 1))
  else
    code=$?
    echo "FIXED${version} failed (exit ${code}); log:" >&2
    tail -20 /tmp/hotel_shift_regression_$$.log >&2
    failures=$((failures + 1))
  fi
done
rm -f /tmp/hotel_shift_regression_$$.log
echo "Regression summary: ${passed} passed, ${failures} failed, $((passed + failures)) total"
if (( failures )); then echo "Regression failures: ${failures}" >&2; exit 1; fi
printf '\nTriage editor regression suite passed.\n'
