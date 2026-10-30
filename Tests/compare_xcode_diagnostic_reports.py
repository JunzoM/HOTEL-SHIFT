#!/usr/bin/env python3
"""Compare FIXED367 diagnostic JSON reports without relying on log line positions."""
import argparse
import json
import sys
from collections import Counter
from pathlib import Path


def validate(report):
    if not isinstance(report, dict) or report.get('schema_version') != 1:
        raise ValueError('unsupported diagnostic report schema (expected version 1)')
    if report.get('result') not in ('success', 'failure'):
        raise ValueError('invalid build result')
    if not isinstance(report.get('exit_code'), int) or isinstance(report['exit_code'], bool) or report['exit_code'] < 0:
        raise ValueError('invalid exit code')
    if (report['exit_code'] == 0) != (report['result'] == 'success'):
        raise ValueError('build result does not match exit code')
    counts = report.get('category_counts')
    if not isinstance(counts, dict) or any(not isinstance(k, str) or not isinstance(v, int) or isinstance(v, bool) or v < 0 for k, v in counts.items()):
        raise ValueError('invalid category counts')
    if not isinstance(report.get('diagnostic_count'), int) or isinstance(report['diagnostic_count'], bool) or report['diagnostic_count'] < sum(counts.values()):
        raise ValueError('invalid diagnostic count')
    diagnostics = report.get('prioritized_diagnostics')
    if not isinstance(diagnostics, list):
        raise ValueError('invalid prioritized diagnostics')
    for item in diagnostics:
        if not isinstance(item, dict) or not isinstance(item.get('category'), str) or not isinstance(item.get('message'), str) or not isinstance(item.get('log_line'), int) or isinstance(item['log_line'], bool) or item['log_line'] < 1:
            raise ValueError('invalid prioritized diagnostic entry')
    return report


def fingerprint(item):
    # Line positions shift when unrelated build output changes; preserve the message.
    return (item['category'], item['message'].strip())


def compare(before, after):
    before, after = validate(before), validate(after)
    old = Counter(fingerprint(item) for item in before['prioritized_diagnostics'])
    new = Counter(fingerprint(item) for item in after['prioritized_diagnostics'])
    categories = sorted(set(before['category_counts']) | set(after['category_counts']))
    return {
        'schema_version': 1,
        'previous_result': before['result'],
        'current_result': after['result'],
        'previous_diagnostic_count': before['diagnostic_count'],
        'current_diagnostic_count': after['diagnostic_count'],
        'diagnostic_count_change': after['diagnostic_count'] - before['diagnostic_count'],
        'category_changes': {category: {'previous': before['category_counts'].get(category, 0), 'current': after['category_counts'].get(category, 0), 'change': after['category_counts'].get(category, 0) - before['category_counts'].get(category, 0)} for category in categories},
        'new_prioritized_diagnostics': [{'category': category, 'message': message} for category, message in sorted((new - old).elements())],
        'resolved_prioritized_diagnostics': [{'category': category, 'message': message} for category, message in sorted((old - new).elements())],
        'note': '個別エラーの比較対象は各レポートの優先診断（最大10件）のみです。総件数と分類別件数は全診断を集計します。',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('previous', type=Path)
    parser.add_argument('current', type=Path)
    parser.add_argument('--output', type=Path, help='Optional JSON comparison output')
    args = parser.parse_args()
    try:
        result = compare(json.loads(args.previous.read_text(encoding='utf-8')), json.loads(args.current.read_text(encoding='utf-8')))
        if args.output:
            from export_xcode_diagnostic_report import write_report
            write_report(args.output, result)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        parser.exit(2, f'Cannot compare reports: {exc}\n')
    print(f"Build: {result['previous_result']} -> {result['current_result']}")
    print(f"Diagnostics: {result['previous_diagnostic_count']} -> {result['current_diagnostic_count']} ({result['diagnostic_count_change']:+d})")
    for category, counts in result['category_changes'].items():
        if counts['change']:
            print(f"  {category}: {counts['previous']} -> {counts['current']} ({counts['change']:+d})")
    for label, key in [('New prioritized', 'new_prioritized_diagnostics'), ('Resolved prioritized', 'resolved_prioritized_diagnostics')]:
        print(f'{label}: {len(result[key])}')
        for item in result[key]:
            print(f"  [{item['category']}] {item['message']}")
    print(result['note'])
    if args.output:
        print(f'Comparison JSON: {args.output}')


if __name__ == '__main__':
    main()
