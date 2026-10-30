#!/usr/bin/env python3
"""Run bounded Swift syntax and triage regressions; emit offline JSON/HTML reports."""
import argparse
import datetime as dt
import html
import json
import subprocess
import sys
import time
import re
import uuid
from pathlib import Path


def execute(command, cwd, timeout):
    started = time.monotonic()
    try:
        proc = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return {'status': 'passed' if proc.returncode == 0 else 'failed', 'exit_code': proc.returncode,
                'stdout': proc.stdout[-12000:], 'stderr': proc.stderr[-12000:], 'duration_seconds': round(time.monotonic() - started, 3)}
    except subprocess.TimeoutExpired as exc:
        return {'status': 'timeout', 'exit_code': None, 'stdout': (exc.stdout or b'').decode('utf-8', 'replace')[-12000:] if isinstance(exc.stdout, bytes) else (exc.stdout or '')[-12000:],
                'stderr': (exc.stderr or b'').decode('utf-8', 'replace')[-12000:] if isinstance(exc.stderr, bytes) else (exc.stderr or '')[-12000:], 'duration_seconds': round(time.monotonic() - started, 3)}
    except OSError as exc:
        return {'status': 'error', 'exit_code': None, 'stdout': '', 'stderr': str(exc), 'duration_seconds': round(time.monotonic() - started, 3)}


def regression_counts(result):
    """Extract reliable per-test totals from the bounded runner summary."""
    combined = result.get('stdout', '') + '\n' + result.get('stderr', '')
    match = re.search(r'^Regression summary: (\d+) passed, (\d+) failed, (\d+) total$', combined, re.M)
    if not match:
        return None
    passed, failed, total = map(int, match.groups())
    if passed + failed != total:
        return None
    return {'passed': passed, 'failed': failed, 'total': total}


def compare_baseline(current, baseline):
    """Compare supported metrics without trusting arbitrary baseline structure."""
    if not isinstance(baseline, dict) or baseline.get('schema_version') != 1 or not isinstance(baseline.get('checks'), dict):
        raise ValueError('baseline must be a diagnostics JSON report (schema_version 1)')
    comparisons = {}
    for name, now in current['checks'].items():
        old = baseline['checks'].get(name)
        if not isinstance(old, dict) or old.get('status') not in ('passed', 'failed', 'timeout', 'error'):
            comparisons[name] = {'availability': 'missing'}
            continue
        entry = {'availability': 'available', 'previous_status': old['status'],
                 'current_status': now['status'],
                 'new_failure': old['status'] == 'passed' and now['status'] != 'passed'}
        a, b = now.get('duration_seconds'), old.get('duration_seconds')
        if all(isinstance(x, (int, float)) and not isinstance(x, bool) and 0 <= x < float('inf') for x in (a, b)):
            entry['duration_delta_seconds'] = round(a - b, 3)
        old_counts, new_counts = old.get('test_counts'), now.get('test_counts')
        if all(isinstance(x, dict) and isinstance(x.get('failed'), int) and not isinstance(x.get('failed'), bool) and x['failed'] >= 0 for x in (old_counts, new_counts)):
            entry['failed_delta'] = new_counts['failed'] - old_counts['failed']
        comparisons[name] = entry
    return comparisons


def history_files(directory):
    """Only archived diagnostics JSON; ignore temporary or unrelated files."""
    if not directory.exists():
        return []
    return sorted((p for p in directory.glob('diagnostics_*.json') if p.is_file()), reverse=True)


def latest_history(directory):
    """Return the newest valid report, skipping corrupted snapshots."""
    for path in history_files(directory):
        try:
            data = json.loads(path.read_text(encoding='utf-8'))
            if isinstance(data, dict) and data.get('schema_version') == 1 and isinstance(data.get('checks'), dict):
                return path, data
        except (OSError, ValueError, TypeError):
            continue
    return None, None


def archive_report(directory, report, keep=30):
    """Write a unique atomic history snapshot; retain only the newest keep files."""
    if keep < 1:
        raise ValueError('history retention must be positive')
    directory.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    target = directory / f'diagnostics_{stamp}_{uuid.uuid4().hex[:12]}.json'
    temporary = target.with_name(target.name + '.tmp')
    try:
        temporary.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    for obsolete in history_files(directory)[keep:]:
        obsolete.unlink()
    return target


def render_comparison(report, name):
    entry = report.get('baseline_comparison', {}).get(name)
    if not entry:
        return ''
    if entry['availability'] == 'missing':
        return '<p>前回比較: 対応する検査データなし</p>'
    old = html.escape(entry['previous_status'])
    current = html.escape(entry['current_status'])
    change = ' <strong>新たな失敗</strong>' if entry['new_failure'] else ''
    result = f'<p>前回比較: {old} → {current}{change}</p>'
    if 'duration_delta_seconds' in entry:
        result += f'<p>実行時間の変化: {entry["duration_delta_seconds"]:+.2f}秒</p>'
    if 'failed_delta' in entry:
        result += f'<p>失敗件数の変化: {entry["failed_delta"]:+d}件</p>'
    return result

