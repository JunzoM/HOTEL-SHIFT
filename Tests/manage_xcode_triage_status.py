#!/usr/bin/env python3
"""Persist manual triage statuses separately from generated diagnostics."""
import argparse
import hashlib
import html
import json
from pathlib import Path

STATUSES = ('未対応', '対応中', '修正済み')

def issue_id(item):
    key = json.dumps([item['category'], item['message']], ensure_ascii=False, separators=(',', ':'))
    return hashlib.sha256(key.encode('utf-8')).hexdigest()[:20]

def load_json_strict(path):
    # Reject ambiguous duplicate keys rather than silently applying the last value.
    def unique_pairs(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('duplicate JSON key: ' + key)
            result[key] = value
        return result
    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique_pairs)

def validate_manual(data):
    if not isinstance(data, dict) or data.get('schema_version') != 1 or not isinstance(data.get('statuses'), dict):
        raise ValueError('invalid manual status file')
    if set(data) - {'schema_version', 'statuses', 'base_statuses'}:
        raise ValueError('unexpected manual status fields')
    if 'base_statuses' in data:
        if not isinstance(data['base_statuses'], dict) or set(data['base_statuses']) != set(data['statuses']):
            raise ValueError('invalid baseline statuses')
        if any(not isinstance(v, str) or v not in STATUSES for v in data['base_statuses'].values()):
            raise ValueError('invalid baseline status entry')
    for key, value in data['statuses'].items():
        if not isinstance(key, str) or not isinstance(value, str) or value not in STATUSES:
            raise ValueError('invalid manual status entry')
    return data

def combine(triage, manual):
    if not isinstance(triage, dict) or not isinstance(triage.get('items'), list):
        raise ValueError('invalid triage report')
    validate_manual(manual)
    items = []
    for item in triage['items']:
        if not isinstance(item, dict) or not all(isinstance(item.get(k), str) for k in ('category','message')):
            raise ValueError('invalid triage item')
        row = dict(item)
        row['issue_id'] = issue_id(item)
        row['manual_status'] = manual['statuses'].get(row['issue_id'], '未対応')
        items.append(row)
    return {'schema_version': 1, 'items': items, 'manual_statuses_count': len(manual['statuses'])}

def render(result):
    rows = ''.join('<tr>' + ''.join('<td>' + html.escape(str(row.get(k, ''))) + '</td>' for k in ('priority','manual_status','status','category','message','issue_id','suggested_check')) + '</tr>' for row in result['items'])
    if not rows:
        rows = '<tr><td colspan="7">診断対象なし</td></tr>'
    return ('<!doctype html><html lang="ja"><head><meta charset="utf-8"><title>HOTEL SHIFT 対応管理</title>'
            '<style>body{font-family:-apple-system,sans-serif;max-width:1200px;margin:2rem auto;padding:1rem}'
            'table{border-collapse:collapse;width:100%}td,th{padding:.6rem;border-bottom:1px solid #ddd;text-align:left;overflow-wrap:anywhere}</style>'
            '</head><body><h1>ビルドエラー対応状況</h1><p>対応状況は手動記録です。修正済みでもビルド成功を保証しません。</p>'
            '<table><thead><tr><th>優先度</th><th>手動対応状況</th><th>検出状況</th><th>分類</th><th>エラー</th><th>識別ID</th><th>確認事項</th></tr></thead><tbody>' + rows + '</tbody></table></body></html>')

def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + '.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temp.replace(path)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('triage', type=Path)
    p.add_argument('--statuses', type=Path, required=True)
    p.add_argument('--import-statuses', type=Path, help='JSON downloaded from the offline HTML editor')
    p.add_argument('--conflicts-json', type=Path, help='Write a detailed report if stale imported edits conflict')
    p.add_argument('--conflicts-html', type=Path, help='Write a readable HTML report for stale import conflicts')
    p.add_argument('--set-id', help='Issue ID to update (listed in report)')
    p.add_argument('--status', choices=STATUSES)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--html', type=Path, required=True)
    a = p.parse_args()
    try:
        if (a.conflicts_json or a.conflicts_html) and not a.import_statuses:
            raise ValueError('conflict reports require --import-statuses')
        if bool(a.set_id) != bool(a.status):
            raise ValueError('--set-id and --status must be provided together')
        triage = load_json_strict(a.triage)
        manual = validate_manual(load_json_strict(a.statuses)) if a.statuses.exists() else {'schema_version': 1, 'statuses': {}}
        # Validate the entire current report before making any persistent changes.
        combine(triage, manual)
        if a.import_statuses:
            if a.set_id or a.status:
                raise ValueError('--import-statuses cannot be combined with --set-id or --status')
            imported = validate_manual(load_json_strict(a.import_statuses))
            allowed_ids = {issue_id(item) for item in triage['items']}
            if not set(imported['statuses']).issubset(allowed_ids):
                raise ValueError('import contains issue IDs not in the current report')
            # FIXED385: refuse stale editor exports if the same issue was edited
            # since the HTML was generated; leave unrelated newer edits intact.
            baseline = imported.get('base_statuses')
            if baseline is not None:
                conflicts = []
                by_id = {issue_id(item): item for item in triage['items']}
                for key, new_status in imported['statuses'].items():
                    old_status = baseline[key]
                    current_status = manual['statuses'].get(key, '未対応')
                    if new_status != old_status and current_status != old_status and current_status != new_status:
                        item = by_id[key]
                        conflicts.append({'issue_id': key, 'category': item['category'],
                                          'message': item['message'], 'baseline_status': old_status,
                                          'current_status': current_status, 'imported_status': new_status})
                if conflicts:
                    report = {'schema_version': 1, 'conflict_count': len(conflicts),
                              'conflicts': conflicts,
                              'resolution': 'Reopen the latest triage editor, review these issues, and export again.'}
                    if a.conflicts_json:
                        write_json(a.conflicts_json, report)
                    if a.conflicts_html:
                        from render_xcode_import_conflicts import render as render_conflicts
                        a.conflicts_html.parent.mkdir(parents=True, exist_ok=True)
                        tmp = a.conflicts_html.with_name(a.conflicts_html.name + '.tmp')
                        tmp.write_text(render_conflicts(report), encoding='utf-8')
                        tmp.replace(a.conflicts_html)
                    raise ValueError(f'stale status conflicts ({len(conflicts)} issues): ' + ', '.join(x['issue_id'] for x in conflicts))
            if baseline is None:
                manual['statuses'].update(imported['statuses'])
            else:
                manual['statuses'].update({key: value for key, value in imported['statuses'].items()
                                           if value != baseline[key]})
            write_json(a.statuses, manual)
        result = combine(triage, manual)
        if a.set_id:
            if a.set_id not in {item['issue_id'] for item in result['items']}:
                raise ValueError('issue ID is not present in the current triage report')
            manual['statuses'][a.set_id] = a.status
            result = combine(triage, manual)
            write_json(a.statuses, manual)
        write_json(a.output, result)
        a.html.parent.mkdir(parents=True, exist_ok=True)
        a.html.write_text(render(result), encoding='utf-8')
        print('Triage statuses:', len(result['items']), 'items')
    except (OSError, ValueError, TypeError) as exc:
        p.exit(2, f'Cannot manage triage statuses: {exc}\n')

if __name__ == '__main__':
    main()
