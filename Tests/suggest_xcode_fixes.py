#!/usr/bin/env python3
"""Provide conservative, actionable follow-ups for classified Xcode errors."""
import sys
from pathlib import Path
from classify_xcode_diagnostics import classify

ADVICE = {
    'Swiftコンパイル': 'XcodeのIssue Navigatorで最初のSwiftエラーを開き、ファイル名・行番号と型/スコープを確認してください。後続エラーは連鎖している場合があります。',
    'ファイル参照': 'XcodeのProject NavigatorとBuild Phases > Compile Sourcesを確認し、欠落ファイルのパスまたは参照を修正してください。',
    '署名・プロビジョニング': '実機ビルドの場合はSigning & CapabilitiesのTeamとBundle Identifierを確認してください。シミュレータービルドではCODE_SIGNING_ALLOWED=NOを確認してください。',
    'プロジェクト設定・スキーム': 'Xcodeでプロジェクトを開き、Product > Scheme > Manage Schemesとビルド先、使用するXcode/SDKを確認してください。',
    '依存関係・モジュール': 'XcodeのFile > Packages > Resolve Package Versionsを試し、Package Dependenciesとネットワーク/ローカルパッケージの参照を確認してください。',
    'その他のエラー': '該当ログの前後を確認し、最初に発生したエラーを優先して調査してください。',
}

def suggestions(log):
    categories = []
    for line in log.splitlines():
        category = classify(line)
        if category and category not in categories:
            categories.append(category)
    if not categories:
        return '具体的なエラーが分類できません。ビルドログ末尾と最初の失敗箇所を確認してください。'
    return '\n'.join(f'[{category}] {ADVICE[category]}' for category in categories)

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('Usage: suggest_xcode_fixes.py <build-log>', file=sys.stderr)
        sys.exit(2)
    try:
        print(suggestions(Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace')))
    except OSError as exc:
        print(f'Cannot read build log: {exc}', file=sys.stderr)
        sys.exit(2)
