#!/usr/bin/env python3
"""Find recurring prioritized build errors across archived diagnostic reports."""
import argparse
import html
import json
import re
from collections import Counter
from pathlib import Path

FILE_RE = re.compile(r'^build-\d{8}T\d{12}Z\.json$')
LOCATION_RE = re.compile(r':\d+(?::\d+)?(?=:\s*(?:error|warning):)', re.I)

def fingerprint(entry):
    category = entry.get('category')
    message = entry.get('message')
    if not isinstance(category, str) or not category or not isinstance(message, str) or not message.strip():
        raise ValueError('invalid diagnostic entry')
    # Ignore changing line/column positions while retaining the actual error text.
    normalized = LOCATION_RE.sub(':<line>', message.strip())
    return category, normalized

def analyze(directory: Path, *, last=10, minimum=2):
    if last < 1 or minimum < 2:
        raise ValueError('invalid analysis limits')
    index = json.loads((directory/'index.json').read_text(encoding='utf-8'))
    if not isinstance(index, dict) or index.get('schema_version') != 1 or not isinstance(index.get('builds'), list):
        raise ValueError('invalid history index')
    names = []
    for item in index['builds']:
        if not isinstance(item, dict) or not isinstance(item.get('file'), str) or not FILE_RE.fullmatch(item['file']):
            raise ValueError('invalid history filename')
        names.append(item['file'])
    if len(set(names)) != len(names):
        raise ValueError('duplicate history filename')
    selected = sorted(names)[-last:]
    occurrence = Counter()
    streak = Counter()
    samples = {}
    for name in selected:
        report = json.loads((directory/name).read_text(encoding='utf-8'))
        if not isinstance(report, dict) or report.get('schema_version') != 1 or report.get('result') not in ('success','failure'):
            raise ValueError('invalid archived report')
        diagnostics = report.get('prioritized_diagnostics', [])
        if not isinstance(diagnostics, list):
            raise ValueError('invalid diagnostics')
        keys = set()
        for entry in diagnostics:
            if not isinstance(entry, dict):
                raise ValueError('invalid diagnostic entry')
            key = fingerprint(entry)
            keys.add(key)
            samples[key] = entry.get('suggested_check', '')
        for key in keys:
            occurrence[key] += 1
        for key in list(streak):
            if key not in keys:
                streak[key] = 0
        for key in keys:
            streak[key] += 1
    recurring = [{'category':key[0], 'message':key[1], 'builds':occurrence[key], 'consecutive_latest':streak[key], 'suggested_check':samples[key] if isinstance(samples[key],str) else ''}
                 for key in occurrence if occurrence[key] >= minimum]
    recurring.sort(key=lambda r:(-r['consecutive_latest'], -r['builds'], r['category'], r['message']))
    return {'schema_version':1, 'analyzed_builds':len(selected), 'scope':'prioritized_diagnostics (maximum 10 per build)', 'recurring':recurring}

def render(report):
    rows = ''.join('<tr>'+''.join(f'<td>{html.escape(str(v))}</td>' for v in (r['category'],r['message'],r['builds'],r['consecutive_latest'],r['suggested_check']))+'</tr>' for r in report['recurring'])
    if not rows:
        rows='<tr><td colspan="5">繰り返し発生した優先診断はありません</td></tr>'
    return f'''<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>HOTEL SHIFT 継続エラー</title><style>body{{font-family:-apple-system,sans-serif;max-width:1100px;margin:2rem auto;padding:0 1rem;color:#172033}}table{{border-collapse:collapse;width:100%}}th,td{{text-align:left;padding:.7rem;border-bottom:1px solid #ddd;overflow-wrap:anywhere}}.muted{{color:#64748b}}</style></head><body><h1>継続しているビルド診断</h1><p>分析した履歴：{report['analyzed_builds']} 件</p><table><thead><tr><th>分類</th><th>診断</th><th>出現回数</th><th>直近連続回数</th><th>確認事項</th></tr></thead><tbody>{rows}</tbody></table><p class="muted">各ビルドの優先診断上位10件のみを分析しています。出現しない診断が解消したとは限りません。</p></body></html>'''

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory',type=Path)
    parser.add_argument('--last',type=int,default=10)
    parser.add_argument('--minimum',type=int,default=2)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--html',type=Path,required=True)
    args=parser.parse_args()
    try:
        result=analyze(args.directory,last=args.last,minimum=args.minimum)
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.html.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        args.html.write_text(render(result),encoding='utf-8')
        print(f"Persistent diagnostics: {len(result['recurring'])} ({result['analyzed_builds']} builds)")
    except (OSError,ValueError,TypeError) as exc:
        parser.exit(2,f'Cannot analyze diagnostic history: {exc}\n')

if __name__=='__main__':
    main()
