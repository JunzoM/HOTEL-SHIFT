import Foundation

enum ShiftPersistenceError: Error { case superseded }
// Tickets are reserved synchronously on the UI actor before an async call can suspend.
// A late-starting old job cannot overwrite a newer flush, edit or restore.
final class ShiftPersistenceWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "jp.hotelshift.persistence", qos: .utility, autoreleaseFrequency: .workItem)
    private let lock = NSLock()
    private var generation: UInt64 = 0
    @discardableResult func reserve() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1; return generation
    }
    private func current(_ ticket: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }; return generation == ticket
    }
    static func encode(_ snapshot: ShiftData) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }
    private func commit(_ bytes: Data, to url: URL, ticket: UInt64, preservingTo safety: URL? = nil) throws -> Data {
        guard current(ticket) else { throw ShiftPersistenceError.superseded }
        if let safety, FileManager.default.fileExists(atPath: url.path) { try FileManager.default.copyItem(at: url, to: safety) }
        guard current(ticket) else { throw ShiftPersistenceError.superseded }
        try bytes.write(to: url, options: .atomic)
        return bytes
    }
    func write(_ snapshot: ShiftData, to url: URL, ticket: UInt64) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard self.current(ticket) else { throw ShiftPersistenceError.superseded }
                    let bytes = try Self.encode(snapshot)
                    continuation.resume(returning: try self.commit(bytes, to: url, ticket: ticket))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func install(_ bytes: Data, to url: URL, ticket: UInt64, preservingTo safety: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try self.commit(bytes, to: url, ticket: ticket, preservingTo: safety)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    func writeSynchronously(_ snapshot: ShiftData, to url: URL) throws -> Data {
        let ticket = reserve()
        return try queue.sync { try commit(Self.encode(snapshot), to: url, ticket: ticket) }
    }
    func pruneAutomaticCloudCopies(in directory: URL) async {
        await withCheckedContinuation { continuation in
            queue.async {
                let manager = FileManager.default
                let files = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])) ?? []
                let candidates = files.compactMap { url -> (URL, Date)? in
                    let prefix = "hotel-shift-before-cloud-sync-"
                    guard url.lastPathComponent.hasPrefix(prefix), url.pathExtension == "json",
                          UUID(uuidString: String(url.deletingPathExtension().lastPathComponent.dropFirst(prefix.count))) != nil,
                          let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]), values.isRegularFile == true else { return nil }
                    return (url, values.contentModificationDate ?? .distantPast)
                }.sorted { $0.1 > $1.1 }
                for (url, _) in candidates.dropFirst(3) { try? manager.removeItem(at: url) }
                continuation.resume()
            }
        }
    }

}
