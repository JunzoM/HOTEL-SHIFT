#!/usr/bin/env python3
import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('diagnostics', Path(__file__).with_name('run_diagnostics.py'))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class DiagnosticsTests(unittest.TestCase):
    def test_success(self):
        r = mod.execute(['python3', '-c', 'print("OK")'], Path('.'), 5)
        self.assertEqual(r['status'], 'passed')
        self.assertIn('OK', r['stdout'])

    def test_failure(self):
        self.assertEqual(mod.execute(['python3', '-c', 'raise SystemExit(3)'], Path('.'), 5)['exit_code'], 3)

    def test_timeout(self):
        self.assertEqual(mod.execute(['python3', '-c', 'import time;time.sleep(2)'], Path('.'), .1)['status'], 'timeout')

    def test_missing_command(self):
        self.assertEqual(mod.execute(['/nonexistent/diagnostic-binary'], Path('.'), 1)['status'], 'error')

    def test_escaping(self):
        report = {'overall_status':'failed', 'checks': {'swift_syntax': {'status':'failed', 'stdout':'<script>alert(1)</script>', 'stderr':''}}}
        output = mod.render(report)
        self.assertNotIn('<script>', output)
        self.assertIn('&lt;script&gt;', output)

    def test_cli_validation(self):
        with self.assertRaises(SystemExit):
            mod.main(['--recent', '0'])

unittest.main() if __name__ == '__main__' else None
