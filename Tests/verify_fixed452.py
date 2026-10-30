from pathlib import Path
import unittest
s=(Path(__file__).resolve().parents[1]/"HOTEL_SHIFT/Services/ShiftStore.swift").read_text()
class TestPDF(unittest.TestCase):
 def test_one_sheet(self):
  self.assertIn("let staffPages: [[StaffMember]] = [staff]",s)
  self.assertIn("drawTable(firstHalf",s)
  self.assertIn("drawTable(secondHalf",s)
 def test_other_modes(self):
  self.assertIn('case "前半"',s)
  self.assertIn('case "後半"',s)
  self.assertIn('periodMode == "上下分割"',s)
if __name__=="__main__": unittest.main()
