from pathlib import Path
import unittest
root=Path(__file__).resolve().parents[1]/"HOTEL_SHIFT/Views"
a=(root/"StaffAndOtherViews.swift").read_text()
b=(root/"ShiftCalendarView.swift").read_text()
class PreviewTests(unittest.TestCase):
 def test_atomic_fullscreen(self):
  self.assertIn(".fullScreenCover(item: $activePDFPreview)",a)
  self.assertIn("activePDFPreview = OutputPDFPreviewItem(document: document, url: url)",a)
  self.assertNotIn("showFullPreview",a)
 def test_calendar_preloads(self):
  self.assertIn("PDFPreviewItem(url: url, document: document)",b)
  self.assertIn("PDFOutputPreview(url: item.url, document: item.document)",b)
  self.assertNotIn("if let document = PDFDocument(url: url) {",b)
if __name__=="__main__":unittest.main()
