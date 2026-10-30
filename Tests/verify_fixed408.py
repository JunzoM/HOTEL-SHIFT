#!/usr/bin/env python3
import json
import tempfile
import unittest
from pathlib import Path
from render_diagnostics_history import collect, render, write

class HistoryDashboardTests(unittest.TestCase):
    def test_empty(self):
        self.assertIn('有効な診断履歴はありません', render([]))
    def test_invalid_skipped_and_ordered(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)
            (p/'diagnostics_01.json').write_text('invalid')
            (p/'diagnostics_02.json').write_text(json.dumps({'schema_version':1,'checks':{'swift_syntax':{'status':'passed','duration_seconds':1},'triage_regression':{'status':'failed','duration_seconds':2,'test_counts':{'failed':3}}}}))
            self.assertEqual(len(collect(p)),1)
            self.assertEqual(collect(p)[0]['failed_tests'],3)
            out=p/'history.html';write(p,out)
            self.assertIn('診断履歴',out.read_text())
    def test_html_injection_escaped(self):
        page=render([{'date':'</script><script>alert(1)</script>','overall':'passed','swift':'passed','regression':'passed','swift_seconds':1,'regression_seconds':2,'failed_tests':0}])
        self.assertNotIn('</script><script>alert',page)
        self.assertIn('\\u003c/script\\u003e',page)
    def test_no_history_mutation(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);source=p/'diagnostics_1.json';source.write_text('{}');write(p,p/'out.html');self.assertEqual(source.read_text(),'{}')
    def test_offline_selectors(self):
        page=render([])
        self.assertIn('id="current"',page)
        self.assertIn('id="baseline"',page)
        self.assertNotIn('https://',page)

if __name__=='__main__':unittest.main()
