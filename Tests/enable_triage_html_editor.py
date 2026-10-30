#!/usr/bin/env python3
"""Add an offline, browser-editable status selector and JSON download to triage HTML."""
import argparse
import html
import json
from pathlib import Path

SCRIPT = r'''<script>
(() => {
  const allowed = ['未対応', '対応中', '修正済み'];
  const selections = document.querySelectorAll('select[data-issue-id]');
  const button = document.getElementById('export-statuses');
  // FIXED385: retain the initial snapshot for stale-export conflict checks.
  const initialStatuses = {};
  for (const select of selections) initialStatuses[select.dataset.issueId] = select.value;
  const query = document.getElementById('filter-query');
  const category = document.getElementById('filter-category');
  const priority = document.getElementById('filter-priority');
  const status = document.getElementById('filter-status');
  const count = document.getElementById('visible-count');
  const sortMode = document.getElementById('sort-mode');
  const bulkStatus = document.getElementById('bulk-status');
  const bulkApply = document.getElementById('bulk-apply');
  const bulkMessage = document.getElementById('bulk-message');
  // FIXED382: bounded session-only undo/redo stacks for individual and bulk edits.
  const undoStack = [];
  const redoStack = [];
  const undoButton = document.getElementById('edit-undo');
  const redoButton = document.getElementById('edit-redo');
  function updateEditButtons() {
    undoButton.disabled = undoStack.length === 0;
    redoButton.disabled = redoStack.length === 0;
  }
  function commitEdit(kind, changes) {
    const changed = changes.filter(entry => entry.before !== entry.after);
    if (!changed.length) return false;
    undoStack.push({kind, changes: changed});
    if (undoStack.length > 100) undoStack.shift();
    redoStack.length = 0;
    recordChange(kind, changed);
    updateEditButtons();
    return true;
  }
  function applyEdit(edit, backwards) {
    for (const change of edit.changes) {
      const select = Array.from(selections).find(s => s.dataset.issueId === change.issue_id);
      if (select) select.value = backwards ? change.before : change.after;
    }
    recordChange(backwards ? '取り消し' : 'やり直し', edit.changes.map(c => ({issue_id:c.issue_id, before:backwards ? c.after : c.before, after:backwards ? c.before : c.after})));
    for (const select of selections) previousValues.set(select, select.value);
    updateFilters();
    updateEditButtons();
  }
  undoButton.addEventListener('click', () => {
    if (!undoStack.length) return;
    const edit = undoStack.pop();
    redoStack.push(edit);
    applyEdit(edit, true);
  });
  redoButton.addEventListener('click', () => {
    if (!redoStack.length) return;
    const edit = redoStack.pop();
    undoStack.push(edit);
    applyEdit(edit, false);
  });
  // FIXED381: session-only audit trail. No browser storage or remote service.
  const changeHistory = [];
  const historyList = document.getElementById('change-history');
  const historyCount = document.getElementById('history-count');
  const historyExport = document.getElementById('export-history');
  function recordChange(kind, changes) {
    const changed = changes.filter(entry => entry.before !== entry.after);
    if (!changed.length) return;
    changeHistory.push({sequence: changeHistory.length + 1, kind, changes: changed});
    const item = document.createElement('li');
    item.textContent = `${changeHistory.length}. ${kind}：${changed.length}件`;
    historyList.appendChild(item);
    historyCount.textContent = `${changeHistory.length}操作を記録（このページを閉じると消去）`;
  }
  function downloadJSON(filename, payload) {
    const blob = new Blob([JSON.stringify(payload, null, 2) + '\n'], {type:'application/json'});
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  const tableBody = document.querySelector('tbody');
  const rows = Array.from(document.querySelectorAll('tbody tr[data-issue-row]'));
  // FIXED378: sort visible and hidden rows together; export still covers all items.
  const priorityRank = {'高': 0, '中': 1, '要確認': 2};
  const statusRank = {'未対応': 0, '対応中': 1, '修正済み': 2};
  function rank(map, value) { return Object.prototype.hasOwnProperty.call(map, value) ? map[value] : 99; }
  function sortRows() {
    const mode = sortMode.value;
    const sorted = rows.map((row, index) => ({row, index}));
    sorted.sort((a, b) => {
      if (mode === 'original') return a.index - b.index;
      const statusA = a.row.querySelector('select[data-issue-id]').value;
      const statusB = b.row.querySelector('select[data-issue-id]').value;
      const priorityA = rank(priorityRank, a.row.dataset.priority);
      const priorityB = rank(priorityRank, b.row.dataset.priority);
      const statusDiff = rank(statusRank, statusA) - rank(statusRank, statusB);
      const priorityDiff = priorityA - priorityB;
      return (mode === 'priority' ? priorityDiff || statusDiff : statusDiff || priorityDiff) || a.index - b.index;
    });
    for (const item of sorted) tableBody.appendChild(item.row);
  }
  function updateFilters() {
    sortRows();
    const term = query.value.trim().toLocaleLowerCase();
    let visible = 0;
    for (const row of rows) {
      const match = (!term || row.textContent.toLocaleLowerCase().includes(term)) &&
        (!category.value || row.dataset.category === category.value) &&
        (!priority.value || row.dataset.priority === priority.value) &&
        (!status.value || row.querySelector('select[data-issue-id]').value === status.value);
      row.hidden = !match;
      if (match) visible++;
    }
    count.textContent = `${visible} / ${rows.length} 件表示`;
  }
  for (const field of [query, category, priority, status]) {
    field.addEventListener(field === query ? 'input' : 'change', updateFilters);
  }
  // FIXED382: individual edits participate in the same undo/redo history.
  const previousValues = new Map(Array.from(selections, s => [s, s.value]));
  for (const select of selections) {
    select.addEventListener('change', () => {
      commitEdit('個別変更', [{issue_id:select.dataset.issueId, before:previousValues.get(select), after:select.value}]);
      previousValues.set(select, select.value);
      updateFilters();
    });
  }
  sortMode.addEventListener('change', updateFilters);
  updateFilters();
  // FIXED379: bulk edits affect only currently visible rows, never filtered-out entries.
  bulkApply.addEventListener('click', () => {
    const target = bulkStatus.value;
    if (!allowed.includes(target)) return;
    const visibleRows = rows.filter(row => !row.hidden);
    if (!visibleRows.length) {
      bulkMessage.textContent = '変更対象がありません。';
      return;
    }
    if (!window.confirm(`${visibleRows.length}件の対応状況を「${target}」に変更しますか？`)) return;
    const changes = visibleRows.map(row => {
      const select = row.querySelector('select[data-issue-id]');
      return {issue_id:select.dataset.issueId, before:select.value, after:target};
    });
    if (!commitEdit('一括変更', changes)) {
      bulkMessage.textContent = '変更が必要な項目はありません。';
      return;
    }
    for (const row of visibleRows) {
      const select = row.querySelector('select[data-issue-id]');
      select.value = target;
      previousValues.set(select, target);
    }
    updateFilters();
    bulkMessage.textContent = `${changes.filter(c => c.before !== c.after).length}件を「${target}」に変更しました。`;
  });
  button.addEventListener('click', () => {
    const statuses = {};
    for (const select of selections) {
      if (!allowed.includes(select.value)) return;
      statuses[select.dataset.issueId] = select.value;
    }
    downloadJSON('manual_statuses.json', {schema_version:1,statuses,base_statuses:initialStatuses});
  });
  historyExport.addEventListener('click', () => {
    downloadJSON('status_change_history.json', {schema_version:1, changes:changeHistory});
  });
})();
</script>'''

