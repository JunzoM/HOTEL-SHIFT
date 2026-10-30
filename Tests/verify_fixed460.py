from pathlib import Path
import unittest
s=(Path(__file__).resolve().parents[1]/"HOTEL_SHIFT/Services/ShiftStore.swift").read_text()
class PrintRegression(unittest.TestCase):
 def test_two_lines_separate(self):
  self.assertIn('draw(clock(startMinutes)',s)
  self.assertIn('draw(clock(endMinutes)',s)
  self.assertNotIn('draw(startText + "\\\\n" + endText',s)
 def test_overnight(self):
  self.assertIn('case .night: defaultRange = (1260, 1980)',s)
  self.assertIn('(minutes / 60) % 24',s)
 def test_breaks(self):
  self.assertIn('assignment.customBreakMinutes',s)
  self.assertIn('totalMinutes += max(0, duration - rest)',s)
 def test_page_settings(self):
  self.assertIn('let isPortrait = paperSize.hasSuffix("縦")',s)
  self.assertIn('drawTable(firstHalf',s)
  self.assertIn('drawTable(secondHalf',s)
if __name__=="__main__": unittest.main()
