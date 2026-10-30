#!/usr/bin/env python3
"""Create actionable triage status from recurring Xcode diagnostics."""
import argparse
import html
import json
from pathlib import Path

CATEGORY_ORDER = {'ファイル参照': 0, 'プロジェクト設定': 1, '依存関係': 2, 'Swiftコンパイル': 3, '署名・プロビジョニング': 4}

def triage(report):
    if not isinstance(report, dict) or report.get('schema_version') != 1 or not isinstance(report.get('recurring'), list):
        raise ValueError('invalid recurring diagnostics report')
    rows = []
    for entry in report['recurring']:
        if not isinstance(entry, dict) or not isinstance(entry.get('category'), str) or not isinstance(entry.get('message'), str):
            raise ValueError('invalid recurring entry')
        builds, consecutive = entry.get('builds'), entry.get('consecutive_latest')
        if type(builds) is not int or type(consecutive) is not int or builds < 2 or not 0 <= consecutive <= builds:
            raise ValueError('invalid recurring counters')
        active = consecutive > 0
        # Resolved is deliberately not inferred from absence in a truncated top-10 diagnostic set.
        priority = '高' if active and consecutive >= 3 else '中' if active else '要確認'
        rows.append({'category': entry['category'], 'message': entry['message'], 'builds': builds,
                     'consecutive_latest': consecutive, 'status': '継続中' if active else '最新履歴では未検出',
                     'priority': priority, 'suggested_check': entry.get('suggested_check', '') if isinstance(entry.get('suggested_check', ''), str) else ''})
    ranks = {'高': 0, '中': 1, '要確認': 2}
    rows.sort(key=lambda r: (ranks[r['priority']], CATEGORY_ORDER.get(r['category'], 9), -r['consecutive_latest'], -r['builds'], r['message']))
    return {'schema_version': 1, 'scope': report.get('scope', ''), 'analyzed_builds': report.get('analyzed_builds', 0), 'items': rows,
            'counts': {name: sum(row['priority'] == name for row in rows) for name in ('高', '中', '要確認')}}

def render(report):
    rows = ''.join('<tr>' + ''.join(f'<td>{html.escape(str(row[field]))}</td>' for field in ('priority', 'status', 'category', 'message', 'consecutive_latest', 'builds', 'suggested_check')) + '</tr>' for row in report['items'])
    if not rows:
        rows = '<tr><td colspan="7">対応候補はありません</td></tr>'
    return '<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>HOTEL SHIFT エラー対応優先度</title><style>body{{font-family:-apple-system,sans-serif;max-width:1200px;margin:2rem auto;padding:0 1rem;color:#172033}}table{{border-collapse:collapse;width:100%}}th,td{{text-align:left;padding:.65rem;border-bottom:1px solid #ddd;overflow-wrap:anywhere}}.muted{{color:#64748b}}</style></head><body><h1>継続エラーの対応優先度</h1><p>高: {high}件 / 中: {medium}件 / 要確認: {review}件</p><table><thead><tr><th>優先度</th><th>状態</th><th>分類</th><th>診断</th><th>連続回数</th><th>出現回数</th><th>確認事項</th></tr></thead><tbody>{rows}</tbody></table><p class="muted">各ビルドの優先診断上位10件のみが対象です。未検出は解消を意味しません。対応状況は推定であり、実際の修正完了を記録するものではありません。</p></body></html>'.format(high=report['counts']['高'], medium=report['counts']['中'], review=report['counts']['要確認'], rows=rows)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('input', type=Path)
    p.add_argument('--output', required=True, type=Path)
    p.add_argument('--html', required=True, type=Path)
    a = p.parse_args()
    try:
        report = triage(json.loads(a.input.read_text(encoding='utf-8')))
        a.output.parent.mkdir(parents=True, exist_ok=True)
        a.html.parent.mkdir(parents=True, exist_ok=True)
        a.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        a.html.write_text(render(report), encoding='utf-8')
        print('Triage:', len(report['items']), 'items')
    except (OSError, ValueError, TypeError) as exc:
        p.exit(2, f'Cannot triage diagnostics: {exc}\n')

if __name__ == '__main__':
    main()
