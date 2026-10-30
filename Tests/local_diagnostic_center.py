#!/usr/bin/env python3
"""Offline one-click diagnostics UI. Binds exclusively to local loopback."""
import argparse
import html
import json
import secrets
import subprocess
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PAGE = r'''<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>HOTEL SHIFT 診断センター</title><style>
:root{font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;color:#17243a;background:#f4f6fa}body{max-width:850px;margin:38px auto;padding:0 18px}header,section{background:white;border:1px solid #e1e5ed;border-radius:16px;padding:24px;margin:16px 0}h1{margin:0 0 8px;font-size:27px}h2{font-size:19px}p{line-height:1.7}button{border:0;border-radius:10px;padding:14px 24px;background:#224c8d;color:white;font-weight:700;font-size:16px;cursor:pointer}button:disabled{opacity:.5;cursor:wait}.copy{background:#17634c;font-size:14px;padding:10px 15px;margin:8px 8px 8px 0}.copy-status{font-size:13px;color:#17634c}.all-copy{background:#224c8d;margin-top:12px}.all-copy:disabled{cursor:not-allowed}.priority{border-left:5px solid #b45309}.priority h2{margin-top:0}.priority li{padding:6px 0}.priority strong{color:#92400e}.priority-nav{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin-top:14px}.priority-nav button{padding:9px 14px;font-size:14px}.priority-target{outline:3px solid #b45309;outline-offset:4px;scroll-margin-top:22px}.priority-position{font-size:14px;color:#58677e}.priority li button{margin:4px 0;padding:7px 12px;font-size:13px}.error-summary{background:#fff8ed;border:1px solid #f0d5a6;border-radius:10px;padding:12px;margin-top:12px}.error-summary summary{font-weight:700;cursor:pointer}.error-summary li{overflow-wrap:anywhere}.error-summary code{font-size:13px}.hint-target{outline:3px solid #17634c;outline-offset:3px;scroll-margin-top:22px}.hint-jump{background:#17634c;font-size:13px;padding:8px 12px;margin-top:8px}.hint-list li{scroll-margin-top:22px}.progress-panel{background:#f0f7f4;border:1px solid #b9d9cb;border-radius:10px;padding:12px;margin:12px 0}.progress-panel button{font-size:13px;padding:8px 12px;margin:6px 0}.progress-done{opacity:.65}.progress-done strong{text-decoration:line-through}.progress-counter{font-weight:700;color:#17634c}.history{border-left:5px solid #224c8d}.history-list details{margin:4px 0}.history-list summary{cursor:pointer;font-weight:600}.history>button{font-size:13px;padding:9px 13px;background:#58677e}.history .csv-export{background:#17634c;margin-right:10px}.history-filter{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}.history-filter button{font-size:13px;padding:8px 12px;background:#e8edf5;color:#17243a}.history-filter button[aria-pressed="true"]{background:#224c8d;color:white}.history-count{font-size:13px;color:#58677e}.history-chart{border:1px solid #e1e5ed;border-radius:12px;padding:14px;margin:12px 0}.history-chart svg{display:block;width:100%;height:auto;max-height:250px}.history-chart .chart-axis{stroke:#a5b2c4;stroke-width:1}.history-chart .chart-line{stroke:#224c8d;stroke-width:3;fill:none;stroke-linecap:round;stroke-linejoin:round}.history-chart .chart-dot{fill:#224c8d}.history-chart .chart-label{fill:#58677e;font-size:12px}.history-chart .chart-rate{fill:#17634c;font-size:15px;font-weight:700}.history-chart .chart-rate-bg{fill:#e7f5ed}.history-chart .chart-dot{cursor:pointer}.history-chart .chart-dot:focus{outline:none;stroke:#b45309;stroke-width:4}.history-chart .chart-selected{fill:#b45309;stroke:#92400e;stroke-width:2}.chart-point-detail{background:#edf4ff;border-radius:9px;padding:10px 12px;font-size:14px}.history-chart .chart-empty{color:#58677e;font-size:13px}.history-recent{border-top:1px solid #e1e5ed;margin-top:12px;padding-top:10px}.history-recent h3{font-size:15px;margin:4px 0}.history-rate{font-weight:700;color:#224c8d;background:#edf4ff;border-radius:9px;padding:10px 12px}.history-trend{font-weight:700;padding:10px 12px;border-radius:9px;background:#eef2f8}.history-trend[data-trend="improved"]{background:#e7f5ed;color:#17634c}.history-trend[data-trend="worsened"]{background:#fff0ed;color:#a12a24}.history-trend[data-trend="unchanged"]{background:#eef2f8;color:#224c8d}.privacy{font-size:13px;color:#58677e}.ok{color:#067548}.bad{color:#b02d26}.muted{color:#58677e}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f2f5f9;border-radius:8px;padding:12px}details{margin-top:12px}li{margin:8px 0}#status{font-weight:600}a{color:#224c8d}.chart-point-nav{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0}.chart-point-nav button{font-size:13px;padding:8px 12px}.chart-point-copy{background:#17634c}.chart-point-consult{background:#5b4389}.chart-multi-csv{background:#17634c}.chart-multi-summary{background:#f6f8fc;border:1px solid #d9e1ef;border-radius:10px;padding:12px;margin:10px 0}.chart-multi-summary h4{margin:0 0 8px}.chart-multi-steps{overflow-x:auto;margin:12px 0}.chart-multi-steps h4{margin:0 0 8px}.chart-steps-table{width:100%;border-collapse:collapse;font-size:13px}.chart-steps-table th,.chart-steps-table td{border:1px solid #d9e1ef;padding:8px;text-align:left}.chart-steps-table tr[data-trend="improved"] td:last-child{color:#17634c;font-weight:700}.chart-steps-table tr[data-trend="worsened"] td:last-child{color:#a12a24;font-weight:700}.chart-transition-bar{display:flex;width:100%;height:24px;border-radius:7px;overflow:hidden;background:#eef2f8;margin:12px 0 8px}.chart-transition-segment{height:100%;min-width:0}.chart-transition-segment[data-trend="improved"]{background:#16804e}.chart-transition-segment[data-trend="worsened"]{background:#c43e38}.chart-transition-segment[data-trend="unchanged"]{background:#8492a6}.chart-transition-legend{display:flex;flex-wrap:wrap;gap:8px 16px;font-size:13px}.chart-transition-legend span{white-space:nowrap}.chart-transition-legend span::before{content:"■ ";color:#8492a6}.chart-transition-legend span[data-trend="improved"]::before{color:#16804e}.chart-transition-legend span[data-trend="worsened"]::before{color:#c43e38}.chart-jump{margin:.5rem 0 0}.history-jump-target{outline:3px solid #c49b52;outline-offset:3px;border-radius:8px}.history-return-chart{font-size:13px;padding:8px 12px;margin:10px 0;background:#17634c}.history-chart-return{outline:3px solid #17634c;outline-offset:3px;scroll-margin-top:20px}#comparison-print-report{display:none}@media print{body{max-width:none;margin:0;padding:0;background:white;color:#111}body>*:not(#comparison-print-report){display:none!important}#comparison-print-report{display:block!important;font-family:-apple-system,BlinkMacSystemFont,sans-serif;font-size:11pt}#comparison-print-report h1{font-size:20pt}#comparison-print-report h2{font-size:13pt;margin:14px 0 4px}#comparison-print-report .print-comparison-summary{border:1px solid #999;border-radius:8px;padding:8px 14px;margin:12px 0;break-inside:avoid}#comparison-print-report svg{display:block;width:100%;height:190px;break-inside:avoid}#comparison-print-report table{width:100%;border-collapse:collapse;margin-top:16px}#comparison-print-report th,#comparison-print-report td{border:1px solid #777;padding:9px;text-align:left}#comparison-print-report th{background:#eee}#comparison-print-report p{font-size:10pt} @page{size:A4 landscape;margin:15mm}}
</style></head><body>
<header><h1>HOTEL SHIFT 診断センター</h1><p class="muted">Mac上で動くローカル診断ツールです。クラウドへの送信は行いません。</p><button id="run" type="button">診断を実行</button><p id="status" role="status" aria-live="polite">ボタンを押すとSwift構文と回帰テストを診断します。</p></header><main id="results"></main><script>
const token = new URLSearchParams(location.search).get('token');
const button=document.getElementById('run'), status=document.getElementById('status'), results=document.getElementById('results');
function el(tag,text,cls){const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;}
function advice(name,check){const s=check.status;const logs=(check.stderr||'')+'\\n'+(check.stdout||'');if(s==='passed')return 'この検査は正常です。追加の操作は必要ありません。';if(s==='timeout')return '検査が時間内に終わりませんでした。Macの負荷を確認し、他の作業を終了してから再実行してください。';if(s==='error')return '検査プログラムを開始できません。Python 3、Swiftコマンド、ファイルの配置を確認してください。';if(name==='swift_syntax')return '下の実行ログでファイル名と行番号を確認し、Swiftの構文エラーを修正してから再診断してください。Xcodeの実ビルドも別途必要です。';if(/not found|No such file|command not found/i.test(logs))return '必要なコマンドやファイルが見つかりません。プロジェクトをZIPから展開し、Macの開発環境を確認してください。';return '下の実行ログで失敗したFIXED番号とテスト名を確認してください。原因を修正してから「診断を実行」を押してください。';}
function repairHints(name,check){
  if(check.status==='passed')return [];
  const logs=((check.stderr||'')+'\n'+(check.stdout||'')).slice(0,80000);
  const hints=[];
  function add(file,reason,action){if(!hints.some(x=>x.file===file&&x.reason===reason))hints.push({file,reason,action});}
  if(name==='swift_syntax'){
    // Swift compiler messages: /path/File.swift:12:5: error: ...
    const re=/([^\s\n:]+\.swift):(\d+):(\d+):\s*(?:error|warning):\s*([^\n]+)/g;
    for(const match of logs.matchAll(re)){
      const filename=match[1].split('/').slice(-3).join('/');
      add(filename+':'+match[2]+':'+match[3],match[4].slice(0,220),'Xcodeで該当ファイルと行を開き、構文を確認してください。修正後に再診断してください。');
      if(hints.length>=8)break;
    }
  }else{
    const re=/(?:Tests\/)?(verify_fixed\d+\.py)/gi;
    for(const match of logs.matchAll(re)){
      add('Tests/'+match[1],'回帰テストで参照されたファイル','このテストを個別に実行し、失敗したアサーションと関連する実装を確認してください。');
      if(hints.length>=8)break;
    }
  }
  if(/(?:command not found|swiftc: not found|No such file or directory|ModuleNotFoundError)/i.test(logs))
    add('Macの開発環境','必要なコマンド・ファイル・Pythonモジュールが見つかりません','Xcode Command Line ToolsとPython 3の設定、ZIPの展開場所を確認してください。');
  if(check.status==='timeout')add('診断の実行環境','時間制限に達しました','他の重い処理を終了し、もう一度診断してください。繰り返す場合は詳細ログを確認してください。');
  if(hints.length===0)add('実行ログ','原因となるファイルを自動特定できませんでした','「実行ログを表示」を開き、error・FAIL・Traceback付近を確認してChatGPTに相談してください。');
  return hints;
}
function errorHighlights(name,check){
  if(check.status==='passed')return [];
  const logs=((check.stderr||'')+'\n'+(check.stdout||'')).slice(0,80000);
  const lines=logs.split(/\r?\n/);
  const selected=[];
  for(let i=0;i<lines.length;i++){
    const line=lines[i].trim();
    if(!line)continue;
    const swift=name==='swift_syntax'&&/\.swift:\d+(?::\d+)?:\s*(?:error|warning):/i.test(line);
    const test=/^(?:FAIL|ERROR):\s|AssertionError|Traceback \(most recent call last\)|ModuleNotFoundError|command not found|timed out|timeout/i.test(line);
    if(swift||test){selected.push({line:i+1,text:line.slice(0,350)});if(selected.length>=6)break;}
  }
  if(!selected.length&&check.status!=='passed'){
    const first=lines.findIndex(x=>x.trim());
    if(first>=0)selected.push({line:first+1,text:lines[first].trim().slice(0,350)});
  }
  return selected;
}
function addErrorHighlights(section,name,check){
  if(check.status==='passed')return;
  const details=el('details',undefined,'error-summary');
  details.append(el('summary','エラーの要点を見る'));
  const highlights=errorHighlights(name,check),list=el('ol');
  for(const item of highlights){const li=el('li');li.append(el('code','ログ '+item.line+'行：'+item.text));list.append(li);}
  details.append(el('p','重要と思われるログを最大6件表示します。正確な原因は詳細ログと照合してください。','muted'),list);
  const jump=el('button','修正候補へ移動','hint-jump');jump.type='button';
  jump.addEventListener('click',()=>{
    const target=section.querySelector('.hint-list li');
    if(!target)return;
    for(const node of section.querySelectorAll('.hint-target'))node.classList.remove('hint-target');
    target.classList.add('hint-target');
    target.scrollIntoView({behavior:'smooth',block:'start'});
    target.setAttribute('tabindex','-1');target.focus({preventScroll:true});
  });
  details.append(jump);section.append(details);
}
function singleHintPrompt(name,check,hint){
  const label=name==='swift_syntax'?'Swift構文解析':name==='regression'?'回帰テスト':name;
  const logs=((check.stderr||'')+'\n'+(check.stdout||'')).split(/\r?\n/);
  // Include only relevant log lines; avoid bundling other issues in a single-hint request.
  const file=hint.file.split(':')[0].split('/').pop();
  const matching=logs.filter(line=>line.includes(file)||line.includes(hint.reason)).slice(0,8);
  const excerpt=matching.join('\n').slice(0,1800);
  return ['HOTEL SHIFTの次の問題1件について、修正方法を教えてください。',
    '検査：'+label,'状態：'+check.status,'対象：'+hint.file,
    '検出内容：'+hint.reason,'修正候補：'+hint.action,
    '関連ログ：',excerpt||'（この候補に対応するログ行は抽出できませんでした）',
    '依頼：この問題に限定して原因の切り分け、修正箇所、コード例、再検証方法を提示してください。',
    'ログだけで断定できない場合は、必要な追加情報を教えてください。',
    '※ 推定候補です。Xcode実ビルドの結果ではありません。送信前に機密情報を確認してください。'].join('\n');
}
function addRepairHints(section,name,check){
  if(check.status==='passed')return;
  const hints=repairHints(name,check);
  section.append(el('h3','確認するファイル・修正候補'));
  const list=el('ol');list.className='hint-list';
  for(const hint of hints){
    const item=el('li');item.append(el('strong',hint.file),el('p',hint.reason),el('p',hint.action,'muted'));
    const copy=el('button','この修正候補だけをChatGPTに相談','copy hint-copy');copy.type='button';
    const msg=el('span','','copy-status');msg.setAttribute('role','status');
    copy.addEventListener('click',async()=>{
      try{await copyToClipboard(singleHintPrompt(name,check,hint));msg.textContent='この候補をコピーしました。内容を確認して貼り付けてください。';}
      catch(e){msg.textContent='コピーできませんでした。候補の内容を手動でコピーしてください。';}
    });
    item.append(copy,msg);list.append(item);
  }
  section.append(list,el('p','候補はログからの推定です。自動修正は行いません。','privacy'));
}
function copyText(name,check){const label=name==='swift_syntax'?'Swift構文解析':'回帰テスト';const logs=((check.stdout||'')+'\\n'+(check.stderr||'')).trim();const clipped=logs.length>6000?logs.slice(0,6000)+'\n…（長いため省略）':logs;return ['HOTEL SHIFT 診断結果', '検査：'+label, '状態：'+check.status, '対処方法：'+advice(name,check), '確認するファイル・修正候補：',...repairHints(name,check).map(h=>h.file+'：'+h.reason+'／'+h.action), '実行ログ：',clipped||'（ログなし）','※ Xcode実ビルドの結果ではありません。'].join('\n');}
function repairPrompt(name,check){
  const label=name==='swift_syntax'?'Swift構文解析':name==='regression'?'回帰テスト':name;
  const logs=((check.stderr||'')+'\n'+(check.stdout||'')).trim();
  const clipped=logs.length>6000?logs.slice(0,6000)+'\n…（長いため省略）':logs;
  const hints=repairHints(name,check);
  const lines=['HOTEL SHIFT の診断エラーについて修正方法を教えてください。','検査：'+label,'状態：'+(check.status||'不明'),
    '推定原因・確認箇所：',...hints.map((h,i)=>(i+1)+'. '+h.file+'\n   原因：'+h.reason+'\n   対処候補：'+h.action),
    '現在の対処案：'+advice(name,check),'実行ログ：',clipped||'（ログなし）','',
    '依頼：原因を切り分け、修正すべきファイル・行・コード例と検証手順を具体的に提示してください。',
    'ログだけで断定できない場合は必要な追加情報を教えてください。自動修正は行わないでください。',
    '※ この診断はXcode実ビルドやiPad実機動作を保証しません。'];
  return lines.join('\n');
}
function addRepairPromptButton(section,name,check){
  if(check.status==='passed')return;
  const copy=el('button','修正方法をChatGPTに相談する文章をコピー','copy');copy.type='button';
  const msg=el('span','','copy-status');msg.setAttribute('role','status');
  copy.addEventListener('click',async()=>{try{await copyToClipboard(repairPrompt(name,check));msg.textContent='コピーしました。内容を確認してChatGPTに貼り付けてください。';}catch(e){msg.textContent='コピーできませんでした。下のログを手動でコピーしてください。';}});
  section.append(copy,msg);
}
async function copyToClipboard(value){if(navigator.clipboard&&window.isSecureContext){await navigator.clipboard.writeText(value);return;}const field=document.createElement('textarea');field.value=value;field.setAttribute('readonly','');field.style.position='fixed';field.style.opacity='0';document.body.append(field);field.select();let ok=false;try{ok=document.execCommand('copy');}finally{field.remove();}if(!ok)throw Error('コピーが許可されませんでした');}
function allCopyText(data){
  const checks=data&&data.checks&&typeof data.checks==='object'?data.checks:{};
  const names=Object.keys(checks).sort();
  const header=['HOTEL SHIFT 診断結果（全項目）','総合結果：'+(data.overall_status||'不明'),'検査件数：'+names.length,'※ Xcode実ビルドやiPad実機テストの結果ではありません。'];
  for(const name of names){
    const check=checks[name];
    if(!check||typeof check!=='object')continue;
    header.push('','--- '+(name==='swift_syntax'?'Swift構文解析':name==='regression'?'回帰テスト':name)+' ---','状態：'+(check.status||'不明'),'対処方法：'+advice(name,check));
    const logs=((check.stdout||'')+'\n'+(check.stderr||'')).trim();
    header.push('確認するファイル・修正候補：',...repairHints(name,check).map(h=>h.file+'：'+h.reason+'／'+h.action));
    header.push('実行ログ：',logs.length>6000?logs.slice(0,6000)+'\n…（長いため省略）':logs||'（ログなし）');
  }
  header.push('','修正の優先順位：',...priorityItems(data).map((item,i)=>(i+1)+'. '+item.label+'（'+item.name+'）: '+item.reason),'','ChatGPTへの依頼：失敗した項目の原因を特定し、修正するファイルと手順を具体的に教えてください。','※ 送信前にログに個人情報・秘密情報がないか確認してください。');
  return header.join('\n');
}
function priorityItems(data){
  const checks=data&&data.checks&&typeof data.checks==='object'?data.checks:{};
  const items=[];
  for(const [name,check] of Object.entries(checks)){
    if(!check||typeof check!=='object'||check.status==='passed')continue;
    const logs=((check.stderr||'')+'\n'+(check.stdout||''));
    const env=check.status==='error'||/(?:command not found|swiftc: not found|ModuleNotFoundError|xcrun: error|unable to find utility|No such file or directory)/i.test(logs);
    const timed=check.status==='timeout';
    let rank,label,reason;
    if(env){rank=1;label='開発環境・実行環境';reason='Python 3・Swift・Xcode Command Line Toolsや必要ファイルの配置を先に確認してください。';}
    else if(timed){rank=2;label='診断の時間制限';reason='Macの負荷やタイムアウトを確認し、再診断してください。';}
    else if(name==='swift_syntax'){rank=3;label='Swift構文エラー';reason='該当するSwiftファイルと行番号を確認し、構文を修正してください。';}
    else {rank=4;label='回帰テストの失敗';reason='失敗したテストを確認し、関連する実装を修正してください。';}
    items.push({name,rank,label,reason,check});
  }
  return items.sort((a,b)=>a.rank-b.rank||a.name.localeCompare(b.name));
}
function focusPriority(name){
  const target=document.getElementById('check-'+name);
  if(!target)return false;
  for(const node of results.querySelectorAll('.priority-target'))node.classList.remove('priority-target');
  target.classList.add('priority-target');
  target.scrollIntoView({behavior:'smooth',block:'start'});
  target.setAttribute('tabindex','-1');target.focus({preventScroll:true});
  return true;
}
// Only local, non-sensitive fingerprints and checkmarks are stored in this browser.
const progressKey='hotel-shift-diagnostic-progress-v420';
function fingerprint(item){
  const check=item.check||{};
  const input=item.name+'|'+(check.status||'')+'|'+(check.stdout||'')+'|'+(check.stderr||'');
  let hash=2166136261;
  for(let i=0;i<input.length;i++){hash^=input.charCodeAt(i);hash=Math.imul(hash,16777619);}
  return item.name+':'+(hash>>>0).toString(16);
}
function readProgress(){
  try{const obj=JSON.parse(localStorage.getItem(progressKey)||'{}');return obj&&typeof obj==='object'&&!Array.isArray(obj)?obj:{};}
  catch(e){return {};}
}
function writeProgress(value){try{localStorage.setItem(progressKey,JSON.stringify(value));}catch(e){/* private mode / storage unavailable */}}
function addProgressTracker(section,items){
  if(!items.length)return;
  const saved=readProgress();
  const keys=items.map(fingerprint);
  // Drop resolved or changed failures; keep only matching current failures.
  const current={};for(const key of keys)if(saved[key]===true)current[key]=true;
  writeProgress(current);
  const panel=el('div',undefined,'progress-panel');
  panel.append(el('h3','対応状況（このブラウザに保存）'));
  panel.append(el('p','対応済みチェックはこのブラウザに保存されます。同じエラーは再診断後も保持され、解消・内容変更されたエラーのチェックは解除されます。チェックは診断結果を変更しません。','privacy'));
  const counter=el('p','','progress-counter');counter.setAttribute('role','status');
  const list=el('ul');const boxes=[];
  function refresh(){
    const done=boxes.filter(x=>x.checked).length;
    counter.textContent='対応済み '+done+' / '+items.length+'件 ・ 未対応 '+(items.length-done)+'件';
    for(const box of boxes)box.parentElement.classList.toggle('progress-done',box.checked);
  }
  function save(){const state={};boxes.forEach((box,i)=>{if(box.checked)state[keys[i]]=true;});writeProgress(state);refresh();}
  for(const [index,item] of items.entries()){
    const li=el('li');const label=el('label');
    const checkbox=el('input');checkbox.type='checkbox';checkbox.checked=current[keys[index]]===true;
    checkbox.setAttribute('aria-label',item.label+'（'+item.name+'）を対応済みにする');
    checkbox.addEventListener('change',save);boxes.push(checkbox);
    label.append(checkbox,el('strong',' '+item.label+'（'+item.name+'）'));li.append(label);list.append(li);
  }
  const reset=el('button','チェックをすべて解除');reset.type='button';
  reset.addEventListener('click',()=>{for(const box of boxes)box.checked=false;save();});
  panel.append(counter,list,reset);section.append(panel);refresh();
}
// Store only check identifiers, statuses and non-reversible fingerprints, never logs.
const comparisonKey='hotel-shift-diagnostic-comparison-v421';
function readComparison(){
  try{const value=JSON.parse(localStorage.getItem(comparisonKey)||'null');
    return value&&typeof value==='object'&&!Array.isArray(value)&&value.version===1&&value.checks&&typeof value.checks==='object'&&!Array.isArray(value.checks)?value.checks:null;
  }catch(e){return null;}
}
function comparisonSnapshot(data){
  const snapshot={};
  const checks=data&&data.checks&&typeof data.checks==='object'?data.checks:{};
  for(const [name,check] of Object.entries(checks)){
    if(!check||typeof check!=='object')continue;
    const failed=check.status!=='passed';
    snapshot[name]={failed,fingerprint:failed?fingerprint({name,check}):null};
  }
  return snapshot;
}
function addComparisonSection(data){
  const previous=readComparison(),current=comparisonSnapshot(data);
  const section=el('section');section.className='comparison';section.append(el('h2','前回との診断比較'));
  if(previous===null){section.append(el('p','初回診断です。次回の診断から、新規・継続・解消したエラーを比較できます。','muted'));}
  else {
    const newIssues=[],ongoing=[],resolved=[];
    for(const [name,now] of Object.entries(current)){
      const before=Object.prototype.hasOwnProperty.call(previous,name)?previous[name]:null;
      if(now.failed){
        if(before&&before.failed&&before.fingerprint===now.fingerprint)ongoing.push(name);
        else newIssues.push(name);
      }else if(before&&before.failed)resolved.push(name);
    }
    // Missing checks are not treated as resolved: they may not have run.
    const summary=el('p','新規・内容変更 '+newIssues.length+'件 ／ 継続 '+ongoing.length+'件 ／ 解消 '+resolved.length+'件','comparison-summary');
    summary.setAttribute('role','status');section.append(summary);
    for(const [heading,names] of [['新規・内容変更',newIssues],['継続',ongoing],['解消',resolved]]){
      const group=el('div',undefined,'comparison-group');group.append(el('h3',heading+'（'+names.length+'件）'));
      if(!names.length)group.append(el('p','該当なし','muted'));
      else {const list=el('ul');for(const name of names){const li=el('li');li.append(el('span',name));
        const go=el('button','診断結果へ移動');go.type='button';go.addEventListener('click',()=>focusPriority(name));li.append(go);list.append(li);}group.append(list);}
      section.append(group);
    }
    section.append(el('p','同じ項目でもエラーログの内容が変わった場合は「新規・内容変更」に分類します。実行されなかった項目は解消と判定しません。','privacy'));
  }
  try{localStorage.setItem(comparisonKey,JSON.stringify({version:1,checks:current}));}catch(e){/* storage unavailable */}
  results.prepend(section);
}
// FIXED422: bounded browser-only history. Never persist diagnostic logs.
const historyKey='hotel-shift-diagnostic-history-v422';
function readHistory(){
  try{
    const value=JSON.parse(localStorage.getItem(historyKey)||'[]');
    if(!Array.isArray(value))return [];
    return value.filter(x=>x&&typeof x==='object'&&typeof x.at==='string'&&x.checks&&typeof x.checks==='object'&&!Array.isArray(x.checks)).slice(-20);
  }catch(e){return [];}
}
function historyDifference(before,current){
  const changes={newIssues:[],ongoing:[],resolved:[]};
  for(const [name,now] of Object.entries(current)){
    const old=before&&Object.prototype.hasOwnProperty.call(before,name)?before[name]:null;
    if(now.failed){
      if(old&&old.failed&&old.fingerprint===now.fingerprint)changes.ongoing.push(name);
      else changes.newIssues.push(name);
    }else if(old&&old.failed)changes.resolved.push(name);
  }
  return changes; // Unexecuted checks are not counted as resolved.
}
// FIXED423: export only the bounded, privacy-preserving snapshots as Excel-compatible CSV.
function csvCell(value){
  let s=String(value??'');
  // Prevent spreadsheet formula evaluation when a name or date comes from malformed storage.
  if(/^[\s]*[=+@-]/.test(s))s="'"+s;
  return '"'+s.replace(/"/g,'""')+'"';
}
function historyCsv(entries){return historyCsvSelected(entries,null);}
function historyCsvSelected(entries,selectedIndices){
  const rows=[['診断日時','検査項目','結果','新規・内容変更','継続','解消']];
  for(let i=0;i<entries.length;i++){
    if(selectedIndices!==null&&!selectedIndices.includes(i))continue;
    const item=entries[i],prior=i+1<entries.length?entries[i+1].checks:null;
    const delta=prior?historyDifference(prior,item.checks):null;
    for(const [name,check] of Object.entries(item.checks)){
      if(!check||typeof check!=='object')continue;
      const category=delta?(delta.newIssues.includes(name)?'新規・内容変更':delta.ongoing.includes(name)?'継続':delta.resolved.includes(name)?'解消':'変化なし'):'比較元なし';
      rows.push([item.at,name,check.failed?'要確認':'正常',category,delta?delta.ongoing.length:'',delta?delta.resolved.length:'']);
    }
  }
  return '\uFEFF'+rows.map(row=>row.map(csvCell).join(',')).join('\r\n')+'\r\n';
}
function exportHistoryCsv(selectedIndices=null){
  const entries=readHistory();
  if(!entries.length)return false;
  if(selectedIndices!==null&&!selectedIndices.length)return false;
  const blob=new Blob([selectedIndices===null?historyCsv(entries):historyCsvSelected(entries,selectedIndices)],{type:'text/csv;charset=utf-8'});
  const url=URL.createObjectURL(blob);
  try{
    const link=document.createElement('a');link.href=url;
    link.download='HOTEL_SHIFT_診断履歴_'+(selectedIndices===null?'全件_':'検索結果_')+new Date().toISOString().slice(0,10)+'.csv';
    document.body.append(link);link.click();link.remove();
  }finally{URL.revokeObjectURL(url);}
  return true;
}
// FIXED427: SVG chart of failure counts, oldest to newest; no external libraries.
// Read only sanitized history snapshots, not diagnostic log text.
function historyFailureCount(entry){
  return Object.values(entry.checks||{}).filter(check=>check&&check.failed===true).length;
}
// FIXED428: compare the last two *visible* runs, matching the filtered chart.
// Counts measure failed checks, not severity or a guarantee that the app builds.
function historyTrend(entries){
  if(entries.length<2)return {kind:'insufficient',difference:0};
  const latest=historyFailureCount(entries[0]);
  const previous=historyFailureCount(entries[1]);
  const difference=latest-previous;
  return {kind:difference<0?'improved':difference>0?'worsened':'unchanged',difference,latest,previous};
}
function renderHistoryTrend(container,entries){
  const trend=historyTrend(entries);
  const labels={improved:'改善',worsened:'悪化',unchanged:'変化なし',insufficient:'比較データ不足'};
  const line=el('p',undefined,'history-trend');
  line.dataset.trend=trend.kind;
  if(trend.kind==='insufficient')line.textContent='前回との比較：比較には表示中の診断履歴が2回以上必要です。';
  else line.textContent='前回との比較：'+labels[trend.kind]+'（'+trend.previous+'件 → '+trend.latest+'件、'+(trend.difference>0?'+':'')+trend.difference+'件）';
  container.append(line);
  container.append(el('p','※ 現在の検索・絞り込み条件で表示中の直近2回を比較しています。エラー件数のみの判定です。','history-count'));
}
// FIXED429: summarize up to five most recent visible runs (not hidden history).
function historyRecentSummary(entries){
  const recent=entries.slice(0,5);
  if(recent.length<2)return {kind:'insufficient',runs:recent.length};
  const counts=recent.map(historyFailureCount);
  let improved=0,worsened=0,unchanged=0;
  for(let i=0;i<counts.length-1;i++){
    if(counts[i]<counts[i+1])improved++;
    else if(counts[i]>counts[i+1])worsened++;
    else unchanged++;
  }
  const difference=counts[0]-counts[counts.length-1];
  return {kind:difference<0?'improved':difference>0?'worsened':'unchanged',runs:counts.length,
    first:counts[counts.length-1],latest:counts[0],difference,improved,worsened,unchanged};
}
// FIXED430: percentage improvement relative to the oldest visible run in the recent window.
// A zero baseline cannot be used as a denominator: show a clear nonnumeric result.
function historyImprovementRate(entries){
  const summary=historyRecentSummary(entries);
  if(summary.kind==='insufficient')return {kind:'insufficient',runs:summary.runs};
  if(summary.first===0){
    return {kind:summary.latest===0?'zero-stable':'zero-baseline',first:0,latest:summary.latest};
  }
  const percentage=(summary.first-summary.latest)/summary.first*100;
  return {kind:'rate',percentage,first:summary.first,latest:summary.latest};
}
function renderHistoryImprovementRate(container,entries){
  const rate=historyImprovementRate(entries);
  const line=el('p',undefined,'history-rate');
  if(rate.kind==='insufficient')line.textContent='改善率：比較には診断履歴が2回以上必要です。';
  else if(rate.kind==='zero-stable')line.textContent='改善率：0%（最初も最新もエラー0件）';
  else if(rate.kind==='zero-baseline')line.textContent='改善率：算出不可（最初のエラーが0件、最新 '+rate.latest+'件）';
  else line.textContent='改善率：'+rate.percentage.toFixed(1)+'%（'+rate.first+'件 → '+rate.latest+'件）';
  container.append(line);
}
function renderHistoryRecentSummary(container,entries){
  const summary=historyRecentSummary(entries);
  const line=el('div',undefined,'history-recent');
  line.append(el('h3','直近の改善状況（最大5回）'));
  if(summary.kind==='insufficient')line.append(el('p','集計には表示中の診断履歴が2回以上必要です。'));
  else {
    const label={improved:'改善',worsened:'悪化',unchanged:'変化なし'}[summary.kind];
    const outcome=el('p',label+'：'+summary.first+'件 → '+summary.latest+'件（'+(summary.difference>0?'+':'')+summary.difference+'件）','history-trend');
    outcome.dataset.trend=summary.kind;line.append(outcome);
    line.append(el('p',summary.runs+'回の診断 ／ 改善 '+summary.improved+'回・悪化 '+summary.worsened+'回・変化なし '+summary.unchanged+'回','history-count'));
  }
  renderHistoryImprovementRate(line,entries);
  line.append(el('p','※ 検索・絞り込み後の直近最大5回を比較します。改善率は最古のエラー件数を基準に算出し、重大度は考慮しません。','history-count'));
  container.append(line);
}
function renderHistoryChart(container,entries,onNavigate){
  const onReady=arguments[3];
  container.replaceChildren();
  container.append(el('h3','エラー件数の推移（古い順 → 新しい順）'));
  if(!entries.length){container.append(el('p','表示できる診断履歴がありません。','chart-empty'));return;}
  const ns='http://www.w3.org/2000/svg';
  const svg=document.createElementNS(ns,'svg');
  svg.setAttribute('viewBox','0 0 640 210');svg.setAttribute('role','img');
  svg.setAttribute('aria-label','診断履歴 '+entries.length+'回のエラー件数の推移');
  const title=document.createElementNS(ns,'title');title.textContent='診断ごとのエラー件数';svg.append(title);
  const chronological=entries.slice().reverse();
  const counts=entries.slice().reverse().map(historyFailureCount);
  const max=Math.max(1,...counts),left=48,right=610,top=18,bottom=168;
  function node(tag,attrs,text){const n=document.createElementNS(ns,tag);for(const [k,v] of Object.entries(attrs))n.setAttribute(k,String(v));if(text!==undefined)n.textContent=text;svg.append(n);return n;}
  const x=i=>counts.length===1?(left+right)/2:left+(right-left)*i/(counts.length-1);
  const y=value=>bottom-(bottom-top)*value/max;
  node('line',{x1:left,y1:bottom,x2:right,y2:bottom,class:'chart-axis'});
  node('line',{x1:left,y1:top,x2:left,y2:bottom,class:'chart-axis'});
  node('text',{x:8,y:bottom+4,class:'chart-label'},'0');
  node('text',{x:8,y:top+4,class:'chart-label'},String(max));
  if(counts.length>1)node('polyline',{points:counts.map((v,i)=>x(i)+','+y(v)).join(' '),class:'chart-line'});
  // FIXED432: select a point to see its failure count and change from the prior run.
  // Only sanitized history snapshots are used; no log text is exposed.
  const pointDetail=el('p','グラフの点を選ぶと、エラー件数と前回からの増減を表示します。','chart-point-detail');
  const dots=[];
  // FIXED435: compare the selected run with its immediate visible neighbors.
  const neighborDetail=el('div',undefined,'chart-neighbor-detail');
  // FIXED437: copy only the selected run's sanitized summary (never raw logs).
  function selectedHistoryCopyText(i){
    if(!Number.isInteger(i)||i<0||i>=counts.length)return '';
    const current=counts[i],previous=i>0?counts[i-1]:null;
    const difference=previous===null?null:current-previous;
    const change=difference===null?'前回比較：対象なし':
      '前回比較：'+(difference<0?'改善':difference>0?'悪化':'変化なし')+
      '（'+previous+'件 → '+current+'件、'+(difference>0?'+':'')+difference+'件）';
    return ['HOTEL SHIFT 診断履歴（選択した1回分）',
      '診断日時：'+chronological[i].at,
      'エラー件数：'+current+'件',change,
      '表示中の診断：古い順 '+(i+1)+' / '+counts.length+'回',
      '※ ブラウザ内の保存済み集計情報です。診断ログ全文は含みません。'].join('\n');
  }
  // FIXED438: a ready-to-paste consultation request, limited to the selected saved summary.
  function selectedHistoryConsultationText(i){
    const summary=selectedHistoryCopyText(i);
    if(!summary)return '';
    return ['HOTEL SHIFT の診断履歴について相談します。',
      '以下は保存済みの集計情報であり、実際のエラーログやソースコードは含まれていません。',
      'エラー件数の増減から断定せず、考えられる確認手順を優先順に教えてください。',
      '原因特定に必要なログやファイルがあれば、何を共有すべきか具体的に教えてください。',
      '',summary,'',
      '希望する回答：①状況の整理 ②追加で確認すべき情報 ③Mac/Xcodeでの安全な確認手順。',
      '未確認の原因や修正完了を断定しないでください。'].join('\n');
  }
  // FIXED439: compare and copy multiple explicitly selected visible history runs.
  // Selection is local to the currently filtered chart and never changes stored history.
  const comparisonIndices=new Set();
  const comparisonPanel=el('div',undefined,'chart-multi-comparison');
  const comparisonTitle=el('h4','複数の診断を比較');
  const comparisonStatus=el('p','比較する診断を2件以上選択してください。','history-count');
  const comparisonList=el('div',undefined,'chart-multi-list');
  const comparisonControls=el('div',undefined,'chart-point-nav');
  const comparisonCopy=el('button','選択した診断の比較をコピー','chart-multi-copy');
  comparisonCopy.type='button';comparisonCopy.disabled=true;
  const comparisonClear=el('button','比較の選択を解除','chart-multi-clear');
  comparisonClear.type='button';comparisonClear.disabled=true;
  const comparisonFeedback=el('span','','copy-status');comparisonFeedback.setAttribute('role','status');
  function comparisonSelectionText(){
    const indices=Array.from(comparisonIndices).sort((a,b)=>a-b);
    if(indices.length<2)return '';
    const first=counts[indices[0]],last=counts[indices[indices.length-1]],difference=last-first;
    const lines=['HOTEL SHIFT 診断履歴（選択した'+indices.length+'回の比較）'];
    for(const i of indices)lines.push('古い順 '+(i+1)+'回目：'+chronological[i].at+' ／ エラー '+counts[i]+'件');
    lines.push('最初と最後：'+first+'件 → '+last+'件（'+(difference>0?'+':'')+difference+'件）');
    lines.push('※ 表示中の履歴から選択した集計情報です。診断ログ全文は含みません。');
    return lines.join('\n');
  }
  // FIXED440: compose a privacy-conscious ChatGPT consultation from selected summaries.
  function comparisonConsultationText(){
    const summary=comparisonSelectionText();
    if(!summary)return '';
    return ['HOTEL SHIFT の複数回の診断履歴を比較して相談します。',
      '以下は診断履歴の集計情報のみです。実際のエラーログやソースコードは含まれていません。',
      '件数の変化だけで原因・解決を断定しないでください。',
      '',summary,'',
      '次の順で回答してください。',
      '1. 選択した診断の時系列変化と増減の整理',
      '2. 追加で確認すべき診断ログ・Swiftファイル・Xcode設定',
      '3. Macで安全に実施できる確認手順と修正の優先順位',
      '4. 再診断時に何を比較すればよいか',
      '必要な情報が不足している場合は、推測で修正済みと判断せず質問してください。'].join('\n');
  }
  // FIXED441: export only explicitly selected, visible history summaries.
  // CSV rows are chronological and include the difference from the prior selected run.
  function comparisonSelectionCsv(){
    const indices=Array.from(comparisonIndices).sort((a,b)=>a-b);
    if(indices.length<2)return '';
    const rows=[['診断順','診断日時','エラー件数','前の選択診断との差','判定']];
    for(let j=0;j<indices.length;j++){
      const i=indices[j],previous=j?counts[indices[j-1]]:null;
      const delta=previous===null?null:counts[i]-previous;
      rows.push([i+1,chronological[i].at,counts[i],delta===null?'':(delta>0?'+':'')+delta,
        delta===null?'比較元なし':delta<0?'改善':delta>0?'悪化':'変化なし']);
    }
    return '\uFEFF'+rows.map(row=>row.map(csvCell).join(',')).join('\r\n')+'\r\n';
  }
  function exportComparisonCsv(){
    const csv=comparisonSelectionCsv();if(!csv)return false;
    const blob=new Blob([csv],{type:'text/csv;charset=utf-8'});
    const url=URL.createObjectURL(blob);
    try{
      const link=document.createElement('a');link.href=url;
      link.download='HOTEL_SHIFT_選択した診断の比較_'+new Date().toISOString().slice(0,10)+'.csv';
      document.body.append(link);link.click();link.remove();
    }finally{URL.revokeObjectURL(url);}
    return true;
  }
  // FIXED442: create a print-only report from selected, sanitized summaries.
  // Never put raw logs, source files or untrusted HTML into the report.
  function comparisonPrintReport(){
    const indices=Array.from(comparisonIndices).sort((a,b)=>a-b);
    if(indices.length<2)return false;
    let report=document.getElementById('comparison-print-report');
    if(!report){report=el('article');report.id='comparison-print-report';document.body.append(report);}
    report.replaceChildren();
    report.append(el('h1','HOTEL SHIFT 診断履歴 比較レポート'));
    report.append(el('p','対象：選択した'+indices.length+'回の診断（古い順）'));
    const table=el('table'),head=el('thead'),header=el('tr');
    for(const title of ['診断順','診断日時','エラー件数','前の選択診断との差','判定'])header.append(el('th',title));
    head.append(header);table.append(head);
    const body=el('tbody');
    for(let j=0;j<indices.length;j++){
      const i=indices[j],previous=j?counts[indices[j-1]]:null;
      const delta=previous===null?null:counts[i]-previous;
      const row=el('tr');
      for(const value of [String(i+1),String(chronological[i].at),counts[i]+'件',
        delta===null?'—':(delta>0?'+':'')+delta+'件',
        delta===null?'比較元なし':delta<0?'改善':delta>0?'悪化':'変化なし'])row.append(el('td',value));
      body.append(row);
    }
    table.append(body);report.append(table);
    // FIXED443: a self-contained SVG trend chart for the selected runs.
    // Use only bounded numeric summaries; never render raw logs or HTML.
    const chartTitle=el('h2','選択した診断のエラー件数推移');report.append(chartTitle);
    const chart=document.createElementNS('http://www.w3.org/2000/svg','svg');
    chart.setAttribute('viewBox','0 0 760 220');chart.setAttribute('role','img');
    chart.setAttribute('aria-label','選択した診断のエラー件数の推移');
    const svgNode=(tag,attributes,textValue)=>{
      const node=document.createElementNS('http://www.w3.org/2000/svg',tag);
      for(const [key,value] of Object.entries(attributes))node.setAttribute(key,String(value));
      if(textValue!==undefined)node.textContent=String(textValue);
      return node;
    };
    const maxCount=Math.max(1,...indices.map(i=>counts[i]));
    const xAt=j=>55+(650*j)/(indices.length-1);
    const yAt=value=>175-(125*value/maxCount);
    chart.append(svgNode('line',{x1:55,y1:175,x2:705,y2:175,stroke:'#777','stroke-width':1}));
    chart.append(svgNode('line',{x1:55,y1:45,x2:55,y2:175,stroke:'#777','stroke-width':1}));
    const coordinates=indices.map((i,j)=>xAt(j)+','+yAt(counts[i])).join(' ');
    chart.append(svgNode('polyline',{points:coordinates,fill:'none',stroke:'#224c8d','stroke-width':3,'stroke-linejoin':'round'}));
    for(let j=0;j<indices.length;j++){
      const i=indices[j],x=xAt(j),y=yAt(counts[i]);
      chart.append(svgNode('circle',{cx:x,cy:y,r:5,fill:'#224c8d'}));
      chart.append(svgNode('text',{x,y:y-12,'text-anchor':'middle','font-size':12,fill:'#17243a'},counts[i]+'件'));
      chart.append(svgNode('text',{x,y:198,'text-anchor':'middle','font-size':11,fill:'#58677e'},(i+1)+'回目'));
    }
    report.append(chart);
    const first=counts[indices[0]],last=counts[indices[indices.length-1]],difference=last-first;
    report.append(el('p','最初と最後：'+first+'件 → '+last+'件（'+(difference>0?'+':'')+difference+'件）'));
    // FIXED444: show a bounded count-based improvement rate and overall direction.
    // A zero baseline cannot support a percentage reduction if errors later appear.
    const overall= difference<0?'改善':difference>0?'悪化':'変化なし';
    let improvementRate;
    if(first===0){
      improvementRate=last===0?'0.0%（両方とも0件）':'算出不可（比較元が0件）';
    }else{
      improvementRate=((first-last)/first*100).toFixed(1)+'%';
    }
    const summary=el('section',undefined,'print-comparison-summary');
    summary.append(el('h2','改善率・総合判定'));
    summary.append(el('p','エラー件数の改善率：'+improvementRate));
    summary.append(el('p','総合判定：'+overall+'（'+first+'件 → '+last+'件、'+(difference>0?'+':'')+difference+'件）'));
    summary.append(el('p','※ 選択した最古と最新の診断を比較。件数のみの判定であり、エラーの重大度・修正完了・ビルド成功を保証しません。'));
    report.append(summary);

    report.append(el('p','※ 診断履歴の集計値のみを表示。エラーの重大度やビルド成功を示すものではありません。'));
    return true;
  }
  const comparisonPrint=el('button','選択した診断の比較を印刷','chart-multi-print');
  comparisonPrint.type='button';comparisonPrint.disabled=true;
  comparisonPrint.addEventListener('click',()=>{
    if(!comparisonPrintReport())return;
    comparisonFeedback.textContent='比較レポートの印刷画面を開きます。';
    window.print();
  });
  const comparisonCsv=el('button','選択した診断の比較をCSV出力','chart-multi-csv');
  comparisonCsv.type='button';comparisonCsv.disabled=true;
  comparisonCsv.addEventListener('click',()=>{
    if(!exportComparisonCsv())return;
    comparisonFeedback.textContent='選択した診断の比較CSVを出力しました。';
  });
  const comparisonConsult=el('button','選択した診断をChatGPTに相談する文章をコピー','chart-multi-consult');
  comparisonConsult.type='button';comparisonConsult.disabled=true;
  // FIXED445: a live preview of the same count-based summary used in printing.
  // A zero baseline is not used as a divisor, and two different runs are required.
  const comparisonSummaryPreview=el('section',undefined,'chart-multi-summary');
  comparisonSummaryPreview.setAttribute('aria-live','polite');
  function updateComparisonSummaryPreview(indices){
    comparisonSummaryPreview.replaceChildren();
    comparisonSummaryPreview.append(el('h4','印刷前の改善率・総合判定'));
    if(indices.length<2){
      comparisonSummaryPreview.append(el('p','診断を2件以上選択すると改善率と総合判定を確認できます。'));
      return;
    }
    const first=counts[indices[0]],last=counts[indices[indices.length-1]];
    const difference=last-first;
    const overall=difference<0?'改善':difference>0?'悪化':'変化なし';
    const rate=first===0?(last===0?'0.0%（両方とも0件）':'算出不可（比較元が0件）'):
      ((first-last)/first*100).toFixed(1)+'%';
    const direction=difference<0?'improved':difference>0?'worsened':'unchanged';
    const detail=el('p','改善率：'+rate+' ／ 総合判定：'+overall+'（'+first+'件 → '+last+'件、'+(difference>0?'+':'')+difference+'件）','history-trend');
    detail.setAttribute('data-trend',direction);
    comparisonSummaryPreview.append(detail);
    comparisonSummaryPreview.append(el('p','※ 選択した最古と最新の診断を比較。件数のみの判定であり、エラーの重大度・修正完了・ビルド成功を保証しません。','history-count'));
  }
  // FIXED446: display the change at each selected diagnosis, not just endpoints.
  // Deltas always use the preceding SELECTED diagnosis in chronological order.
  const comparisonSteps=el('section',undefined,'chart-multi-steps');
  comparisonSteps.setAttribute('aria-live','polite');
  function updateComparisonSteps(indices){
    comparisonSteps.replaceChildren();
    comparisonSteps.append(el('h4','診断ごとのエラー増減'));
    if(indices.length<2){
      comparisonSteps.append(el('p','診断を2件以上選択すると、診断間の改善・悪化を一覧表示します。','history-count'));
      return;
    }
    const table=el('table');table.className='chart-steps-table';
    const head=el('thead'),header=el('tr');
    for(const label of ['診断日時','エラー件数','前の選択診断との差','判定'])header.append(el('th',label));
    head.append(header);table.append(head);
    const body=el('tbody');
    for(let j=0;j<indices.length;j++){
      const i=indices[j],previous=j>0?counts[indices[j-1]]:null;
      const difference=previous===null?null:counts[i]-previous;
      const outcome=difference===null?'比較元なし':difference<0?'改善':difference>0?'悪化':'変化なし';
      const row=el('tr');
      if(difference!==null)row.setAttribute('data-trend',difference<0?'improved':difference>0?'worsened':'unchanged');
      for(const value of [chronological[i].at,counts[i]+'件',difference===null?'—':(difference>0?'+':'')+difference+'件',outcome])row.append(el('td',value));
      body.append(row);
    }
    table.append(body);comparisonSteps.append(table);
    comparisonSteps.append(el('p','※ 前の選択診断との差です。選択していない診断は比較対象に含みません。','history-count'));
  }
  // FIXED447: aggregate transitions between consecutive selected diagnoses only.
  const comparisonTransitionTotals=el('section',undefined,'chart-multi-transition-totals');
  comparisonTransitionTotals.setAttribute('aria-live','polite');
  function updateComparisonTransitionTotals(indices){
    comparisonTransitionTotals.replaceChildren();
    comparisonTransitionTotals.append(el('h4','診断間の改善・悪化回数'));
    if(indices.length<2){
      comparisonTransitionTotals.append(el('p','診断を2件以上選択すると、改善・悪化・変化なしの回数を表示します。','history-count'));
      return;
    }
    let improved=0,worsened=0,unchanged=0;
    for(let j=1;j<indices.length;j++){
      const difference=counts[indices[j]]-counts[indices[j-1]];
      if(difference<0)improved++;
      else if(difference>0)worsened++;
      else unchanged++;
    }
    const totals=el('div',undefined,'chart-transition-counts');
    for(const [label,count,trend] of [
      ['改善した回数',improved,'improved'],
      ['悪化した回数',worsened,'worsened'],
      ['変化なしの回数',unchanged,'unchanged']
    ]){
      const item=el('p',label+'：'+count+'回');item.setAttribute('data-trend',trend);totals.append(item);
    }
    comparisonTransitionTotals.append(totals);
    // FIXED448: percentages are based on selected-to-selected intervals, not runs.
    // Calculate from the same counters as the displayed totals so they stay consistent.
    const intervalCount=indices.length-1;
    const percentageRows=el('div',undefined,'chart-transition-percentages');
    percentageRows.append(el('h5','改善・悪化・変化なしの割合'));
    for(const [label,count,trend] of [
      ['改善',improved,'improved'],
      ['悪化',worsened,'worsened'],
      ['変化なし',unchanged,'unchanged']
    ]){
      const percent=(count/intervalCount*100).toFixed(1);
      const item=el('p',label+'：'+percent+'%（'+count+' / '+intervalCount+'区間）');
      item.setAttribute('data-trend',trend);
      percentageRows.append(item);
    }
    comparisonTransitionTotals.append(percentageRows);
    // FIXED449: accessible, proportional stacked horizontal bar from the same counters.
    const bar=el('div',undefined,'chart-transition-bar');
    bar.setAttribute('role','img');
    bar.setAttribute('aria-label','診断間の変化割合：改善 '+(improved/intervalCount*100).toFixed(1)+'%、悪化 '+(worsened/intervalCount*100).toFixed(1)+'%、変化なし '+(unchanged/intervalCount*100).toFixed(1)+'%');
    const legend=el('div',undefined,'chart-transition-legend');
    for(const [label,count,trend] of [
      ['改善',improved,'improved'],['悪化',worsened,'worsened'],['変化なし',unchanged,'unchanged']
    ]){
      const segment=el('span',undefined,'chart-transition-segment');
      segment.setAttribute('data-trend',trend);
      segment.style.width=(count/intervalCount*100)+'%';
      segment.setAttribute('aria-hidden','true');
      bar.append(segment);
      const item=el('span',label+' '+(count/intervalCount*100).toFixed(1)+'%（'+count+'回）');
      item.setAttribute('data-trend',trend);legend.append(item);
    }
    comparisonTransitionTotals.append(bar,legend);

    comparisonTransitionTotals.append(el('p','比較区間：'+(indices.length-1)+'区間。前の選択診断との差のみを集計し、選択していない診断は含みません。','history-count'));
    comparisonTransitionTotals.append(el('p','※ 件数の増減だけを示します。原因の特定や修正完了を意味しません。','history-count'));
  }
  function updateComparison(){
    const indices=Array.from(comparisonIndices).sort((a,b)=>a-b);
    comparisonList.replaceChildren();
    updateComparisonSummaryPreview(indices);
    updateComparisonSteps(indices);
    updateComparisonTransitionTotals(indices);
    comparisonStatus.textContent='選択中：'+indices.length+'件'+(indices.length<2?'（比較には2件以上必要）':'');
    for(const i of indices)comparisonList.append(el('p','古い順 '+(i+1)+'回目：'+chronological[i].at+' ／ エラー '+counts[i]+'件'));
    if(indices.length>=2){
      const difference=counts[indices[indices.length-1]]-counts[indices[0]];
      comparisonList.append(el('p','最初と最後の増減：'+(difference>0?'+':'')+difference+'件','history-trend'));
    }
    comparisonCopy.disabled=indices.length<2;
    comparisonConsult.disabled=indices.length<2;
    comparisonCsv.disabled=indices.length<2;
    comparisonPrint.disabled=indices.length<2;
    comparisonClear.disabled=indices.length===0;
    comparisonFeedback.textContent='';
  }
  const comparisonChoices=el('div',undefined,'chart-multi-choices');
  for(let i=0;i<counts.length;i++){
    const label=el('label',undefined,'chart-multi-choice');
    const checkbox=el('input');checkbox.type='checkbox';
    checkbox.setAttribute('aria-label','古い順 '+(i+1)+'回目を比較に含める');
    checkbox.addEventListener('change',()=>{
      if(checkbox.checked)comparisonIndices.add(i);else comparisonIndices.delete(i);
      updateComparison();
    });
    label.append(checkbox,el('span',(i+1)+'回目（'+counts[i]+'件）'));comparisonChoices.append(label);
  }
  comparisonCopy.addEventListener('click',async()=>{
    const value=comparisonSelectionText();if(!value)return;
    try{await copyToClipboard(value);comparisonFeedback.textContent='選択した診断の比較をコピーしました。';}
    catch(e){comparisonFeedback.textContent='コピーできませんでした。ブラウザのコピー権限をご確認ください。';}
  });
  comparisonConsult.addEventListener('click',async()=>{
    const value=comparisonConsultationText();if(!value)return;
    try{await copyToClipboard(value);comparisonFeedback.textContent='複数の診断の相談文をコピーしました。ChatGPTに貼り付けてください。';}
    catch(e){comparisonFeedback.textContent='コピーできませんでした。ブラウザのコピー権限をご確認ください。';}
  });
  comparisonClear.addEventListener('click',()=>{
    comparisonIndices.clear();
    for(const label of comparisonChoices.children)label.firstChild.checked=false;
    updateComparison();
  });
  // Preserve prior comparisonCopy,comparisonConsult,comparisonClear controls; CSV is additional.
  comparisonControls.append(comparisonCopy,comparisonConsult,comparisonCsv,comparisonClear,comparisonFeedback);
  comparisonControls.append(comparisonPrint);
  // Keep the original panel append sequence for older diagnostics compatibility.
  comparisonPanel.append(comparisonTitle,comparisonChoices,comparisonStatus,comparisonList,comparisonSummaryPreview,comparisonControls);
  comparisonControls.before(comparisonSteps);
  comparisonControls.before(comparisonTransitionTotals);
  const copySelectedButton=el('button','選択した診断結果をコピー','chart-point-copy');
  copySelectedButton.type='button';copySelectedButton.disabled=true;
  const copySelectedStatus=el('span','','copy-status');copySelectedStatus.setAttribute('role','status');
  copySelectedButton.addEventListener('click',async()=>{
    if(selectedIndex<0)return;
    try{await copyToClipboard(selectedHistoryCopyText(selectedIndex));copySelectedStatus.textContent='選択した診断結果をコピーしました。';}
    catch(e){copySelectedStatus.textContent='コピーできませんでした。ブラウザのコピー権限をご確認ください。';}
  });
  const consultSelectedButton=el('button','選択した診断をChatGPTに相談する文章をコピー','chart-point-consult');
  consultSelectedButton.type='button';consultSelectedButton.disabled=true;
  const consultSelectedStatus=el('span','','copy-status');consultSelectedStatus.setAttribute('role','status');
  consultSelectedButton.addEventListener('click',async()=>{
    if(selectedIndex<0)return;
    try{await copyToClipboard(selectedHistoryConsultationText(selectedIndex));consultSelectedStatus.textContent='相談用の文章をコピーしました。ChatGPTに貼り付けてください。';}
    catch(e){consultSelectedStatus.textContent='コピーできませんでした。ブラウザのコピー権限をご確認ください。';}
  });
  const jumpButton=el('button','選択した診断の履歴へ移動','chart-jump');
  jumpButton.type='button';jumpButton.hidden=true;
  let selectedEntry=null;
  // FIXED436: adjacent-run navigation uses the same point selection path as clicks.
  let selectedIndex=-1;
  const pointNav=el('div',undefined,'chart-point-nav');
  const previousButton=el('button','前の診断へ','chart-point-prev');
  const nextButton=el('button','次の診断へ','chart-point-next');
  previousButton.type='button';nextButton.type='button';
  previousButton.disabled=true;nextButton.disabled=true;
  previousButton.addEventListener('click',()=>{if(selectedIndex>0)selectHistoryPoint(selectedIndex-1);});
  nextButton.addEventListener('click',()=>{if(selectedIndex>=0&&selectedIndex<counts.length-1)selectHistoryPoint(selectedIndex+1);});
  pointNav.append(previousButton,nextButton,copySelectedButton,copySelectedStatus);
  pointNav.append(consultSelectedButton,consultSelectedStatus);
  jumpButton.addEventListener('click',()=>{if(selectedEntry&&typeof onNavigate==='function')onNavigate(selectedEntry);});
  function selectHistoryPoint(i){
    if(!Number.isInteger(i)||i<0||i>=counts.length)return;
    selectedIndex=i;
    copySelectedButton.disabled=false;copySelectedStatus.textContent='';
    consultSelectedButton.disabled=false;consultSelectedStatus.textContent='';
    previousButton.disabled=i===0;
    nextButton.disabled=i===counts.length-1;
    dots.forEach((dot,j)=>dot.classList.toggle('chart-selected',i===j));
    const current=counts[i],previous=i>0?counts[i-1]:null;
    const difference=previous===null?null:current-previous;
    const change=previous===null?'最初の診断（比較対象なし）':
      difference<0?'改善 '+Math.abs(difference)+'件減少':
      difference>0?'悪化 '+difference+'件増加':'変化なし（±0件）';
    pointDetail.textContent='古い順 '+(i+1)+'回目 ／ '+chronological[i].at+' ／ エラー '+current+'件 ／ '+change;
    selectedEntry=chronological[i];jumpButton.hidden=false;
    neighborDetail.replaceChildren();
    neighborDetail.append(el('h4','選択した診断の前後を比較'));
    function neighborLine(label,index){
      if(index<0||index>=counts.length){neighborDetail.append(el('p',label+'：比較対象なし','muted'));return;}
      const diff=counts[index]-current;
      const description=diff===0?'同じ（±0件）':diff>0?'選択時点より '+diff+'件多い':'選択時点より '+Math.abs(diff)+'件少ない';
      neighborDetail.append(el('p',label+'：'+chronological[index].at+' ／ エラー '+counts[index]+'件 ／ '+description));
    }
    neighborLine('前の診断',i-1);
    neighborDetail.append(el('p','選択中：'+chronological[i].at+' ／ エラー '+current+'件','chart-neighbor-current'));
    neighborLine('次の診断',i+1);
  }
  for(let i=0;i<counts.length;i++){
    const dot=node('circle',{cx:x(i),cy:y(counts[i]),r:7,class:'chart-dot',tabindex:0,role:'button','aria-label':'古い順 '+(i+1)+'回目の診断詳細'});
    dots.push(dot);
    const tip=document.createElementNS(ns,'title');tip.textContent='古い順 '+(i+1)+'回目：要確認 '+counts[i]+'件';dot.append(tip);
    dot.addEventListener('click',()=>selectHistoryPoint(i));
    dot.addEventListener('keydown',event=>{if(event.key==='Enter'||event.key===' '){event.preventDefault();selectHistoryPoint(i);}});
  }
  node('text',{x:left,y:195,class:'chart-label'},'古い');
  node('text',{x:right,y:195,'text-anchor':'end',class:'chart-label'},'新しい');
  // FIXED431: display the recent (up to five visible runs) improvement rate on the chart.
  // Keep zero-baseline and insufficient cases explicit rather than inventing a percentage.
  const chartRate=historyImprovementRate(entries);
  const chartRateText=chartRate.kind==='rate'?'直近の改善率 '+chartRate.percentage.toFixed(1)+'%':
    chartRate.kind==='zero-stable'?'直近の改善率 0%':
    chartRate.kind==='zero-baseline'?'直近の改善率 算出不可':'直近の改善率 比較データ不足';
  node('rect',{x:365,y:22,width:245,height:34,rx:9,class:'chart-rate-bg'});
  node('text',{x:600,y:44,'text-anchor':'end',class:'chart-rate'},chartRateText);
  // FIXED434: expose a safe, entry-identity based selection method to history details.
  if(typeof onReady==='function')onReady(entry=>{
    const index=chronological.indexOf(entry);
    if(index<0)return false;
    selectHistoryPoint(index);
    return true;
  });
  container.append(svg,pointDetail,pointNav,neighborDetail,jumpButton,comparisonPanel);
  renderHistoryTrend(container,entries);
  renderHistoryRecentSummary(container,entries);
  container.append(el('p','対象 '+counts.length+'回 ／ 最古 '+counts[0]+'件 → 最新 '+counts[counts.length-1]+'件（最大 '+Math.max(...counts)+'件）','history-count'));
}
function addHistorySection(data){
  const current=comparisonSnapshot(data);
  const history=readHistory();
  const previous=history.length?history[0].checks:null;
  const changes=previous?historyDifference(previous,current):null;
  const entry={at:new Date().toISOString(),checks:current};
  const updated=[entry,...history].slice(0,20);
  try{localStorage.setItem(historyKey,JSON.stringify(updated));}catch(e){/* storage unavailable */}
  const section=el('section');section.className='history';section.append(el('h2','診断履歴（最新20回）'));
  section.append(el('p','診断日時・検査項目の状態・匿名の照合用情報だけをこのブラウザに保存します。ログ本文は保存しません。','privacy'));
  // FIXED424: view-only filtering; preserve all snapshots and CSV export.
  const filterBar=el('div',undefined,'history-filter');
  const filterCount=el('p',undefined,'history-count');
  const list=el('ol',undefined,'history-list');
  const chart=el('div',undefined,'history-chart');
  let selectChartEntry=null;
  const filterButtons=[];
  let historyFilter='all';
  // FIXED425: local, case-insensitive search; never mutate saved history.
  const historySearch=el('input');historySearch.type='search';
  historySearch.placeholder='診断日時・検査項目名で検索';
  historySearch.setAttribute('aria-label','診断履歴を検索');
  historySearch.autocomplete='off';
  historySearch.addEventListener('input',applyHistoryFilter);
  function applyHistoryFilter(){
    let visible=0;
    for(const item of list.children){
      const matchesStatus=historyFilter==='all'||(historyFilter==='issues'?item.dataset.hasIssues==='true':item.dataset.hasIssues==='false');
      const query=historySearch.value.trim().toLocaleLowerCase('ja-JP');
      const matchesSearch=!query||item.dataset.searchText.includes(query);
      const match=matchesStatus&&matchesSearch;
      item.hidden=!match;
      if(match)visible++;
    }
    filterCount.textContent='表示中：'+visible+'件 ／ 保存済み：'+updated.length+'件';
    const visibleEntries=Array.from(list.children).filter(item=>!item.hidden&&item.dataset.historyIndex!==undefined).map(item=>updated[Number(item.dataset.historyIndex)]);
    // FIXED427 compatibility: renderHistoryChart(chart,visibleEntries) with navigation callback added.
    renderHistoryChart(chart,visibleEntries,entry=>{
      // Resolve by object identity, not by date or visible index: duplicate timestamps
      // and filtered lists must still navigate to the exact saved history row.
      const index=updated.indexOf(entry);
      if(index<0)return;
      const target=Array.from(list.children).find(item=>item.dataset.historyIndex===String(index)&&!item.hidden);
      if(!target)return;
      const details=target.querySelector('details');
      if(details)details.open=true;
      target.scrollIntoView({behavior:'smooth',block:'center'});
      if(details){const summary=details.querySelector('summary');if(summary){summary.setAttribute('tabindex','-1');summary.focus({preventScroll:true});}}
      target.classList.add('history-jump-target');
      for(const other of list.children){if(other!==target)other.classList.remove('history-jump-target');}
    },select=>{selectChartEntry=select;});
    for(const [mode,button] of filterButtons)button.setAttribute('aria-pressed',String(mode===historyFilter));
  }
  for(const [mode,label] of [['all','すべて'],['issues','エラーあり'],['passed','正常のみ']]){
    const control=el('button',label);control.type='button';
    control.addEventListener('click',()=>{historyFilter=mode;applyHistoryFilter();});
    filterButtons.push([mode,control]);filterBar.append(control);
  }
  section.append(filterBar,historySearch,filterCount,chart);
  for(let i=0;i<updated.length;i++){
    const item=updated[i];const prior=i+1<updated.length?updated[i+1].checks:null;
    const delta=prior?historyDifference(prior,item.checks):i===0?changes:null;
    const failures=Object.values(item.checks).filter(x=>x&&x.failed).length;
    const li=el('li');li.dataset.historyIndex=String(i);li.dataset.hasIssues=String(failures>0);const details=el('details');
    const when=new Date(item.at);const label=Number.isNaN(when.getTime())?item.at:when.toLocaleString('ja-JP');
    li.dataset.searchText=(label+' '+item.at+' '+Object.keys(item.checks).join(' ')).toLocaleLowerCase('ja-JP');
    details.append(el('summary',label+' ／ 要確認 '+failures+'件'));
    if(delta){
      details.append(el('p','新規・内容変更 '+delta.newIssues.length+'件 ／ 継続 '+delta.ongoing.length+'件 ／ 解消 '+delta.resolved.length+'件'));
      for(const [heading,names] of [['新規・内容変更',delta.newIssues],['継続',delta.ongoing],['解消',delta.resolved]]){
        details.append(el('p',heading+'：'+(names.length?names.join('、'):'なし'),'muted'));
      }
    }else details.append(el('p','比較元の履歴はありません。','muted'));
    // FIXED434: navigate back to this exact history point without changing filters.
    const returnButton=el('button','この診断をグラフで表示','history-return-chart');
    returnButton.type='button';
    returnButton.addEventListener('click',()=>{
      if(typeof selectChartEntry!=='function'||!selectChartEntry(item))return;
      chart.scrollIntoView({behavior:'smooth',block:'center'});
      chart.classList.add('history-chart-return');
      for(const other of list.children)other.classList.remove('history-jump-target');
      const selected=chart.querySelector('.chart-selected');
      if(selected)selected.focus({preventScroll:true});
    });
    details.append(returnButton);
    li.append(details);list.append(li);
  }
  section.append(list);applyHistoryFilter();
  const exportButton=el('button','診断履歴をCSV出力','csv-export');exportButton.type='button';
  exportButton.addEventListener('click',()=>{if(!exportHistoryCsv())exportButton.textContent='出力できる履歴がありません';});
  section.append(exportButton);
  // FIXED426: export only the visible results, without changing saved history.
  // Preserve original indices so comparison categories still use the actual preceding run.
  const filteredExport=el('button','表示中の履歴をCSV出力','csv-export');filteredExport.type='button';
  filteredExport.addEventListener('click',()=>{
    const selected=Array.from(list.children).filter(item=>!item.hidden&&item.dataset.historyIndex!==undefined).map(item=>Number(item.dataset.historyIndex));
    if(!exportHistoryCsv(selected))filteredExport.textContent='出力対象の履歴がありません';
  });
  section.append(filteredExport);
  const clear=el('button','診断履歴を削除');clear.type='button';
  clear.addEventListener('click',()=>{
    if(!window.confirm('このブラウザに保存した診断履歴を削除しますか？'))return;
    try{localStorage.removeItem(historyKey);}catch(e){/* storage unavailable */}
    list.replaceChildren();list.append(el('li','履歴を削除しました。'));historySearch.remove();filterBar.remove();filterCount.remove();chart.remove();exportButton.disabled=true;filteredExport.disabled=true;
  });
  section.append(clear);results.prepend(section);
}
function addPrioritySection(data){
  const items=priorityItems(data);
  const section=el('section');section.className='priority';section.append(el('h2','修正する優先順位'));
  if(!items.length){writeProgress({});section.append(el('p','確認が必要な項目はありません。前回の対応済みチェックも整理しました。','ok'));results.prepend(section);return;}
  section.append(el('p','複数の問題がある場合は、上から順番に確認してください。これはログからの推定であり、自動修正ではありません。','muted'));
  const list=el('ol');
  let selected=-1;
  const nav=el('div',undefined,'priority-nav');
  const prev=el('button','前の問題へ');prev.type='button';
  const next=el('button','次の問題へ');next.type='button';
  const position=el('span','問題 '+items.length+'件','priority-position');position.setAttribute('role','status');
  function jump(index){
    if(!items.length)return;
    selected=(index+items.length)%items.length;
    if(focusPriority(items[selected].name))position.textContent='確認中 '+(selected+1)+' / '+items.length+'件';
  }
  prev.addEventListener('click',()=>jump(selected<0?items.length-1:selected-1));
  next.addEventListener('click',()=>jump(selected+1));
  nav.append(prev,next,position);
  for(const [index,item] of items.entries()){
    const li=el('li');li.append(el('strong',item.label+'（'+(item.name==='swift_syntax'?'Swift構文解析':item.name==='regression'?'回帰テスト':item.name)+'）'),el('p',item.reason));
    const go=el('button','この問題を確認');go.type='button';go.addEventListener('click',()=>jump(index));li.append(go);
    list.append(li);
  }
  section.append(nav,list);addProgressTracker(section,items);results.prepend(section);
}
function addAllCopyButton(data){
  const section=el('section');section.append(el('h2','すべての診断結果をまとめてコピー'));
  section.append(el('p','診断結果・エラー別の対処方法・実行ログをChatGPTへの相談用にまとめます。','muted'));
  const copy=el('button','全診断結果をコピー','copy all-copy');copy.type='button';
  const msg=el('span','','copy-status');msg.setAttribute('role','status');
  copy.addEventListener('click',async()=>{try{await copyToClipboard(allCopyText(data));msg.textContent='コピーしました。内容を確認してからChatGPTに貼り付けてください。';}catch(e){msg.textContent='コピーできませんでした。各検査のログを手動でコピーしてください。';}});
  section.append(copy,msg,el('p','ログにはファイルパスや機密情報が含まれる場合があります。貼り付ける前に確認してください。','privacy'));
  results.prepend(section);
}
function addCopyButton(section,name,check){const copy=el('button','対処方法とログをコピー','copy');copy.type='button';const msg=el('span','','copy-status');msg.setAttribute('role','status');copy.addEventListener('click',async()=>{try{await copyToClipboard(copyText(name,check));msg.textContent='コピーしました。ChatGPTに貼り付けられます。';}catch(e){msg.textContent='コピーできませんでした。下の実行ログを手動でコピーしてください。';}});section.append(copy,msg);}
button.addEventListener('click',async()=>{button.disabled=true;results.replaceChildren();status.textContent='診断中です。数十秒かかる場合があります…';try{const r=await fetch('/api/run?token='+encodeURIComponent(token||''),{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});const data=await r.json();if(!r.ok)throw Error(data.error||'診断を開始できませんでした');status.textContent=data.overall_status==='passed'?'診断完了：すべて正常':'診断完了：確認が必要な項目があります';for(const [name,check] of Object.entries(data.checks)){const section=el('section');section.id='check-'+name;section.append(el('h2',name==='swift_syntax'?'Swift構文解析':'回帰テスト'));section.append(el('p',check.status==='passed'?'正常':'要確認：'+check.status,check.status==='passed'?'ok':'bad'));section.append(el('p','所要時間：'+(check.duration_seconds??'不明')+'秒'));section.append(el('h3','対処方法'));section.append(el('p',advice(name,check)));addErrorHighlights(section,name,check);addRepairHints(section,name,check);addRepairPromptButton(section,name,check);addCopyButton(section,name,check);const d=el('details'),summary=el('summary','実行ログを表示');d.append(summary,el('pre',(check.stdout||'')+'\\n'+(check.stderr||'')));section.append(d);results.append(section);}addAllCopyButton(data);addPrioritySection(data);addComparisonSection(data);addHistorySection(data);results.append(el('p','詳細レポートは reports/diagnostics.html に保存されています。','muted'));}catch(e){status.textContent='診断を実行できませんでした：'+e.message;}finally{button.disabled=false;}});
</script></body></html>'''


