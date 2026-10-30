#!/usr/bin/env python3
"""Render an offline, dependency-free build diagnostic trend from the history index."""
import argparse
import html
import json
import re
from pathlib import Path

NAME = re.compile(r'^build-\d{8}T\d{12}Z\.json$')


def load_history(index_path: Path):
    index = json.loads(index_path.read_text(encoding='utf-8'))
    if not isinstance(index, dict) or index.get('schema_version') != 1 or not isinstance(index.get('builds'), list):
        raise ValueError('invalid history index')
    records = []
    seen = set()
    for item in index['builds']:
        if not isinstance(item, dict):
            raise ValueError('invalid history entry')
        filename, result, count = item.get('file'), item.get('result'), item.get('diagnostic_count')
        if not isinstance(filename, str) or not NAME.fullmatch(filename) or filename in seen:
            raise ValueError('invalid or duplicate history filename')
        if result not in ('success', 'failure') or type(count) is not int or count < 0:
            raise ValueError('invalid build result or diagnostic count')
        seen.add(filename)
        records.append({'file': filename, 'result': result, 'count': count})
    return sorted(records, key=lambda r: r['file'])


def render(records):
    width, height, left, right, top, bottom = 900, 300, 55, 25, 25, 48
    max_count = max((r['count'] for r in records), default=0)
    ceiling = max(max_count, 1)
    usable_w, usable_h = width - left - right, height - top - bottom
    coords = []
    for i, record in enumerate(records):
        x = left + usable_w * (i / max(len(records)-1, 1))
        y = top + usable_h * (1 - record['count'] / ceiling)
        coords.append((x, y))
    parts = [f'<line x1="{left}" y1="{top}" x2="{left}" y2="{height-bottom}" stroke="#94a3b8"/>',
             f'<line x1="{left}" y1="{height-bottom}" x2="{width-right}" y2="{height-bottom}" stroke="#94a3b8"/>',
             f'<text x="8" y="{top+5}" fill="#475569">{ceiling}</text>',
             f'<text x="26" y="{height-bottom+5}" fill="#475569">0</text>']
    if coords:
        points = ' '.join(f'{x:.1f},{y:.1f}' for x,y in coords)
        parts.append(f'<polyline points="{points}" fill="none" stroke="#2563eb" stroke-width="3"/>')
    for (x,y), record in zip(coords, records):
        color = '#16a34a' if record['result'] == 'success' else '#dc2626'
        label = html.escape(f"{record['file']} | {record['count']} errors | {record['result']}", quote=True)
        parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="5" fill="{color}"><title>{label}</title></circle>')
    rows = ''.join('<tr><td>'+html.escape(r['file'])+'</td><td>'+('成功' if r['result']=='success' else '失敗')+'</td><td>'+str(r['count'])+'</td></tr>' for r in records)
    if not rows:
        rows = '<tr><td colspan="3">ビルド履歴がありません</td></tr>'
    last = records[-1]['count'] if records else None
    change = last - records[-2]['count'] if len(records)>1 else None
    change_text = '比較対象なし' if change is None else f'{change:+d} 件（直前比）'
    return f'''<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>HOTEL SHIFT ビルド診断履歴</title><style>body{{font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;margin:2rem auto;padding:0 1rem;max-width:1000px;color:#172033}}svg{{width:100%;height:auto;background:#f8fafc;border-radius:12px}}table{{border-collapse:collapse;width:100%}}td,th{{padding:.65rem;border-bottom:1px solid #ddd;text-align:left}}.muted{{color:#64748b}}</style></head><body><h1>ビルド診断の推移</h1><p>記録数：{len(records)} 件 ／ 最新のエラー数：{last if last is not None else '—'} ／ 増減：{change_text}</p><svg viewBox="0 0 {width} {height}" role="img" aria-label="ビルドごとの診断エラー件数の推移">{''.join(parts)}</svg><p class="muted">緑：ビルド成功 ／ 赤：ビルド失敗。点にカーソルを合わせると詳細が表示されます。</p><h2>履歴一覧</h2><table><thead><tr><th>ビルド記録</th><th>結果</th><th>エラー数</th></tr></thead><tbody>{rows}</tbody></table><p class="muted">記録された診断件数の推移です。実際のビルド実行やエラー原因の確定を行うものではありません。</p></body></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('index', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        records = load_history(args.index)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(render(records), encoding='utf-8')
        print(f'History trend: {args.output} ({len(records)} builds)')
    except (OSError, ValueError, TypeError) as exc:
        parser.exit(2, f'Cannot render history trend: {exc}\n')

if __name__ == '__main__':
    main()