def render(report):
    cards = []
    for name, result in report['checks'].items():
        label = 'Swift構文解析' if name == 'swift_syntax' else '競合画面の回帰テスト'
        status = result['status']
        log = html.escape((result['stdout'] + '\n' + result['stderr']).strip())
        duration = result.get('duration_seconds')
        duration_label = f'{duration:.2f}秒' if isinstance(duration, (int, float)) and duration >= 0 else '計測なし'
        counts = result.get('test_counts')
        counts_label = (f'<p>テスト: {counts["total"]}件 / 成功 {counts["passed"]}件 / 失敗 {counts["failed"]}件</p>' if counts else '')
        cards.append(f'<section><h2>{label}</h2><p class="{status}">{html.escape(status)}</p><p>実行時間: {duration_label}</p>{counts_label}{render_comparison(report, name)}<details><summary>実行ログ</summary><pre>{log}</pre></details></section>')
    overall = html.escape(report['overall_status'])
    return ('<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>HOTEL SHIFT 診断結果</title><style>body{font:16px system-ui,sans-serif;max-width:920px;margin:2rem auto;padding:0 1rem;background:#f6f7fa;color:#202637}'
            'section{background:white;padding:1.2rem;margin:1rem 0;border-radius:12px;box-shadow:0 1px 5px #0001}'
            '.passed{color:#087a45}.failed,.timeout,.error{color:#b3261e}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f1f3f6;padding:1rem;border-radius:8px}'
            '</style><h1>HOTEL SHIFT 診断結果</h1><p>総合結果: <strong>' + overall + '</strong></p>'
            '<p>Swiftの構文解析はiOS SDKを使ったXcodeビルドではありません。</p><p>失敗時は実行ログを開き、原因を確認してください。</p>' + ''.join(cards) + '</html>')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--recent', type=int, default=5)
    parser.add_argument('--swift-timeout', type=float, default=15)
    parser.add_argument('--regression-timeout', type=float, default=180)
    parser.add_argument('--per-test-timeout', type=int, default=45)
    parser.add_argument('--baseline-json', type=Path, help='Explicit previous diagnostics JSON (overrides automatic history comparison)')
    parser.add_argument('--history-dir', type=Path, default=Path('reports/diagnostics_history'), help='Directory for automatic historical snapshots')
    parser.add_argument('--history-keep', type=int, default=30, help='Maximum archived reports to retain')
    parser.add_argument('--no-history', action='store_true', help='Disable automatic history and automatic comparison')
    parser.add_argument('--history-html', type=Path, default=Path('reports/diagnostics_history.html'), help='Offline dashboard for archived diagnostics')
    parser.add_argument('--output-json', type=Path, default=Path('reports/diagnostics.json'))
    parser.add_argument('--output-html', type=Path, default=Path('reports/diagnostics.html'))
    args = parser.parse_args(argv)
    if args.recent < 1 or args.swift_timeout <= 0 or args.regression_timeout <= 0 or args.per_test_timeout <= 0 or args.history_keep < 1:
        parser.error('recent and timeouts must be positive')
    root = args.root.resolve()
    checks = {
        'swift_syntax': execute([sys.executable, 'Tests/check_swift_syntax.py', '--timeout', str(args.swift_timeout)], root, args.swift_timeout * 30),
        'triage_regression': execute(['bash', 'Tests/run_triage_editor_regression.sh', '--recent', str(args.recent), '--timeout', str(args.per_test_timeout)], root, args.regression_timeout),
    }
    checks['triage_regression']['test_counts'] = regression_counts(checks['triage_regression'])
    report = {'schema_version': 1, 'generated_at_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'recent_versions': args.recent, 'overall_status': 'passed' if all(c['status'] == 'passed' for c in checks.values()) else 'failed', 'checks': checks,
              'note': 'Swift syntax parsing is not an Xcode/iOS build.'}
    history_dir = args.history_dir if args.history_dir.is_absolute() else root / args.history_dir
    if args.baseline_json:
        baseline_path = args.baseline_json if args.baseline_json.is_absolute() else root / args.baseline_json
        try:
            baseline = json.loads(baseline_path.read_text(encoding='utf-8'))
            report['baseline_comparison'] = compare_baseline(report, baseline)
            report['baseline_source'] = str(args.baseline_json)
        except (OSError, ValueError, TypeError) as exc:
            parser.error(f'cannot read baseline: {exc}')
    elif not args.no_history:
        previous_path, previous = latest_history(history_dir)
        if previous is not None:
            report['baseline_comparison'] = compare_baseline(report, previous)
            report['baseline_source'] = str(previous_path)

    for path, content in ((args.output_json, json.dumps(report, ensure_ascii=False, indent=2) + '\n'), (args.output_html, render(report))):
        target = path if path.is_absolute() else root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(target.name + '.tmp')
        temporary.write_text(content, encoding='utf-8')
        temporary.replace(target)
    if not args.no_history:
        try:
            snapshot = archive_report(history_dir, report, args.history_keep)
            print(f"History snapshot: {snapshot}")
            from render_diagnostics_history import write as write_history_dashboard
            dashboard = args.history_html if args.history_html.is_absolute() else root / args.history_html
            write_history_dashboard(history_dir, dashboard)
            print(f"History dashboard: {dashboard}")
        except OSError as exc:
            parser.error(f'cannot save history: {exc}')
    print(f"Combined diagnostics: {report['overall_status']} (Swift: {checks['swift_syntax']['status']}, regression: {checks['triage_regression']['status']})")
    return 0 if report['overall_status'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())
