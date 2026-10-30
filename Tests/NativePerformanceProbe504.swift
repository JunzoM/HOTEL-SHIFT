// Included only in the isolated verification build, never in the shipping target.
import Foundation
import SwiftUI
import UIKit
import PDFKit
import Vision

@MainActor enum NativePerformanceProbe504 {
    static func run(_ store: ShiftStore) async {
        do {
            let previousReport = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("fixed504_native_probe.json")
            try? FileManager.default.removeItem(at: previousReport)
            var metrics: [String: Any] = ["probe_version": 3, "environment": "iPad Pro Simulator; debug build; not a physical-device FPS claim"]
            store.cloudSync.pause()
            let fixture = SampleShiftData.make(anchor: Date.keyFormatter.date(from: "2026-10-28")!)
            store.data = fixture; store.selectedLocationID = fixture.locations[0].id
            let people = store.selectedStaff
            precondition(people.count == 25)
            let day = Date.keyFormatter.date(from: "2026-10-01")!
            let before = store.assignment(staffID: people[0].id, date: day)!
            let revision = store.pdfRevision
            store.setShift(staffID: people[0].id, date: day, type: .paidLeave)
            precondition(store.pdfRevision == revision + 1)
            precondition(store.assignment(staffID: people[0].id, date: day)?.type == .paidLeave)
            store.data = fixture
            // Atomic bulk edits, cached lookups, undo, and store isolation.
            let edits = people.prefix(3).map { person -> ScheduleGridEdit in
                let old = store.assignment(staffID: person.id, date: day)
                let next = ScheduleGridSupport.replacing(old, type: .off, staff: person, dateKey: day.shiftDateKey, locationID: store.selectedLocationID)
                return ScheduleGridEdit(key: .init(staffID: person.id, dateKey: day.shiftDateKey), before: old, after: next)
            }
            if let change = try store.applyScheduleGrid(edits, locationID: store.selectedLocationID, revision: store.pdfRevision, allowLeave: true) {
                try store.restoreScheduleGrid(change, undo: true)
            }
            precondition(store.assignment(staffID: people[0].id, date: day) == before)
            let oldLocation = store.selectedLocationID
            store.selectedLocationID = fixture.locations[1].id
            precondition(store.staffMember(id: people[0].id) == nil)
            precondition(store.assignment(staffID: people[0].id, date: day) == nil)
            store.selectedLocationID = oldLocation
            precondition(store.staffMember(id: people[0].id) == people[0])
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4032, height: 3024), format: format)
            let source = renderer.jpegData(withCompressionQuality: 0.9) { context in
                for y in 0..<32 { for x in 0..<40 {
                    UIColor(red: CGFloat(x)/40, green: CGFloat(y)/32, blue: CGFloat((x+y)%20)/20, alpha: 1).setFill()
                    context.fill(CGRect(x: x*101, y: y*95, width: 101, height: 95))
                } }
            }
            let photoStart = ProcessInfo.processInfo.systemUptime
            let imageWork = await Task.detached { () -> (UIImage?, Double) in
                let start = ProcessInfo.processInfo.systemUptime
                let image = ShiftPhotoCache.image(source, pixels: 128)
                return (image, (ProcessInfo.processInfo.systemUptime-start)*1000)
            }.value
            let thumbnail = imageWork.0
            metrics["thumbnail_decode_work_ms"] = imageWork.1
            precondition(thumbnail != nil && max(thumbnail!.cgImage!.width, thumbnail!.cgImage!.height) <= 128)
            metrics["source_pixels"] = 4032 * 3024
            metrics["thumbnail_pixels"] = thumbnail!.cgImage!.width * thumbnail!.cgImage!.height
            metrics["thumbnail_first_request_elapsed_ms"] = (ProcessInfo.processInfo.systemUptime-photoStart)*1000
            let compressed = await Task.detached { ShiftPhotoProcessing.jpeg(source, maxPixels: 640) }.value
            precondition(compressed != nil)
            let imported = UIImage(data: compressed!)!
            precondition(max(imported.size.width, imported.size.height) <= 640)
            var photos = fixture
            for i in photos.staff.indices {
                var unique = source
                if unique.count < 256*1024 { unique.append(Data(repeating: UInt8(i), count: 256*1024-unique.count)) }
                unique.append(UInt8(i))
                photos.staff[i].photoData = unique
            }
            // Distinct valid JPEG bytes per member exercise the cache, not one shared image key.
            let decodeStart = ProcessInfo.processInfo.systemUptime
            let allPhotos = photos.staff.compactMap(\.photoData)
            let decoded = await Task.detached { allPhotos.map { ShiftPhotoCache.image($0, pixels: 128) } }.value
            precondition(decoded.allSatisfy { $0 != nil })
            metrics["decode_100_distinct_portraits_ms"] = (ProcessInfo.processInfo.systemUptime-decodeStart)*1000
            let hitStart = ProcessInfo.processInfo.systemUptime
            let hits = await Task.detached { allPhotos.allSatisfy { ShiftPhotoCache.cached($0, pixels: 128) != nil } }.value
            precondition(hits)
            metrics["100_portrait_cache_hits_ms"] = (ProcessInfo.processInfo.systemUptime-hitStart)*1000
            store.data = photos
            var oldGap = 0.0, oldPrevious = ProcessInfo.processInfo.systemUptime
            let oldPulse = Task { @MainActor in
                while !Task.isCancelled {
                    let now = ProcessInfo.processInfo.systemUptime
                    oldGap = max(oldGap, (now-oldPrevious)*1000); oldPrevious = now
                    try? await Task.sleep(for: .milliseconds(5))
                }
            }
            try await Task.sleep(for: .milliseconds(20))
            let legacyFile = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-benchmark.json")
            let legacyStart = ProcessInfo.processInfo.systemUptime
            try autoreleasepool {
                let oldBytes = try JSONEncoder().encode(photos)
                try oldBytes.write(to: legacyFile, options: .atomic)
            }
            metrics["legacy_main_thread_save_ms"] = (ProcessInfo.processInfo.systemUptime-legacyStart)*1000
            try? FileManager.default.removeItem(at: legacyFile)
            try await Task.sleep(for: .milliseconds(20)); oldPulse.cancel()
            metrics["legacy_ui_actor_max_gap_ms"] = oldGap
            var beats = 0, maximumGap = 0.0, previous = ProcessInfo.processInfo.systemUptime
            let pulse = Task { @MainActor in
                while !Task.isCancelled {
                    let now = ProcessInfo.processInfo.systemUptime
                    maximumGap = max(maximumGap, (now-previous)*1000); previous=now; beats += 1
                    try? await Task.sleep(for: .milliseconds(5))
                }
            }
            try await Task.sleep(for: .milliseconds(20))
            let saveStart = ProcessInfo.processInfo.systemUptime
            guard let snapshot = await store.cloudSnapshot() else { preconditionFailure("save failed") }
            metrics["async_store_save_ms"] = (ProcessInfo.processInfo.systemUptime-saveStart)*1000
            try await Task.sleep(for: .milliseconds(20)); pulse.cancel()
            metrics["ui_actor_max_gap_during_save_ms"] = maximumGap; metrics["ui_actor_heartbeat_count"] = beats
            let decodedSnapshot = try JSONDecoder().decode(ShiftData.self, from: snapshot)
            precondition(decodedSnapshot.staff == photos.staff && decodedSnapshot.assignments == photos.assignments)
            let cacheStart = ProcessInfo.processInfo.systemUptime
            for _ in 0..<20 { let bytes = await store.cloudSnapshot(); precondition(bytes != nil) }
            metrics["20_unchanged_snapshot_reads_ms"] = (ProcessInfo.processInfo.systemUptime-cacheStart)*1000
            guard let exported = await store.exportBackup() else { preconditionFailure("backup export") }
            let restoreOK = await store.importBackup(from: exported)
            precondition(restoreOK && store.data.staff == photos.staff)
            let malformed = exported.deletingLastPathComponent().appendingPathComponent("probe-invalid.json")
            try Data("invalid".utf8).write(to: malformed)
            let invalidOK = await store.importBackup(from: malformed)
            precondition(!invalidOK && store.data.staff == photos.staff)
            try? FileManager.default.removeItem(at: malformed)
            try? FileManager.default.removeItem(at: exported)
            let selected = store.selectedAssignments(inMonth: "2026-10")
            precondition(selected.count == 775)
            precondition(store.selectedAssignments(on: ["2026-10-01"]).count == 25)
            // Native direct header tracking, without a SwiftUI state update per scroll event.
            let header = UIScrollView(frame: CGRect(x:0,y:0,width:500,height:60))
            header.contentSize = CGSize(width:2000,height:60)
            let link = ScheduleScrollLink(); link.header = header
            let body = UIScrollView(frame: CGRect(x:0,y:0,width:500,height:100))
            body.contentSize=CGSize(width:2000,height:100); link.body=body
            let view = ScheduleLinkedHorizontalScroll(contentWidth:2000,contentHeight:100,resetKey:"test",contentRevision:AnyHashable(0),link:link) { Text("test") }
            let coordinator = view.makeCoordinator()
            body.contentOffset=CGPoint(x:480,y:0); coordinator.scrollViewDidScroll(body)
            precondition(header.contentOffset.x==480)
            link.reset(); precondition(header.contentOffset.x==0 && body.contentOffset.x==0)
            let pdfStart = ProcessInfo.processInfo.systemUptime
            let pdfMonth = Date.keyFormatter.date(from: "2026-10-01")!
            guard let pdf = await store.exportShiftPDFAsync(month: pdfMonth), let document = PDFDocument(url: pdf) else { preconditionFailure("PDF export") }
            precondition(document.pageCount > 0)
            metrics["pdf_first_generation_ms"] = (ProcessInfo.processInfo.systemUptime-pdfStart)*1000
            let pdfCachedStart = ProcessInfo.processInfo.systemUptime
            let cachedPDF = await store.exportShiftPDFAsync(month: pdfMonth)
            precondition(cachedPDF == pdf)
            metrics["pdf_cached_generation_ms"] = (ProcessInfo.processInfo.systemUptime-pdfCachedStart)*1000
            let csvStart = ProcessInfo.processInfo.systemUptime
            guard let csv = await store.exportCSV() else { preconditionFailure("CSV export") }
            let contents = try String(contentsOf: csv, encoding: .utf8)
            precondition(contents.components(separatedBy: "\n").filter { !$0.isEmpty }.count == store.selectedAssignments.count + 1)
            metrics["csv_export_ms"] = (ProcessInfo.processInfo.systemUptime-csvStart)*1000
            try? FileManager.default.removeItem(at: csv)
            let protected = ShiftStore(prepared: .init(data: fixture, fresh: false, migrated: false, failed: true, index: ShiftLookupIndex(fixture)))
            let blockedCSV = await protected.exportCSV()
            let blockedPDF = await protected.exportShiftPDFAsync(month: pdfMonth)
            let blockedBackup = await protected.exportBackup()
            precondition(blockedCSV == nil && blockedPDF == nil && blockedBackup == nil && protected.exportRequestTransfer() == nil)
            let requestURL = RequestFormLink.url(storeName: "サンプル東京店").absoluteString
            guard let qr = RequestQRCode.image(requestURL, size: 260), let qrAgain = RequestQRCode.image(requestURL, size: 260), let cg = qr.cgImage else { preconditionFailure("QR image") }
            precondition(qr === qrAgain)
            let detection = VNDetectBarcodesRequest()
            detection.usesCPUOnly = true
            let padded = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300)).image { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
                UIImage(cgImage: cg).draw(in: CGRect(x: 20, y: 20, width: 260, height: 260))
            }
            do {
                try VNImageRequestHandler(cgImage: padded.cgImage!).perform([detection])
                metrics["qr_vision_decoded"] = detection.results?.contains(where: { $0.payloadStringValue == requestURL }) == true
            } catch { metrics["qr_vision_unavailable"] = String(describing: error) }
            let originalLocation = store.selectedLocationID
            store.addLocation(name: "性能検証の一時店舗")
            let temporaryLocation = store.selectedLocationID
            store.addStaff(name: "性能検証", department: "一時", employment: "パート", wage: 1200)
            let temporaryStaff = store.selectedStaff[0]
            store.deleteStaff(temporaryStaff)
            precondition(store.selectedStaff.isEmpty)
            let profileRevision = store.pdfRevision
            store.updateLocationProfile(id: temporaryLocation, name: "名称更新", address: "", phone: "", roomCount: 10, floorCount: 2)
            precondition(store.pdfRevision == profileRevision + 1)
            store.deleteLocation(id: temporaryLocation)
            store.selectedLocationID = originalLocation
            precondition(store.data.locations.count == 4 && store.data.staff.count == 100 && store.data.assignments.count == 6100)
            guard await store.cloudSnapshot() != nil else { preconditionFailure("final durable save") }
            let scrolling = await ScrollFrameProbe504.run(output: "fixed504_scroll_after.json", requireHeader: true)
            precondition(scrolling)
            metrics["checks"] = ["single-notification-shift-edit", "bulk-and-undo", "index-refresh", "store-isolation", "12MP-downsample", "100-valid-distinct-JPEGs", "portrait-cache", "async-durable-save", "snapshot-cache", "async-export-restore", "invalid-restore-preserves-data", "UIKit-header-link-and-reset", "atomic-location-profile-and-delete", "staff-delete-guard", "PDF-and-cache", "async-CSV-row-count", "animated-grid-header-tracking", "protected-state-exports-blocked", "QR-cache-identity"]
            let output = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("fixed504_native_probe.json")
            try JSONSerialization.data(withJSONObject:metrics,options:[.prettyPrinted,.sortedKeys]).write(to:output)
            print("FIXED504_NATIVE_PROBE_PASSED")
        } catch {
            let errorURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("fixed504_probe_error.txt")
            try? String(describing: error).write(to: errorURL, atomically: true, encoding: .utf8)
            print("FIXED504_NATIVE_PROBE_FAILED: \(error)")
        }
    }
}
