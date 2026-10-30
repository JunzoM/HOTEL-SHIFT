#!/usr/bin/env python3
"""FIXED451 regression: CSV date presets and diagnosis comparison graph."""
from pathlib import Path
import unittest, re, subprocess, tempfile, shutil
ROOT=Path(__file__).resolve().parents[1]
VIEW=(ROOT/"HOTEL_SHIFT/Views/ShiftCalendarView.swift").read_text()
STORE=(ROOT/"HOTEL_SHIFT/Services/ShiftStore.swift").read_text()
HTML=(ROOT/"Tests/local_diagnostic_center.py").read_text().split("PAGE = r\'\'\'",1)[1].split("\'\'\'",1)[0]
class Fixed451(unittest.TestCase):
    def test_preset_helper_called(self):
        self.assertIn("csvHistoryPresetButton(preset)", VIEW)
        self.assertIn("private func csvHistoryPresetButton(_ preset: String)", VIEW)
    def test_both_preset_styles_and_action(self):
        helper=VIEW.split("private func csvHistoryPresetButton(_ preset: String)",1)[1].split("private var csvRetryHistoryView",1)[0]
        self.assertIn(".buttonStyle(.borderedProminent)",helper)
        self.assertIn(".buttonStyle(.bordered)",helper)
        self.assertEqual(helper.count("applyCSVHistoryDatePreset(preset)"),2)
        self.assertIn(".accessibilityAddTraits(.isSelected)",helper)
    def test_optional_int_not_nested(self):
        self.assertIn("breakMinutes: defaultTimes == nil ? nil : pattern.customBreakMinutes,",STORE)
    def test_chart_zero_guard_and_accessibility(self):
        self.assertIn("if(indices.length<2){",HTML)
        self.assertIn("bar.setAttribute('aria-label'",HTML)
        self.assertIn("segment.style.width=(count/intervalCount*100)",HTML)
    def test_js_syntax(self):
        node=shutil.which("node")
        if not node: self.skipTest("node not installed")
        js=HTML.split("<script>",1)[1].split("</script>",1)[0]
        with tempfile.NamedTemporaryFile("w",suffix=".js") as f:
            f.write(js);f.flush()
            r=subprocess.run([node,"--check",f.name],capture_output=True,text=True)
        self.assertEqual(r.returncode,0,r.stderr)
if __name__=="__main__": unittest.main()
