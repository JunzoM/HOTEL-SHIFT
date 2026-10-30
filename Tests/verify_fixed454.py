from pathlib import Path
import unittest
root=Path(__file__).resolve().parents[1]
s=(root/'HOTEL_SHIFT/Views/StaffAndOtherViews.swift').read_text()
class PreviewRegression(unittest.TestCase):
 def test_loaded_document_is_retained(self):
  self.assertIn('@State private var fullPreviewDocument: PDFDocument?',s)
  self.assertIn('if let document = fullPreviewDocument {',s)
  self.assertNotIn('fullPreviewURL',s)
 def test_validated_before_presentation(self):
  a=s.split('private func openActualPDFPreview()',1)[1].split('private func configuredPDF()',1)[0]
  self.assertIn('document.pageCount > 0',a)
  self.assertLess(a.index('fullPreviewDocument = document'),a.index('showFullPreview = true'))
 def test_invalidation(self):
  self.assertIn('fullPreviewDocument = nil',s)
 def test_pdf_export_retained(self):
  self.assertIn('store.exportShiftPDF(month: pdfMonth',s)
if __name__=='__main__':unittest.main()
