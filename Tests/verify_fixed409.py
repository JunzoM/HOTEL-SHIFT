#!/usr/bin/env python3
import http.client
import json
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from local_diagnostic_center import make_handler, PAGE

class LocalCenterTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.root=Path(self.tmp.name)
        (self.root/'reports').mkdir()
        (self.root/'reports/diagnostics.json').write_text(json.dumps({'overall_status':'passed','checks':{'swift_syntax':{'status':'passed','stdout':'','stderr':'','duration_seconds':0.1}}}))
        self.runner=self.root/'runner.py'
        self.runner.write_text('print("ok")\n')
        self.server=ThreadingHTTPServer(('127.0.0.1',0),make_handler('secret',self.root,self.runner,2))
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join();self.tmp.cleanup()
    def request(self,method,path,body=None):
        conn=http.client.HTTPConnection('127.0.0.1',self.server.server_port,timeout=10)
        conn.request(method,path,body=body)
        response=conn.getresponse();data=response.read().decode();code=response.status;conn.close();return code,data
    def test_page(self):
        code,data=self.request('GET','/?token=secret');self.assertEqual(code,200);self.assertIn('診断を実行',data)
    def test_unauthorized_page(self):self.assertEqual(self.request('GET','/')[0],403)
    def test_unauthorized_run(self):self.assertEqual(self.request('POST','/api/run')[0],403)
    def test_run(self):
        code,data=self.request('POST','/api/run?token=secret','{}');self.assertEqual(code,200);self.assertEqual(json.loads(data)['overall_status'],'passed')
    def test_unknown_route(self):self.assertEqual(self.request('GET','/other?token=secret')[0],404)
    def test_guidance(self):
        self.assertIn('対処方法',PAGE);self.assertIn('timeout',PAGE);self.assertIn('swift_syntax',PAGE)
if __name__=='__main__':unittest.main()