def make_handler(token, root, runner, recent):
    lock = threading.Lock()
    class Handler(BaseHTTPRequestHandler):
        def respond(self, code, payload, content_type='application/json; charset=utf-8'):
            raw = payload.encode('utf-8')
            self.send_response(code)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(raw)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.end_headers()
            self.wfile.write(raw)
        def authorized(self):
            from urllib.parse import parse_qs, urlsplit
            supplied = parse_qs(urlsplit(self.path).query).get('token', [''])[0]
            return secrets.compare_digest(supplied, token)
        def do_GET(self):
            if not self.authorized():
                return self.respond(403, json.dumps({'error':'アクセスできません'}))
            if self.path.split('?')[0] != '/':
                return self.respond(404, '{}')
            self.respond(200, PAGE, 'text/html; charset=utf-8')
        def do_POST(self):
            if not self.authorized():
                return self.respond(403, json.dumps({'error':'アクセスできません'}))
            if self.path.split('?')[0] != '/api/run':
                return self.respond(404, '{}')
            if not lock.acquire(blocking=False):
                return self.respond(409, json.dumps({'error':'診断はすでに実行中です'},ensure_ascii=False))
            try:
                # Fixed executable/arguments; browser cannot supply shell commands or paths.
                proc = subprocess.run([sys.executable, str(runner), '--root', str(root), '--recent', str(recent)],cwd=root,capture_output=True,text=True,timeout=240)
                report_path = root / 'reports/diagnostics.json'
                report = json.loads(report_path.read_text(encoding='utf-8'))
                self.respond(200,json.dumps(report,ensure_ascii=False))
            except (OSError,ValueError,subprocess.TimeoutExpired) as exc:
                self.respond(500,json.dumps({'error':str(exc)},ensure_ascii=False))
            finally:
                lock.release()
        def log_message(self, fmt, *args):
            pass
    return Handler


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',type=int,default=0,help='Local port (0 selects an available port)')
    parser.add_argument('--recent',type=int,default=5)
    parser.add_argument('--no-browser',action='store_true')
    args=parser.parse_args(argv)
    if args.recent<1 or not 0<=args.port<=65535:parser.error('invalid recent/port')
    token=secrets.token_urlsafe(32)
    server=ThreadingHTTPServer(('127.0.0.1',args.port),make_handler(token,ROOT,ROOT/'Tests/run_diagnostics.py',args.recent))
    url=f'http://127.0.0.1:{server.server_port}/?token={token}'
    print('HOTEL SHIFT 診断センター:',url,flush=True)
    print('終了するにはターミナルで Control+C を押してください。',flush=True)
    if not args.no_browser:webbrowser.open(url)
    try:server.serve_forever()
    except KeyboardInterrupt:pass
    finally:server.server_close()
    return 0
if __name__=='__main__':sys.exit(main())
