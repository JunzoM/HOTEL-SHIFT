#!/usr/bin/env python3
"""Render a FIXED368 comparison JSON as a standalone, escaped HTML report."""
import argparse
import html
import json
from pathlib import Path


def validate_comparison(data):
    if not isinstance(data, dict) or data.get('schema_version') != 1:
        raise ValueError('unsupported comparison schema')
    for key in ('previous_result', 'current_result'):
        if data.get(key) not in ('success', 'failure'):
            raise ValueError(f'invalid {key}')
    for key in ('previous_diagnostic_count', 'current_diagnostic_count', 'diagnostic_count_change'):
        value = data.get(key)
        if type(value) is not int or (key != 'diagnostic_count_change' and value < 0):
            raise ValueError(f'invalid {key}')
    if data['current_diagnostic_count'] - data['previous_diagnostic_count'] != data['diagnostic_count_change']:
        raise ValueError('inconsistent diagnostic count change')
    changes = data.get('category_changes')
    if not isinstance(changes, dict):
        raise ValueError('invalid category changes')
    for category, counts in changes.items():
        if not isinstance(category, str) or not isinstance(counts, dict):
            raise ValueError('invalid category entry')
        if any(type(counts.get(k)) is not int for k in ('previous', 'current', 'change')):
            raise ValueError('invalid category count')
        if min(counts['previous'], counts['current']) < 0 or counts['current'] - counts['previous'] != counts['change']:
            raise ValueError('inconsistent category count')
    for key in ('new_prioritized_diagnostics', 'resolved_prioritized_diagnostics'):
        items = data.get(key)
        if not isinstance(items, list) or any(not isinstance(x, dict) or not isinstance(x.get('category'), str) or not isinstance(x.get('message'), str) for x in items):
            raise ValueError(f'invalid {key}')
    if not isinstance(data.get('note'), str):
        raise ValueError('invalid note')
    return data


def render(data):
    data = validate_comparison(data)
    esc = lambda value: html.escape(str(value), quote=True)
    rows = ''.join(f'<tr><th scope="row">{esc(name)}</th><td>{counts["previous"]}</td><td>{counts["current"]}</td><td>{counts["change"]:+d}</td></tr>' for name, counts in sorted(data['category_changes'].items()))
    def diagnostics(key):
        items = data[key]
        if not items:
            return '<p class="empty">該当なし</p>'
        return '<ul>' + ''.join(f'<li><strong>{esc(item["category"])}</strong><span>{esc(item["message"])}</span></li>' for item in items) + '</ul>'
    old, new = esc(data['previous_result']), esc(data['current_result'])
    return f'''<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>HOTEL SHIFT ビルド診断比較</title>
<style>
:root{{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}}
body{{max-width:960px;margin:32px auto;padding:0 20px;line-height:1.6}}
h1{{font-size:1.7rem}}h2{{margin-top:2rem;font-size:1.2rem}}.summary{{display:flex;gap:12px;flex-wrap:wrap}}
.metric{{border:1px solid #8886;border-radius:12px;padding:14px 18px;min-width:180px;flex:1}}
.metric strong{{display:block;font-size:1.35rem}}table{{border-collapse:collapse;width:100%}}th,td{{padding:9px;text-align:left;border-bottom:1px solid #8885}}
li{{margin:10px 0;overflow-wrap:anywhere}}li strong{{display:inline-block;margin-right:12px}}li span{{white-space:pre-wrap}}
.note{{font-size:.9rem;opacity:.8}}.empty{{opacity:.7}}
</style></head><body>
<main><h1>HOTEL SHIFT ビルド診断比較</h1>
<section class="summary" aria-label="比較概要">
<div class="metric">ビルド結果<strong>{old} → {new}</strong></div>
<div class="metric">診断件数<strong>{data['previous_diagnostic_count']} → {data['current_diagnostic_count']}</strong>増減 {data['diagnostic_count_change']:+d}</div>
</section>
<h2>種類別の増減</h2><table><thead><tr><th scope="col">分類</th><th scope="col">前回</th><th scope="col">今回</th><th scope="col">増減</th></tr></thead><tbody>{rows or '<tr><td colspan="4">診断なし</td></tr>'}</tbody></table>
<h2>新しく発生した優先診断（{len(data['new_prioritized_diagnostics'])}件）</h2>{diagnostics('new_prioritized_diagnostics')}
<h2>解消した優先診断（{len(data['resolved_prioritized_diagnostics'])}件）</h2>{diagnostics('resolved_prioritized_diagnostics')}
<p class="note">{esc(data['note'])}</p>
</main></body></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('comparison', type=Path, help='FIXED368 comparison JSON')
    parser.add_argument('--output', type=Path, required=True, help='HTML output path')
    args = parser.parse_args()
    try:
        content = render(json.loads(args.comparison.read_text(encoding='utf-8')))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content, encoding='utf-8')
    except (OSError, ValueError) as exc:
        parser.exit(2, f'Cannot render comparison: {exc}\n')
    print(f'HTML comparison: {args.output}')


if __name__ == '__main__':
    main()