def render(result):
    if not isinstance(result, dict) or not isinstance(result.get('items'), list):
        raise ValueError('invalid status report')
    columns = ('priority', 'status', 'category', 'message', 'issue_id', 'suggested_check')
    rows = []
    categories = set()
    priorities = set()
    for item in result['items']:
        if not isinstance(item, dict) or not isinstance(item.get('issue_id'), str) or not item['issue_id']:
            raise ValueError('invalid issue')
        status = item.get('manual_status', '未対応')
        if status not in ('未対応', '対応中', '修正済み'):
            raise ValueError('invalid manual status')
        categories.add(str(item.get('category', '')))
        priorities.add(str(item.get('priority', '')))
        select = '<select aria-label="対応状況" data-issue-id="' + html.escape(item['issue_id'], quote=True) + '">' + ''.join(
            '<option value="' + html.escape(s) + '"' + (' selected' if s == status else '') + '>' + html.escape(s) + '</option>' for s in ('未対応', '対応中', '修正済み')) + '</select>'
        rows.append('<tr data-issue-row data-category="' + html.escape(str(item.get('category', '')), quote=True) + '" data-priority="' + html.escape(str(item.get('priority', '')), quote=True) + '"><td>' + select + '</td>' + ''.join('<td>' + html.escape(str(item.get(k, ''))) + '</td>' for k in columns) + '</tr>')
    def choices(values):
        return '<option value="">すべて</option>' + ''.join('<option value="' + html.escape(v, quote=True) + '">' + html.escape(v) + '</option>' for v in sorted(values) if v)
    body = ''.join(rows) if rows else '<tr><td colspan="7">診断対象なし</td></tr>'
    return ('<!doctype html><html lang="ja"><head><meta charset="utf-8"><title>HOTEL SHIFT 対応状況編集</title>'
            '<style>body{font-family:-apple-system,sans-serif;max-width:1200px;margin:2rem auto;padding:1rem}'
            'table{border-collapse:collapse;width:100%}td,th{padding:.6rem;border-bottom:1px solid #ddd;text-align:left;overflow-wrap:anywhere}'
            'button,select,input{padding:.5rem}tr[hidden]{display:none}.filters{display:flex;flex-wrap:wrap;gap:.8rem;margin:1rem 0}.filters label{display:grid;gap:.3rem}</style></head><body><h1>エラー対応状況の編集</h1>'
            '<p>状態を選択してJSONを保存できます。ブラウザだけでは元ファイルは書き換わりません。</p>'
            '<p>「修正済み」は手動メモであり、ビルド成功を意味しません。</p>'
            '<div class="filters"><label>検索<input id="filter-query" type="search" placeholder="エラー内容・IDを検索"></label>'
            '<label>分類<select id="filter-category">' + choices(categories) + '</select></label>'
            '<label>優先度<select id="filter-priority">' + choices(priorities) + '</select></label>'
            '<label>対応状況<select id="filter-status"><option value="">すべて</option><option>未対応</option><option>対応中</option><option>修正済み</option></select></label>'
            '<label>並べ替え<select id="sort-mode"><option value="status">未対応を優先</option><option value="priority">優先度順</option><option value="original">元の順序</option></select></label></div>'
            '<p id="visible-count" role="status" aria-live="polite"></p>'
            '<div class="filters"><label>表示中の項目を一括変更<select id="bulk-status"><option value="">変更先を選択</option><option>未対応</option><option>対応中</option><option>修正済み</option></select></label>'
            '<button type="button" id="bulk-apply">表示中の項目に適用</button>'
            '<button type="button" id="edit-undo" disabled>変更を取り消す</button>'
            '<button type="button" id="edit-redo" disabled>やり直す</button></div><p id="bulk-message" role="status" aria-live="polite"></p>'
            '<button type="button" id="export-statuses">対応状況JSONを保存（非表示の項目も含む）</button>'
            '<section aria-labelledby="history-heading"><h2 id="history-heading">このページでの変更履歴</h2>'
            '<p id="history-count" role="status">0操作を記録（このページを閉じると消去）</p>'
            '<ol id="change-history"></ol><button type="button" id="export-history">変更履歴JSONを保存</button>'
            '<p>履歴は閲覧中の操作のみ記録します。保存した履歴JSONは対応状況の取り込み用ではありません。</p></section>'
            '<table><thead><tr><th>手動対応状況</th><th>優先度</th><th>検出状況</th><th>分類</th><th>エラー</th><th>識別ID</th><th>確認事項</th></tr></thead><tbody>'
            + body + '</tbody></table>' + SCRIPT + '</body></html>')

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('report', type=Path)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    try:
        content = render(json.loads(args.report.read_text(encoding='utf-8')))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content, encoding='utf-8')
    except (OSError, ValueError, TypeError) as exc:
        p.exit(2, f'Cannot create HTML editor: {exc}\n')

if __name__ == '__main__':
    main()
