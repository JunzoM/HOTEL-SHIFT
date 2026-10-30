#!/usr/bin/env bash
# FIXED370: One command for build, comparison JSON and standalone HTML.
set -euo pipefail
cd "$(dirname "$0")/.."
if (( $# != 1 )); then
  echo 'Usage: bash Tests/run_xcode_report_pipeline.sh PREVIOUS_REPORT.json' >&2
  exit 2
fi
previous="$1"
if [[ ! -f "$previous" ]]; then
  echo "Previous report not found: $previous" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo 'Python 3 is required.' >&2
  exit 2
fi
output_dir="${XCODE_REPORT_DIR:-reports}"
mkdir -p "$output_dir"
current="$output_dir/current.json"
diff="$output_dir/diff.json"
html="$output_dir/diff.html"
# Do not use a stale report if the build fails before exporting a new one.
rm -f "$current" "$diff" "$html"
set +e
XCODE_DIAGNOSTIC_REPORT="$current" bash Tests/run_xcode_build_check.sh
build_status=$?
set -e
if [[ ! -f "$current" ]]; then
  echo 'No current report was produced (Xcode unavailable or build could not start).' >&2
  if (( build_status == 0 )); then exit 2; else exit "$build_status"; fi
fi
python3 Tests/archive_xcode_diagnostic_report.py "$current" --directory "$output_dir/history"
python3 Tests/render_xcode_history_trend.py "$output_dir/history/index.json" --output "$output_dir/history/trend.html"
python3 Tests/analyze_xcode_persistent_errors.py "$output_dir/history" --output "$output_dir/history/persistent.json" --html "$output_dir/history/persistent.html"
python3 Tests/triage_xcode_persistent_errors.py "$output_dir/history/persistent.json" --output "$output_dir/history/triage.json" --html "$output_dir/history/triage.html"
python3 Tests/manage_xcode_triage_status.py "$output_dir/history/triage.json" --statuses "$output_dir/history/manual_statuses.json" --output "$output_dir/history/triage_status.json" --html "$output_dir/history/triage_status.html"
python3 Tests/enable_triage_html_editor.py "$output_dir/history/triage_status.json" --output "$output_dir/history/triage_editor.html"
python3 Tests/compare_xcode_diagnostic_reports.py "$previous" "$current" --output "$diff"
python3 Tests/render_xcode_diagnostic_comparison.py "$diff" --output "$html"
printf '\nReport: %s\nComparison: %s\nHTML: %s\nHistory trend: %s\n' "$current" "$diff" "$html" "$output_dir/history/trend.html"
exit "$build_status"
