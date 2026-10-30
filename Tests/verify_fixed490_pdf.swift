import Foundation
import AppKit
import PDFKit
import Vision
let file = URL(fileURLWithPath: CommandLine.arguments[1])
let doc = PDFDocument(url: file)!
precondition(doc.pageCount == 1)
let page = doc.page(at: 0)!
let bounds = page.bounds(for: .mediaBox)
precondition(abs(bounds.width - 595) < 1 && abs(bounds.height - 842) < 1)
let preview = page.thumbnail(of: NSSize(width: 1190, height: 1684), for: .mediaBox)
let cg = preview.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
try VNImageRequestHandler(cgImage: cg).perform([request])
let values = (request.results ?? []).compactMap(\.payloadStringValue)
let expected = "https://facility-manager-phi.vercel.app/hotel-shift/request"
precondition(values.count == 1 && values[0].hasPrefix(expected))
let components = URLComponents(string: values[0])!
precondition(components.queryItems?.first(where: { $0.name == "s" })?.value == "東京本店")
let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("A4 portrait, single page, QR decoded to supplied form with Tokyo store parameter")
