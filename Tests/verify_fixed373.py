#!/usr/bin/env python3
"""FIXED373 recurring-diagnostics regression tests."""
import importlib.util
import json
import tempfile
from pathlib import Path
root=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('persistent',root/'Tests/analyze_xcode_persistent_errors.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
checks=[]
def check(label,condition):
    checks.append(bool(condition));print(('PASS' if condition else 'FAIL'),label)
with tempfile.TemporaryDirectory() as d:
    directory=Path(d)
    names=[f'build-20261025T150{i}00000000Z.json' for i in range(4)]
    def entry(msg):return {'category':'Swiftコンパイル','message':msg,'suggested_check':'Check <Xcode>'}
    records=[[entry('Main.swift:12:3: error: unresolved <Thing>')], [entry('Main.swift:42:9: error: unresolved <Thing>'),entry('Other.swift:1: error: missing')], [entry('Main.swift:56: error: unresolved <Thing>')], []]
    for name,entries in zip(names,records):
        (directory/name).write_text(json.dumps({'schema_version':1,'result':'failure','prioritized_diagnostics':entries}))
    (directory/'index.json').write_text(json.dumps({'schema_version':1,'builds':[{'file':n} for n in reversed(names)]}))
    result=mod.analyze(directory)
    check('history sorted',result['analyzed_builds']==4)
    check('recurring detection',len(result['recurring'])==1)
    check('line changes normalized',result['recurring'][0]['builds']==3)
    check('latest streak reset',result['recurring'][0]['consecutive_latest']==0)
    check('HTML escaped', '&lt;Thing&gt;' in mod.render(result) and '&lt;Xcode&gt;' in mod.render(result))
    check('HTML includes scope', '上位10件' in mod.render(result))
    result3=mod.analyze(directory,last=3)
    check('bounded analysis',result3['analyzed_builds']==3)
    check('bounded occurrences',result3['recurring'][0]['builds']==2)
    check('high minimum suppresses',not mod.analyze(directory,minimum=4)['recurring'])
    check('empty index accepted',mod.analyze(directory,last=1,minimum=2)['schema_version']==1)
    for name,kwargs in [('zero window',{'last':0}),('minimum one',{'minimum':1})]:
        try:mod.analyze(directory,**kwargs);ok=False
        except ValueError:ok=True
        check(name,ok)
    (directory/'index.json').write_text(json.dumps({'schema_version':1,'builds':[{'file':'../bad.json'}]}))
    try:mod.analyze(directory);ok=False
    except ValueError:ok=True
    check('reject traversal',ok)
    (directory/'index.json').write_text(json.dumps({'schema_version':1,'builds':[{'file':names[0]},{'file':names[0]}]}))
    try:mod.analyze(directory);ok=False
    except ValueError:ok=True
    check('reject duplicate history',ok)
    pipeline=(root/'Tests/run_xcode_report_pipeline.sh').read_text()
    check('pipeline integrated','analyze_xcode_persistent_errors.py' in pipeline)
assert all(checks)
print(f'FIXED373: {len(checks)}/{len(checks)} passed')
