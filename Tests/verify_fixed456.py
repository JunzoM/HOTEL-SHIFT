from pathlib import Path
import unittest
s=(Path(__file__).resolve().parents[1]/"HOTEL_SHIFT/Services/ShiftStore.swift").read_text()
class TestPrint(unittest.TestCase):
 def test_paper_selection(self):
  self.assertIn('let isPortrait = paperSize.hasSuffix("縦")',s)
  self.assertIn('let isA3 = paperSize.hasPrefix("A3")',s)
 def test_split_one_sheet(self):
  self.assertIn('let staffPages: [[StaffMember]] = [staff]',s)
 def test_time_two_lines(self):
  self.assertIn('value = lines.joined(separator: "\\n")',s)
 def test_width(self):
  self.assertIn('usableWidth * (isPortrait ? 0.21 : 0.24)',s)
if __name__=="__main__":unittest.main()
