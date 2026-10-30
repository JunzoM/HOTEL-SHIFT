#!/usr/bin/env python3
"""Rank unique Xcode build diagnostics by likely repair order, preserving evidence."""
import sys
from pathlib import Path
from classify_xcode_diagnostics import classify
from suggest_xcode_fixes import ADVICE

# Missing project inputs/dependencies often cause downstream compiler errors.
PRIORITY = {
    'ファイル参照': 0,
    'プロジェクト設定・スキーム': 1,
    '依存関係・モジュール': 2,
    'Swiftコンパイル': 3,
    '署名・プロビジョニング': 4,
    'その他のエラー': 5,
}

def ranked_diagnostics(log, limit=3):
    """Return (category, first_log_line_number, diagnostic) in stable priority order."""
    if limit < 0:
        raise ValueError('limit must not be negative')
    found = []
    seen = set()
    for number, raw in enumerate(log.splitlines(), 1):
        category = classify(raw)
        if category is None:
            continue
        line = raw.strip()
        key = (category, line)
        if key in seen:
            continue
        seen.add(key)
        found.append((category, number, line))
    found.sort(key=lambda item: (PRIORITY[item[0]], item[1]))
    return found[:limit]

def report(log, limit=3):
    ranked = ranked_diagnostics(log, limit)
    if not ranked:
        return '優先順位を付けられるエラーがありません。ビルドログを確認してください。'
    lines = ['推奨確認順（原因の推定であり、確定診断ではありません）:']
    for index, (category, number, diagnostic) in enumerate(ranked, 1):
        lines.append(f'{index}. [{category}] ログ{number}行目: {diagnostic}')
        lines.append(f'   確認: {ADVICE[category]}')
    return '\n'.join(lines)

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('Usage: prioritize_xcode_diagnostics.py <build-log>', file=sys.stderr)
        sys.exit(2)
    try:
        print(report(Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace')))
    except OSError as exc:
        print(f'Cannot read build log: {exc}', file=sys.stderr)
        sys.exit(2)
