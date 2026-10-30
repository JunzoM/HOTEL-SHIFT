#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
models=(HOTEL_SHIFT/Models/CSVHistoryFeedbackPolicy.swift HOTEL_SHIFT/Models/CSVHistoryFeedbackPresentation.swift)
for version in 345 346 347 348; do
  src="Tests/verify_fixed${version}.swift"
  if [[ "$version" == 345 || "$version" == 346 ]]; then
    # Swift requires top-level executable statements in a file named main.swift
    cp "$src" "$tmpdir/main.swift"
    swiftc "${models[@]}" "$tmpdir/main.swift" -o "$tmpdir/test${version}"
  else
    swiftc "${models[@]}" "$src" -o "$tmpdir/test${version}"
  fi
  echo "=== FIXED${version} ==="
  "$tmpdir/test${version}" | tail -1
done
