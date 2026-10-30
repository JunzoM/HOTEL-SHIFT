#!/usr/bin/env python3
"""Export a deterministic, shareable JSON summary of an Xcode build log."""
import argparse
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from prioritize_xcode_diagnostics import ranked_diagnostics, PRIORITY
from suggest_xcode_fixes import ADVICE
from classify_xcode_diagnostics import classify


def build_report(log, exit_code):
    if exit_code < 0:
        raise ValueError('exit code must be nonnegative')
    counts = {category: 0 for category in PRIORITY}
    unique = set()
    for raw in log.splitlines():
        category = classify(raw)
        if category is not None:
            key = (category, raw.strip())
            if key not in unique:
                unique.add(key)
                counts[category] += 1
    ranked = ranked_diagnostics(log, limit=10)
    return {
        'schema_version': 1,
        'result': 'success' if exit_code == 0 else 'failure',
        'exit_code': exit_code,
        'diagnostic_count': len(unique),
        'category_counts': {key: value for key, value in counts.items() if value},
        'prioritized_diagnostics': [
            {'category': category, 'log_line': number, 'message': message, 'suggested_check': ADVICE[category]}
            for category, number, message in ranked
        ],
        'note': '優先順位は一般的な調査順の目安であり、原因の確定診断ではありません。',
    }


def write_report(path, report):
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Do not leave a truncated report if the process is interrupted.
    fd, temporary = tempfile.mkstemp(prefix='.xcode-report-', suffix='.json', dir=str(destination.parent))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(report, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('exit_code', type=int)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    try:
        report = build_report(args.log.read_text(encoding='utf-8', errors='replace'), args.exit_code)
        write_report(args.output, report)
    except (OSError, ValueError) as exc:
        parser.exit(2, f'Cannot export build report: {exc}\n')
    print(f'Diagnostic JSON report: {args.output}')


if __name__ == '__main__':
    main()
