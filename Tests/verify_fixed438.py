#!/usr/bin/env python3
"""FIXED438: selected history consultation prompt."""
import pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
class Fixed438(unittest.TestCase):
 def test_prompt_builder(self):self.assertIn('function selectedHistoryConsultationText(i)',PAGE)
 def test_summary_reuse(self):self.assertIn('const summary=selectedHistoryCopyText(i)',PAGE)
 def test_empty_guard(self):self.assertIn("if(!summary)return '';",PAGE)
 def test_no_raw_logs(self):
  part=PAGE.split('function selectedHistoryConsultationText(i){',1)[1].split('const copySelectedButton=',1)[0]
  self.assertNotIn('stdout',part);self.assertNotIn('stderr',part)
 def test_not_claiming_cause(self):self.assertIn('未確認の原因や修正完了を断定しない',PAGE)
 def test_button(self):self.assertIn('選択した診断をChatGPTに相談する文章をコピー',PAGE)
 def test_disabled(self):self.assertIn('consultSelectedButton.disabled=true',PAGE)
 def test_enable(self):self.assertIn('consultSelectedButton.disabled=false',PAGE)
 def test_explicit_click(self):self.assertIn('copyToClipboard(selectedHistoryConsultationText(selectedIndex))',PAGE)
 def test_copy_feedback(self):self.assertIn('相談用の文章をコピーしました',PAGE)
 def test_safe_dom(self):self.assertNotIn('innerHTML',PAGE)
 def test_js_syntax(self):
  js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
  with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
   f.write(js);f.flush();r=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
  self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__':unittest.main()
