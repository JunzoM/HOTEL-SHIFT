#!/usr/bin/env python3
"""Run the production name fitter with AppKit fonts; checks are not iOS visual QA."""
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
class NameLayoutTests(unittest.TestCase):
 def test_complete_names_fit(self):
  s = (ROOT/'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()
  start=s.index('    nonisolated private static func staffNameLayout(')
  end=s.index('    nonisolated private static func renderShiftPDF(',start)
  method=s[start:end].replace('nonisolated private static func','static func',1)
  program='''import AppKit
typealias UIFont = NSFont
struct Layout {
'''+method+'''}
let seven = Layout.staffNameLayout("田田田田田田田", width: 86, height: 28, font: .boldSystemFont(ofSize: 12))
precondition(!seven.string.contains("\\n"))
precondition((seven.attribute(.font, at: 0, effectiveRange: nil) as! NSFont).pointSize == 12)
let eight = Layout.staffNameLayout("田田田田田田田田", width: 86, height: 28, font: .boldSystemFont(ofSize: 12))
precondition(eight.string.components(separatedBy: "\\n").count == 2)
let names = ["山田 太郎", "佐々木 美奈子", "長谷川 あかり", "Alexander Williams", "山田 太郎\\n¥1500"]
for height: CGFloat in [22, 28, 33] {
 for name in names {
  let text = Layout.staffNameLayout(name, width: 86, height: height, font: .boldSystemFont(ofSize: 12))
  precondition(text.string.filter { !$0.isWhitespace } == name.filter { !$0.isWhitespace })
  let style=text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
  precondition(style.lineBreakMode == .byClipping)
  let bounds=text.boundingRect(with: CGSize(width: 85, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
  precondition(bounds.width <= 85.01 && bounds.height <= height - 0.99)
 }
}
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2000, pixelsHigh: 240, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let context=NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.current=context
context.cgContext.setFillColor(NSColor.white.cgColor)
context.cgContext.fill(CGRect(x: 0,y: 0,width: 2000,height: 240))
context.cgContext.translateBy(x: 0,y: 240)
context.cgContext.scaleBy(x: 4,y: -4)
let flipped = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
NSGraphicsContext.current=flipped
for (i,name) in names.enumerated() {
 let rect=CGRect(x: 5+CGFloat(i)*99,y: 12,width: 90,height: 30)
 NSColor.gray.setStroke()
 NSBezierPath(rect: rect).stroke()
 let text=Layout.staffNameLayout(name,width: 86,height: 28,font: .boldSystemFont(ofSize: 12))
 let bounds=text.boundingRect(with: CGSize(width: 85,height: CGFloat.greatestFiniteMagnitude),options: [.usesLineFragmentOrigin,.usesFontLeading])
 text.draw(with: CGRect(x: rect.minX+2.5,y: rect.midY-bounds.height/2,width: 85,height: bounds.height+0.5),options: [.usesLineFragmentOrigin,.usesFontLeading])
}
NSGraphicsContext.restoreGraphicsState()
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("15 measured name/row combinations passed; desktop render produced")
'''
  with tempfile.TemporaryDirectory() as tmp:
   source=Path(tmp)/'Names.swift'
   source.write_text(program)
   image=ROOT/'reports/fixed474_name_layout.png'
   image.parent.mkdir(exist_ok=True)
   r=subprocess.run(['swift','-module-cache-path',tmp+'/cache',str(source),str(image)],capture_output=True,text=True,timeout=60)
   self.assertEqual(r.returncode,0,r.stderr)
if __name__ == '__main__': unittest.main()
