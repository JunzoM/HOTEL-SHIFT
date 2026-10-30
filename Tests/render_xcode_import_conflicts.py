#!/usr/bin/env python3
"""Render an offline, escaped HTML report for stale triage import conflicts."""
import argparse
import html
import hashlib
import json
from pathlib import Path
from manage_xcode_triage_status import load_json_strict

FIELDS = ('issue_id', 'category', 'message', 'baseline_status', 'current_status', 'imported_status')

def render(report):
    """Produce a safe, offline guide to reviewing conflicts without auto-merging."""
    if not isinstance(report, dict) or type(report.get('schema_version')) is not int or report['schema_version'] != 1:
        raise ValueError('invalid conflict report version')
    conflicts = report.get('conflicts')
    if not isinstance(conflicts, list) or type(report.get('conflict_count')) is not int or report['conflict_count'] != len(conflicts):
        raise ValueError('invalid conflict count')
    if not isinstance(report.get('resolution'), str):
        raise ValueError('invalid resolution guidance')
    rows = []
    seen = set()
    for item in conflicts:
        if not isinstance(item, dict) or any(not isinstance(item.get(key), str) for key in FIELDS):
            raise ValueError('invalid conflict item')
        if not item['issue_id'] or item['issue_id'] in seen:
            raise ValueError('invalid or repeated conflict ID')
        seen.add(item['issue_id'])
        cells = ''.join('<td>' + html.escape(item[key], quote=True) + '</td>' for key in FIELDS)
        rows.append('<tr data-conflict-row><td><input type="checkbox" class="review-check" data-issue-id="' + html.escape(item['issue_id'], quote=True) + '" aria-label="確認済み: ' + html.escape(item['issue_id'], quote=True) + '"></td>' + cells + '</tr>')
    # Bind review progress to the exact report content, not merely the count or IDs.
    # Canonical JSON ensures reproducible hashes across machines and runs.
    identity = [{key: item[key] for key in FIELDS} for item in conflicts]
    canonical = json.dumps(sorted(identity, key=lambda item: item['issue_id']), ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    report_fingerprint = hashlib.sha256(canonical.encode('utf-8')).hexdigest()
    body = ''.join(rows) if rows else '<tr><td colspan="7">競合なし</td></tr>'
    headers = ''.join('<th scope="col">' + x + '</th>' for x in ('確認','識別ID','分類','エラー内容','編集開始時','現在の保存状態','取り込み予定'))
    return ('<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>HOTEL SHIFT 取り込み競合レポート</title><style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;max-width:1200px;margin:2rem auto;padding:1rem;color:#202124}'
            '#import-result[data-error="true"]{color:#9b1c1c;font-weight:600}#import-help:not([hidden]){background:#fff5e5;border-left:4px solid #a16207;padding:.8rem 1rem;margin:.5rem 0}#import-help p{margin:.25rem 0}#import-result[data-error="false"]{color:#166534}input[type=search]{padding:.6rem;width:min(100%,30rem)}button{padding:.5rem;margin:.3rem}tr[data-conflict-row]:focus{outline:3px solid #2563eb;outline-offset:-3px}#next-unreviewed:disabled,#previous-unreviewed:disabled,#review-and-next:disabled{opacity:.55;cursor:not-allowed}table{border-collapse:collapse;width:100%}th,td{padding:.7rem;border-bottom:1px solid #ddd;text-align:left;overflow-wrap:anywhere}th{background:#f4f5f7}'
            '.skip-link{position:absolute;left:-9999px}.skip-link:focus{left:1rem;top:1rem;background:#fff;padding:.6rem;z-index:5}.toolbar{display:flex;flex-wrap:wrap;gap:.4rem;align-items:center;margin:.6rem 0}.toolbar button{margin:0}.toolbar input[type=search]{flex:1;min-width:14rem}.review-panel{border:1px solid #ddd;border-radius:.7rem;padding:1rem;margin:1rem 0}.review-panel h2{margin-top:0}.selected-row{background:#eff6ff}tr[data-conflict-row]{cursor:pointer}tr[data-conflict-row]:hover{background:#f8fafc}.keyboard-guide{margin:.5rem 0}.keyboard-guide summary{cursor:pointer;font-weight:600}@media(max-width:650px){body{margin:.2rem auto;padding:.7rem}.review-panel{padding:.7rem}.toolbar{align-items:stretch}.toolbar button{flex:1}}@media print{button,input,.keyboard-guide,.skip-link{display:none!important}.review-panel{border:0;padding:0}.scroll{overflow:visible}body{max-width:none;margin:0;font-size:10pt}tr{break-inside:avoid}}.progress-track{height:14px;background:#e5e7eb;border-radius:999px;overflow:hidden;max-width:34rem}.progress-fill{height:100%;width:0;background:#166534;transition:width .15s ease}.progress-summary{font-weight:600;margin:.7rem 0}.scroll{overflow-x:auto}.note{background:#fff5e5;padding:1rem;border-radius:.5rem}li{margin:.6rem 0}code{background:#f4f5f7;padding:.2rem .35rem}</style></head><body>'
            '<a class="skip-link" href="#conflict-table">競合一覧へ移動</a><h1>取り込み競合レポート</h1><p class="note">競合を検出したため、取り込み全体を中止しました。保存済みの対応状況は変更されていません。</p>'
            '<p>競合件数：<strong>' + str(len(conflicts)) + '</strong></p>'
            '<section class="review-panel" aria-label="競合の確認作業"><h2>確認作業</h2><label for="conflict-search">競合ID・分類・内容で検索：</label> '
            '<div class="toolbar"><input id="conflict-search" type="search" placeholder="確認したい項目を入力">'
            '<label><input type="checkbox" id="unreviewed-only">未確認のみ</label><button id="previous-unreviewed" type="button" aria-describedby="next-unreviewed-help">前の未確認項目へ</button><button id="next-unreviewed" type="button" aria-describedby="next-unreviewed-help">次の未確認項目へ</button><button id="review-and-next" type="button" disabled>選択中を確認済みにして次へ</button><span id="next-unreviewed-help">未確認項目へ移動します。検索条件は必要に応じて解除されます。行を選択して「確認済みにして次へ」を押すと、チェック後に次の未確認項目へ移動します。ショートカット：N＝次、P＝前、Enter＝選択中を確認済みにして次へ（入力欄では無効）。</span></div><p id="selected-conflict" role="status" aria-live="polite">選択中：なし</p><details class="keyboard-guide"><summary>キーボード操作と使い方</summary><p>N：次、P：前、Enter：確認済みにして次へ。入力中は無効です。</p></details>'
            '<p id="review-count" aria-live="polite"></p><p id="review-progress-label" class="progress-summary" aria-live="polite"></p><div id="review-progress" class="progress-track" role="progressbar" aria-label="競合確認の進捗" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0" aria-valuetext="0%"><div id="review-progress-fill" class="progress-fill"></div></div><label for="import-review"> 確認状況JSONを読み込む：</label><input id="import-review" type="file" accept=".json,application/json"><p id="import-result" role="status" aria-live="polite"></p><div id="import-help" role="note" hidden><strong>解決方法</strong><p id="import-help-text"></p></div><button id="export-review" type="button">確認状況JSONを保存</button></section><h2 id="conflict-table">競合一覧</h2><div class="scroll"><table><thead><tr>' + headers + '</tr></thead><tbody>' + body + '</tbody></table></div>'
            '<p>確認状況JSONは作業メモです。取り込み用の対応状況JSONではなく、保存済みの対応状況も変更しません。</p><h2>安全に再編集・再取り込みする手順</h2><ol>'
            '<li>上の一覧で「現在の保存状態」と「取り込み予定」を比較し、各項目の最終的な状態を決めます。</li>'
            '<li>最新の診断結果と保存済み対応状況から、編集画面を再生成します。古いHTMLをそのまま使わないでください。</li>'
            '<li>再生成した <code>triage_editor.html</code> を開き、必要な項目だけ変更して新しいJSONを書き出します。</li>'
            '<li>新しいJSONを取り込み直します。再度競合した場合は、最新の保存状態を確認してやり直します。</li>'
            '</ol><p><strong>注意：</strong>「修正済み」は手動記録であり、Xcodeビルド成功を意味しません。'
            '古いJSONの <code>base_statuses</code> だけを書き換えて強制取り込みしないでください。</p>'
            '<h2>補足</h2><p>' + html.escape(report['resolution'], quote=True) + '</p>'
            '<script type="text/javascript">\nconst reportFingerprint=' + json.dumps(report_fingerprint) + ';\n' + '''
(function(){
  const search=document.getElementById('conflict-search');
  const only=document.getElementById('unreviewed-only');
  const count=document.getElementById('review-count');
  const progress=document.getElementById('review-progress');
  const progressFill=document.getElementById('review-progress-fill');
  const progressLabel=document.getElementById('review-progress-label');
  const rows=Array.from(document.querySelectorAll('tr[data-conflict-row]'));
  const nextButton=document.getElementById('next-unreviewed');
  const previousButton=document.getElementById('previous-unreviewed');
  const reviewAndNext=document.getElementById('review-and-next');
  let lastFocusedIndex=-1;
  const selectedLabel=document.getElementById('selected-conflict');
  function setSelection(index){
    lastFocusedIndex=index;
    rows.forEach((row,i)=>{
      row.classList.toggle('selected-row',i===index);
      row.setAttribute('aria-selected',String(i===index));
    });
    const row=rows[index];
    selectedLabel.textContent=row?'選択中：'+row.querySelector('.review-check').getAttribute('data-issue-id'):'選択中：なし';
    refresh();
  }
  // Only export review progress. Never modify the triage statuses or import payload.
  function reviewSnapshot(){
    return {schema_version:2,kind:'conflict_review_progress',report_fingerprint:reportFingerprint,conflict_count:rows.length,
      reviewed_ids:rows.filter(row=>row.querySelector('.review-check').checked)
        .map(row=>row.querySelector('.review-check').getAttribute('data-issue-id'))};
  }
  // Validate the complete snapshot before changing any checkbox. A different
  // conflict report must not silently reuse IDs from an older review session.
  function validateReviewSnapshot(value){
    if(!value || typeof value!=='object' || Array.isArray(value))
      throw new Error('JSONの内容が確認状況データではありません。');
    if(value.schema_version===1)
      throw new Error('旧形式の確認状況JSONです。元のレポートで新形式のJSONを保存してください。');
    if(value.schema_version!==2 || value.kind!=='conflict_review_progress')
      throw new Error('確認状況JSONの種類またはバージョンが対応していません。');
    if(value.report_fingerprint!==reportFingerprint)
      throw new Error('別の競合レポートの確認状況です。対象のレポートを開いてください。');
    if(!Number.isInteger(value.conflict_count) || value.conflict_count!==rows.length)
      throw new Error('競合件数が現在のレポートと一致しません。');
    if(!Array.isArray(value.reviewed_ids))
      throw new Error('確認済みIDの一覧が不正です。');
    const known=new Set(rows.map(row=>row.querySelector('.review-check').getAttribute('data-issue-id')));
    const selected=new Set();
    for(const id of value.reviewed_ids){
      if(typeof id!=='string' || !known.has(id))
        throw new Error('確認状況JSONに現在のレポートにない識別IDがあります。');
      if(selected.has(id))
        throw new Error('確認状況JSONに重複した識別IDがあります。');
      selected.add(id);
    }
    return selected;
  }
  const importInput=document.getElementById('import-review');
  const importResult=document.getElementById('import-result');
  const importHelp=document.getElementById('import-help');
  const importHelpText=document.getElementById('import-help-text');
  function recoveryGuidance(message){
    if(message.includes('旧形式')) return '以前の競合レポートを開き、確認状況JSONを新形式で保存し直してください。旧形式をこの画面に強制適用しないでください。';
    if(message.includes('別の競合レポート')) return 'JSONを保存した元の競合レポートを開いてください。現在のレポートには適用できません。';
    if(message.includes('競合件数')) return '現在開いている競合レポートと、保存元のレポートを確認してください。正しい組み合わせで再度読み込んでください。';
    if(message.includes('識別ID')) return '保存元の競合レポートを確認し、現在のレポートから確認状況JSONを保存し直してください。JSONのIDを手動で書き換えないでください。';
    if(message.includes('構文')) return 'JSONファイルを選び直してください。ファイルが壊れている場合は、元のレポートから再度保存してください。';
    if(message.includes('大きすぎ')) return '1MB以下の確認状況JSONを選んでください。別のファイルを誤って選択していないか確認してください。';
    return '「確認状況JSONを保存」で出力したファイルを選んでください。必要なら現在のレポートで新しく保存し直してください。';
  }
  importInput.addEventListener('change',async()=>{
    const file=importInput.files && importInput.files[0];
    if(!file) return;
    try{
      if(file.size>1024*1024) throw new Error('ファイルが大きすぎます（上限1MB）。');
      let payload;
      try{payload=JSON.parse(await file.text());}
      catch(error){throw new Error('JSONの構文が不正です。ファイルを確認してください。');}
      const selected=validateReviewSnapshot(payload);
      rows.forEach(row=>{
        const check=row.querySelector('.review-check');
        check.checked=selected.has(check.getAttribute('data-issue-id'));
      });
      importHelp.hidden=true;
      importHelpText.textContent='';
      refresh();
      importResult.dataset.error='false';
      importResult.textContent='確認状況を復元しました（'+selected.size+'件）。';
    }catch(error){
      importResult.dataset.error='true';
      const message=error instanceof Error?error.message:'不明なエラー';
      importResult.textContent='読み込み中止：'+message;
      importHelpText.textContent=recoveryGuidance(message);
      importHelp.hidden=false;
    }finally{importInput.value='';}
  });
  document.getElementById('export-review').addEventListener('click',()=>{
    const blob=new Blob([JSON.stringify(reviewSnapshot(),null,2)+'\\n'],{type:'application/json'});
    const url=URL.createObjectURL(blob);
    const anchor=document.createElement('a'); anchor.href=url; anchor.download='conflict_review_progress.json';
    document.body.appendChild(anchor); anchor.click(); anchor.remove();
    URL.revokeObjectURL(url);
  });
  function refresh(){
    const term=search.value.trim().toLocaleLowerCase();
    let visible=0, reviewed=0;
    rows.forEach(row=>{
      const done=row.querySelector('.review-check').checked;
      if(done) reviewed++;
      const show=(!term || row.textContent.toLocaleLowerCase().includes(term)) && (!only.checked || !done);
      row.hidden=!show; if(show) visible++;
    });
    const remaining=rows.length-reviewed;
    const percentage=rows.length?Math.round(reviewed*100/rows.length):100;
    count.textContent='表示 '+visible+' / '+rows.length+' 件・確認済み '+reviewed+' 件';
    progressLabel.textContent='確認進捗 '+percentage+'%（確認済み '+reviewed+' 件・未確認 '+remaining+' 件）';
    progress.setAttribute('aria-valuenow',String(percentage));
    progress.setAttribute('aria-valuetext',percentage+'%');
    progressFill.style.width=percentage+'%';
    nextButton.disabled=remaining===0;
    previousButton.disabled=remaining===0;
    reviewAndNext.disabled=lastFocusedIndex<0 || !rows[lastFocusedIndex] || rows[lastFocusedIndex].querySelector('.review-check').checked;
    nextButton.textContent=remaining===0?'すべて確認済み':'次の未確認項目へ（残り '+remaining+' 件）';
    previousButton.textContent=remaining===0?'すべて確認済み':'前の未確認項目へ（残り '+remaining+' 件）';
  }
  function navigateUnreviewed(direction){
    // Navigate only unresolved items, including the first/last wraparound.
    // If a previously focused row has since been reviewed, its position
    // still serves as the anchor. Never modify review checkboxes here.
    const candidates=rows.map((row,index)=>({row,index}))
      .filter(entry=>!entry.row.querySelector('.review-check').checked);
    if(!candidates.length) return;
    let entry;
    if(direction>0){
      entry=candidates.find(item=>item.index>lastFocusedIndex) || candidates[0];
    }else{
      entry=candidates.slice().reverse().find(item=>item.index<lastFocusedIndex)
        || candidates[candidates.length-1];
    }
    setSelection(entry.index);
    // Hidden search results must not prevent access to unresolved conflicts.
    search.value='';
    only.checked=false;
    refresh();
    entry.row.setAttribute('tabindex','-1');
    entry.row.focus();
    entry.row.scrollIntoView({block:'center',behavior:'auto'});
  }
  // Explicit confirmation only: navigation alone never marks an item reviewed.
  reviewAndNext.addEventListener('click',()=>{
    const row=rows[lastFocusedIndex];
    if(!row) return;
    const check=row.querySelector('.review-check');
    if(check.checked) return;
    check.checked = true;
    refresh();
    navigateUnreviewed(1);
  });
  rows.forEach((row,index)=>{
    row.addEventListener('click',()=>setSelection(index));
    row.addEventListener('focusin',()=>setSelection(index));
  });
  nextButton.addEventListener('click',()=>navigateUnreviewed(1));
  previousButton.addEventListener('click',()=>navigateUnreviewed(-1));
  // Keyboard shortcuts work only when the user is not editing or activating a control.
  // Ignore modified keystrokes and auto-repeat to prevent accidental confirmation.
  document.addEventListener('keydown',event=>{
    if(event.defaultPrevented || event.ctrlKey || event.metaKey || event.altKey || event.shiftKey || event.repeat || event.isComposing) return;
    const target=event.target;
    if(target && (target.isContentEditable || target.closest('input,textarea,select,button,[contenteditable]'))) return;
    const key=event.key.toLowerCase();
    if(key==='n') {event.preventDefault();navigateUnreviewed(1);}
    else if(key==='p') {event.preventDefault();navigateUnreviewed(-1);}
    else if(event.key==='Enter' && !reviewAndNext.disabled){
      event.preventDefault();reviewAndNext.click();
    }
  });
  search.addEventListener('input',refresh);
  only.addEventListener('change',refresh);
  rows.forEach(row=>row.querySelector('.review-check').addEventListener('change',refresh));
  refresh();
})();
</script></body></html>''')

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('report', type=Path)
    p.add_argument('--output', required=True, type=Path)
    args = p.parse_args()
    try:
        content = render(load_json_strict(args.report))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temp = args.output.with_name(args.output.name + '.tmp')
        temp.write_text(content, encoding='utf-8')
        temp.replace(args.output)
        print('Conflict HTML:', args.output)
    except (OSError, ValueError, TypeError) as exc:
        p.exit(2, f'Cannot render conflict report: {exc}\n')

if __name__ == '__main__':
    main()
