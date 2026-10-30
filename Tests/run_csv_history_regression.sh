#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
validator="HOTEL_SHIFT/Services/CSVHistoryFilterValidator.swift"
for version in 329 331 335 336 337 338 350 351 352 354 357 359 360; do
  cp "Tests/verify_fixed${version}.swift" "$tmpdir/main.swift"
  if [[ "$version" == 350 || "$version" == 360 ]]; then
    swiftc "$validator" HOTEL_SHIFT/Models/CSVHistoryFeedbackPolicy.swift HOTEL_SHIFT/Models/CSVHistoryFeedbackPresentation.swift "$tmpdir/main.swift" -o "$tmpdir/test${version}"
  else
    swiftc "$validator" "$tmpdir/main.swift" -o "$tmpdir/test${version}"
  fi
  echo "=== FIXED${version} ==="
  "$tmpdir/test${version}" | tail -1
done
bash Tests/run_feedback_regression.sh
