import Foundation

@MainActor final class Pulse {
    var count = 0, maximumGap = 0.0
    private var previous = ProcessInfo.processInfo.systemUptime
    func beat() {
        let now = ProcessInfo.processInfo.systemUptime
        maximumGap = max(maximumGap, (now - previous) * 1000)
        previous = now; count += 1
    }
}
@main struct PerformanceBench504 {
    @MainActor static var sink = 0
    @MainActor static func measured(_ runs: Int, _ work: () -> Void) -> Double {
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<runs { work() }
        return (ProcessInfo.processInfo.systemUptime - start) * 1000 / Double(runs)
    }
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("database.json")
        defer { try? FileManager.default.removeItem(at: file) }
        var sample = SampleShiftData.make(anchor: Date.keyFormatter.date(from: "2026-10-28")!)
        let location = sample.locations[0].id, staff = sample.staff.filter { $0.locationID == location }
        let days = (1...31).map { String(format: "2026-10-%02d", $0) }
        let indexBuild = measured(5) { sink += ShiftLookupIndex(sample).assignmentByCell.count }
        let index = ShiftLookupIndex(sample)
        for person in staff { for day in days {
            let old = sample.assignments.first { $0.locationID == location && $0.staffID == person.id && $0.dateKey == day }
            let new = index.assignmentByCell[.init(location: location, staff: person.id, day: day)].map { sample.assignments[$0] }
            precondition(old == new)
        } }
        let linear = measured(5) {
            for person in staff { for day in days {
                sink += sample.assignments.first { $0.locationID == location && $0.staffID == person.id && $0.dateKey == day }?.note.count ?? 0
            } }
        }
        let indexed = measured(10) {
            for person in staff { for day in days {
                if let i = index.assignmentByCell[.init(location: location, staff: person.id, day: day)] { sink += sample.assignments[i].note.count }
            } }
        }
        let visible = Set(days)
        let oldPositions = sample.assignments.indices.filter { sample.assignments[$0].locationID == location && visible.contains(sample.assignments[$0].dateKey) }
        precondition(index.assignmentPositions(location: location, days: visible) == oldPositions)
        // Legacy duplicate cells retain original-first lookup and original row order.
        var duplicates = sample
        var duplicate = duplicates.assignments[0]; duplicate.id = UUID(); duplicate.note = "duplicate"
        duplicates.assignments.append(duplicate)
        let duplicateIndex = ShiftLookupIndex(duplicates)
        precondition(duplicateIndex.assignmentByCell[.init(location: location, staff: duplicate.staffID, day: duplicate.dateKey)] == 0)
        let renderCache = ShiftRenderCache(); var builds = 0
        for _ in 0..<1000 { let _: Int = renderCache.value(for: "same") { builds += 1; return 1 } }
        precondition(builds == 1)
        let _: Int = renderCache.value(for: "new revision") { builds += 1; return 2 }; precondition(builds == 2)
        let photo = Data((0..<(256 * 1024)).map { UInt8(truncatingIfNeeded: $0 * 31) })
        for i in sample.staff.indices { sample.staff[i].photoData = photo }
        let writer = ShiftPersistenceWriter()
        let syncPulse = Pulse()
        let syncTask = Task { @MainActor in while !Task.isCancelled { syncPulse.beat(); try? await Task.sleep(for: .milliseconds(2)) } }
        try await Task.sleep(for: .milliseconds(30))
        let synchronous = measured(1) { try! ShiftPersistenceWriter.encode(sample).write(to: file, options: .atomic) }
        try await Task.sleep(for: .milliseconds(20)); syncTask.cancel()
        let asyncPulse = Pulse()
        let asyncTask = Task { @MainActor in while !Task.isCancelled { asyncPulse.beat(); try? await Task.sleep(for: .milliseconds(2)) } }
        try await Task.sleep(for: .milliseconds(20))
        let start = ProcessInfo.processInfo.systemUptime, ticket = writer.reserve()
        let bytes = try await writer.write(sample, to: file, ticket: ticket)
        let asynchronous = (ProcessInfo.processInfo.systemUptime - start) * 1000
        try await Task.sleep(for: .milliseconds(20)); asyncTask.cancel()
        let decoded = try JSONDecoder().decode(ShiftData.self, from: bytes)
        precondition(decoded.assignments == sample.assignments && decoded.staff == sample.staff)
        // A delayed stale async job is deliberately submitted AFTER the latest flush.
        let staleTicket = writer.reserve()
        var latest = sample; latest.staff[0].name = "Latest durable edit"
        _ = try writer.writeSynchronously(latest, to: file)
        do { _ = try await writer.write(sample, to: file, ticket: staleTicket); preconditionFailure("stale write accepted") }
        catch ShiftPersistenceError.superseded { }
        let durable = try JSONDecoder().decode(ShiftData.self, from: Data(contentsOf: file))
        precondition(durable.staff[0].name == latest.staff[0].name)
        // Cloud installation copies the old state, and cancelled generations leave it intact.
        let safety = directory.appendingPathComponent("safety.json")
        try? FileManager.default.removeItem(at: safety)
        let remoteBytes = try ShiftPersistenceWriter.encode(sample)
        _ = try await writer.install(remoteBytes, to: file, ticket: writer.reserve(), preservingTo: safety)
        let preserved = try JSONDecoder().decode(ShiftData.self, from: Data(contentsOf: safety))
        precondition(preserved.staff[0].name == "Latest durable edit")
        try? FileManager.default.removeItem(at: safety)
        var failureDetected = false
        do { _ = try await writer.write(sample, to: directory.appendingPathComponent("absent/subdir/file.json"), ticket: writer.reserve()) }
        catch { failureDetected = true }
        precondition(failureDetected)
        let safetyDirectory = directory.appendingPathComponent("safety-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: safetyDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: safetyDirectory) }
        let manual = safetyDirectory.appendingPathComponent("hotel-shift-before-restore-" + UUID().uuidString + ".json")
        try Data("manual".utf8).write(to: manual)
        let unrelated = safetyDirectory.appendingPathComponent("user-backup.json")
        try Data("user".utf8).write(to: unrelated)
        for number in 0..<6 {
            let copy = safetyDirectory.appendingPathComponent("hotel-shift-before-cloud-sync-" + UUID().uuidString + ".json")
            try Data("auto".utf8).write(to: copy)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(number))], ofItemAtPath: copy.path)
        }
        await writer.pruneAutomaticCloudCopies(in: safetyDirectory)
        let remaining = try FileManager.default.contentsOfDirectory(at: safetyDirectory, includingPropertiesForKeys: nil)
        precondition(remaining.filter { $0.lastPathComponent.hasPrefix("hotel-shift-before-cloud-sync-") }.count == 3)
        precondition(FileManager.default.fileExists(atPath: manual.path) && FileManager.default.fileExists(atPath: unrelated.path))
        let result: [String: Any] = [
            "environment": "Optimized macOS Swift microbenchmark; not physical iPad FPS",
            "staff": sample.staff.count, "shifts": sample.assignments.count, "photo_payload_MiB": 25,
            "index_build_ms": indexBuild, "lookup_775_linear_ms": linear, "lookup_775_indexed_ms": indexed,
            "lookup_speedup": linear / indexed, "sync_encode_write_ms": synchronous,
            "async_encode_write_elapsed_ms": asynchronous, "sync_actor_max_gap_ms": syncPulse.maximumGap,
            "async_actor_max_gap_ms": asyncPulse.maximumGap, "async_actor_beats": asyncPulse.count,
            "json_bytes": bytes.count, "render_rebuilds_per_1000_unchanged_queries": 1,
            "checks": ["index-equivalence", "duplicate-order", "cache-invalidation", "photo-JSON-roundtrip", "late-stale-writes-rejected", "restore-safety-copy", "write-error-propagation", "automatic-copy-retention", "manual-and-user-copies-preserved"]
        ]
        let output = directory.appendingPathComponent("fixed504_benchmark.json")
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        print(String(data: try Data(contentsOf: output), encoding: .utf8)!)
    }
}
