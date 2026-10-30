#!/usr/bin/env python3
"""Classify actionable Xcode build diagnostics without changing build status."""
import re
import sys
from pathlib import Path

RULES = [
    ('Swiftコンパイル', re.compile(r'\.swift:\d+(?::\d+)?:\s*(?:error:|fatal error:)|\b(?:No such module|cannot find .* in scope|type .* has no member)\b', re.I)),
    ('ファイル参照', re.compile(r'Build input file cannot be found|No such file or directory|Unable to load contents of file list|file .* does not exist', re.I)),
    ('署名・プロビジョニング', re.compile(r'Signing for |Provisioning profile|No signing certificate|requires a development team', re.I)),
    ('プロジェクト設定・スキーム', re.compile(r'does not contain a scheme|Unable to find a destination|unknown build action|Unable to open project|The project .* is damaged|SDK .* cannot be located', re.I)),
    ('依存関係・モジュール', re.compile(r'package resolution failed|Failed to resolve package|Could not resolve package dependencies|missing package product', re.I)),
]

def classify(line):
    for category, pattern in RULES:
        if pattern.search(line):
            return category
    if re.search(r'\b(?:error:|fatal error:)\b', line, re.I) or 'error:' in line.lower():
        return 'その他のエラー'
    return None

def report(log, limit=40):
    groups = {}
    for line in log.splitlines():
        category = classify(line)
        if category:
            groups.setdefault(category, [])
            if line not in groups[category]:
                groups[category].append(line.strip())
    if not groups:
        return '分類できるエラーがありません。ビルドログ末尾を確認してください。'
    output = []
    for category, lines in groups.items():
        output.append(f'[{category}] {len(lines)}件')
        output.extend(f'  {line}' for line in lines[:limit])
        if len(lines) > limit:
            output.append(f'  ...ほか{len(lines)-limit}件')
    return '\n'.join(output)

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('Usage: classify_xcode_diagnostics.py <build-log>', file=sys.stderr)
        sys.exit(2)
    path = Path(sys.argv[1])
    try:
        print(report(path.read_text(encoding='utf-8', errors='replace')))
    except OSError as exc:
        print(f'Cannot read build log: {exc}', file=sys.stderr)
        sys.exit(2)
