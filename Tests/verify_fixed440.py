#!/usr/bin/env python3
"""FIXED440: multi-run ChatGPT consultation copying."""
import pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PAGE=(ROOT/'Tests/local_diagnostic_center.py').read_text().split("PAGE = r'''",1)[1].split("'''",1)[0]
PART=PAGE.split('// FIXED440:',1)[1].split('function updateComparison()',1)[0]
class Fixed440(unittest.TestCase):
 def test_consultation_builder(self): self.assertIn('function comparisonConsultationText()',PART)
 def test_requires_two(self): self.assertIn('comparisonConsult.disabled=indices.length<2',PAGE)
 def test_uses_selection(self): self.assertIn('const summary=comparisonSelectionText()',PART)
 def test_privacy_note(self): self.assertIn('集計情報のみ',PART)
 def test_does_not_claim_fix(self): self.assertIn('修正済みと判断せず',PART)
 def test_steps(self): self.assertIn('修正の優先順位',PART)
 def test_copy_button(self): self.assertIn('選択した診断をChatGPTに相談する文章をコピー',PART)
 def test_copy_action(self): self.assertIn('copyToClipboard(value);comparisonFeedback',PAGE)
 def test_mount(self): self.assertIn('comparisonCopy,comparisonConsult,comparisonClear',PAGE)
 def test_safe_dom(self): self.assertNotIn('innerHTML',PAGE)
 def test_js_syntax(self):
  js=PAGE.split('<script>',1)[1].split('</script>',1)[0]
  with tempfile.NamedTemporaryFile('w',suffix='.js') as f:
   f.write(js);f.flush();r=subprocess.run(['node','--check',f.name],capture_output=True,text=True)
  self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__':unittest.main()
