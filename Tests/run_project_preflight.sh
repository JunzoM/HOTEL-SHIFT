#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Tests/verify_fixed361_project.py
python3 Tests/verify_fixed362.py
python3 Tests/verify_fixed363.py
find HOTEL_SHIFT -name '*.swift' -print0 | while IFS= read -r -d '' file; do swiftc -frontend -parse "$file"; done
bash Tests/run_csv_history_regression.sh
printf '\nFIXED363 preflight passed (Xcode build and iPad runtime not checked).\n'
if [[ "${RUN_XCODE_BUILD:-0}" == "1" ]]; then
  bash Tests/run_xcode_build_check.sh
fi
