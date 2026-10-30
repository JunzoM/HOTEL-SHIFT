import Foundation
import SwiftUI
import UIKit

@MainActor
final class ShiftStore: ObservableObject {
    @Published var data: ShiftData {
        didSet {
            pdfRevision &+= 1
            persistence.reserve()
            if let replacementLookup { lookupCache = replacementLookup }
            else if !valueOnlyEdit { lookupCache?.refresh(from: oldValue, to: data) }
            serializedSnapshot = nil
            scheduleSave()
        }
    }
    private(set) var pdfRevision: UInt64 = 0
    private var lookupCache: ShiftLookupIndex?
    private var replacementLookup: ShiftLookupIndex?
    private var valueOnlyEdit = false
    private func publishValueEdit(_ updated: ShiftData) {
        valueOnlyEdit = true
        defer { valueOnlyEdit = false }
        data = updated
    }
    private var lookup: ShiftLookupIndex {
        if let lookupCache { return lookupCache }
        let built = ShiftLookupIndex(data); lookupCache = built; return built
    }
    private let persistence = ShiftPersistenceWriter()
    private var serializedSnapshot: (revision: UInt64, bytes: Data)?
    private var activePersistence: (revision: UInt64, ticket: UInt64, task: Task<Data, Error>)?

    // FIXED467: Share one in-flight/completed preparation for identical inputs.
    private struct PDFPreparationKey: Equatable {
        let month: Date
        let options: [String]
        let flags: [Bool]
        let locationID: UUID
        let revision: UInt64
        let calendar: Calendar
        let exportDay: Date
    }
    private var preparedPDF: (id: UUID, key: PDFPreparationKey, task: Task<URL?, Never>)?
    @Published var incomingRequestLinks: [IncomingLeaveLink] = []
    @Published var selectedLocationID: UUID
    private var pendingSave: Task<Void, Never>?
    private var needsSave = false
    @Published private(set) var storageWarning: String? = nil
    private var storageWriteBlocked = false
    let cloudSync = CloudSync()
    private(set) var cloudImportInProgress = false

    func acknowledgeStorageWarning() { storageWarning = nil }

    private var fileURL: URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("hotel-shift-data.json")
    }

    struct InitialLoad: @unchecked Sendable {
        let data: ShiftData
        let fresh: Bool
        let migrated: Bool
        let failed: Bool
        let index: ShiftLookupIndex
    }
    nonisolated static func prepareInitialLoad() -> InitialLoad {
        let isFreshInstall = !FileManager.default.fileExists(atPath: Self.defaultFileURL.path)
        let initialData: ShiftData
        var failedToLoadExistingData = false
        if let saved = try? Data(contentsOf: Self.defaultFileURL),
           let decoded = Self.decodeCompatibleData(saved),
           Self.isValidBackup(decoded) {
            initialData = decoded
        } else {
            // Never silently destroy a damaged or incompatible user data file.
            // Preserve it outside the live filename for later manual recovery.
            if FileManager.default.fileExists(atPath: Self.defaultFileURL.path) {
                failedToLoadExistingData = true
                let recoveryURL = Self.defaultFileURL.deletingLastPathComponent()
                    .appendingPathComponent("hotel-shift-recovery-\(UUID().uuidString).json")
                do {
                    try FileManager.default.copyItem(at: Self.defaultFileURL, to: recoveryURL)
                } catch {
                    NSLog("HOTEL SHIFT: recovery copy failed: %@", String(describing: error))
                }
            }
            initialData = SampleShiftData.make()
        }
        // Older backups do not contain location IDs. Assign their records to the
        // first facility so existing data remains visible after upgrading.
        var migrated = initialData
        let requiresMigration = migrated.staff.contains { $0.locationID == nil }
            || migrated.assignments.contains { $0.locationID == nil }
        let fallbackID = migrated.locations.first?.id ?? UUID()
        for index in migrated.staff.indices where migrated.staff[index].locationID == nil {
            migrated.staff[index].locationID = fallbackID
        }
        // Resolve staff-to-facility associations once during startup migration.
        // Avoid repeatedly searching the entire staff array for every shift.
        let staffLocations = Dictionary(uniqueKeysWithValues: migrated.staff.map {
            ($0.id, $0.locationID ?? fallbackID)
        })
        for index in migrated.assignments.indices where migrated.assignments[index].locationID == nil {
            migrated.assignments[index].locationID = staffLocations[migrated.assignments[index].staffID] ?? fallbackID
        }
        return InitialLoad(data: migrated, fresh: isFreshInstall, migrated: requiresMigration,
                           failed: failedToLoadExistingData, index: ShiftLookupIndex(migrated))
    }
    init(prepared: InitialLoad? = nil) {
        let loaded = prepared ?? Self.prepareInitialLoad()
        self.data = loaded.data
        self.selectedLocationID = loaded.data.locations.first?.id ?? UUID()
        self.lookupCache = loaded.index
        if loaded.failed {
            storageWriteBlocked = true
            storageWarning = "保存済みデータを読み込めませんでした。元のデータファイルは上書きしていません。表示中のサンプルデータへの変更は保存されません。元ファイルを保管し、バックアップから復元してください。"
        }
        if loaded.fresh || loaded.migrated { scheduleSave() }
        cloudSync.attach(self)
    }

    // Repair only legacy request records missing a facility ID; reject other invalid data.
    nonisolated private static func decodeCompatibleData(_ bytes: Data) -> ShiftData? {
        if let direct = try? JSONDecoder().decode(ShiftData.self, from: bytes) { return direct }
        guard var root = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              let locations = root["locations"] as? [[String: Any]],
              let fallback = locations.first?["id"] as? String,
              let staff = root["staff"] as? [[String: Any]] else { return nil }
        var staffLocations: [String: String] = [:]
        for person in staff {
            if let id = person["id"] as? String {
                staffLocations[id] = (person["locationID"] as? String) ?? fallback
            }
        }
        if var requests = root["requests"] as? [[String: Any]] {
            for index in requests.indices where requests[index]["locationID"] == nil {
                guard let staffID = requests[index]["staffID"] as? String,
                      let location = staffLocations[staffID] else { return nil }
                requests[index]["locationID"] = location
            }
            root["requests"] = requests
        }
        guard let patched = try? JSONSerialization.data(withJSONObject: root) else { return nil }
        return try? JSONDecoder().decode(ShiftData.self, from: patched)
    }

    nonisolated private static var defaultFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("hotel-shift-data.json")
    }

    var selectedLocation: HotelLocation? { data.locations.first { $0.id == selectedLocationID } }
    var selectedStaff: [StaffMember] { (lookup.staffByLocation[selectedLocationID] ?? []).map { data.staff[$0] } }
    func staffMember(id: UUID) -> StaffMember? {
        guard let i = lookup.staffByID[id], data.staff[i].locationID == selectedLocationID else { return nil }
        return data.staff[i]
    }
    var selectedAssignmentCount: Int { lookup.assignmentsByLocation[selectedLocationID]?.count ?? 0 }
    var selectedAssignments: [ShiftAssignment] { (lookup.assignmentsByLocation[selectedLocationID] ?? []).map { data.assignments[$0] } }
    func selectedAssignments(inMonth monthKey: String) -> [ShiftAssignment] {
        (lookup.assignmentsByMonth[.init(location: selectedLocationID, value: monthKey)] ?? []).map { data.assignments[$0] }
    }
    func selectedAssignments(on dates: Set<String>) -> [ShiftAssignment] {
        lookup.assignmentPositions(location: selectedLocationID, days: dates).map { data.assignments[$0] }
    }
    func assignment(staffID: UUID, dateKey: String) -> ShiftAssignment? {
        guard let i = lookup.assignmentByCell[.init(location: selectedLocationID, staff: staffID, day: dateKey)] else { return nil }
        return data.assignments[i]
    }
    func hasApprovedLeave(staffID: UUID, dateKey: String) -> Bool {
        let requests = data.requests ?? []
        return (lookup.requestsByCell[.init(location: selectedLocationID, staff: staffID, day: dateKey)] ?? []).contains { requests[$0].status == .approved }
    }
    var selectedRequestsUnsorted: [ShiftRequest] {
        let requests = data.requests ?? []
        return (lookup.requestsByLocation[selectedLocationID] ?? []).map { requests[$0] }
    }
    var selectedRequests: [ShiftRequest] { selectedRequestsUnsorted.sorted { $0.dateKey < $1.dateKey } }

    // FIXED488: Receive one staff's text application without duplicating live requests.
    func receiveRequestText(expectedStaff: StaffMember, dateKeys: [String], reason: String) throws -> (added: Int, skipped: Int) {
        return try receiveRequestAtLocation(expectedStaff: expectedStaff, locationID: selectedLocationID, dateKeys: dateKeys, reason: reason)
    }

    func receiveRequestAtLocation(expectedStaff: StaffMember, locationID: UUID, dateKeys: [String], reason: String) throws -> (added: Int, skipped: Int) {
        guard data.locations.contains(where: { $0.id == locationID }) else { throw RequestWorkflowError(message: "店舗が見つかりません。受け取り先を確認してください。") }
        guard !storageWriteBlocked else { throw RequestWorkflowError(message: "保存が保護されています。バックアップ・復元画面を確認してください。") }
        guard expectedStaff.locationID == locationID, expectedStaff.isActive,
              data.staff.contains(expectedStaff) else { throw RequestWorkflowError(message: "スタッフまたは店舗が変更されました。開き直してください。") }
        let keys = Set(dateKeys).sorted()
        guard !keys.isEmpty, keys.count <= 62, keys.allSatisfy({ key in
            guard let date = Date.keyFormatter.date(from: key) else { return false }
            return date.shiftDateKey == key
        }) else { throw RequestWorkflowError(message: "有効な日付を1〜62日選択してください。") }
        var requests = data.requests ?? []
        let taken = Set(requests.filter { $0.locationID == locationID && $0.staffID == expectedStaff.id && $0.status != .rejected }.map(\.dateKey))
        let fresh = keys.filter { !taken.contains($0) }
        let note = String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        for key in fresh { requests.append(ShiftRequest(staffID: expectedStaff.id, dateKey: key, reason: note.isEmpty ? "希望休" : note, locationID: locationID)) }
        if !fresh.isEmpty { data.requests = requests }
        return (fresh.count, keys.count - fresh.count)
    }

    // Validate the complete confirmation snapshot before committing the batch once.
    func decideRequestBatch(expected: [ShiftRequest], staffSnapshot: [StaffMember], assignmentSnapshot: [ShiftAssignment], locationID: UUID, status: ShiftRequestStatus, alsoOff: Bool) throws {
        guard !storageWriteBlocked else { throw RequestWorkflowError(message: "保存が保護されています。バックアップ・復元画面を確認してください。") }
        guard locationID == selectedLocationID, !expected.isEmpty, Set(expected.map(\.id)).count == expected.count else { throw RequestWorkflowError(message: "店舗または対象が変わりました。再選択してください。") }
        guard selectedStaff == staffSnapshot, !alsoOff || selectedAssignments == assignmentSnapshot else { throw RequestWorkflowError(message: "スタッフまたはシフトが更新されました。最新の一覧から再確認してください。") }
        var next = data
        var requests = next.requests ?? []
        let requestPositions = Dictionary(grouping: requests.indices) { requests[$0].id }
        let staffIDs = Set(staffSnapshot.map(\.id))
        for request in expected {
            guard request.locationID == locationID,
                  (requestPositions[request.id] ?? []).contains(where: { requests[$0] == request }),
                  staffIDs.contains(request.staffID) else { throw RequestWorkflowError(message: "申請が更新・削除されました。最新の一覧から再確認してください。") }
        }
        let now = Date()
        for request in expected {
            guard let index = requestPositions[request.id]?.first else { continue }
            if requests[index].status != status { requests[index].status = status; requests[index].updatedAt = now }
        }
        if status == .approved && alsoOff {
            let dates = Set(expected.map(\.dateKey))
            let positions = lookup.assignmentPositions(location: locationID, days: dates)
            var byCell = Dictionary(grouping: positions) {
                ScheduleGridKey(staffID: next.assignments[$0].staffID, dateKey: next.assignments[$0].dateKey)
            }
            for request in expected {
                let key = ScheduleGridKey(staffID: request.staffID, dateKey: request.dateKey)
                let indices = byCell[key] ?? []
                guard indices.count <= 1 else { throw RequestWorkflowError(message: "同じ日に複数のシフトがあります。シフト画面で整理してください。") }
                if let index = indices.first {
                    // Keep existing paid leave and rest records intact.
                    if [.off, .paidLeave, .afterNight].contains(next.assignments[index].type) { continue }
                    next.assignments[index].type = .off
                    next.assignments[index].customStartMinutes = nil
                    next.assignments[index].customEndMinutes = nil
                    next.assignments[index].customBreakMinutes = nil
                    next.assignments[index].customBreakStartMinutes = nil
                    next.assignments[index].patternNameSnapshot = nil
                } else {
                    byCell[key] = [next.assignments.count]
                    next.assignments.append(ShiftAssignment(staffID: request.staffID, dateKey: request.dateKey, type: .off, locationID: locationID))
                }
            }
        }
        next.requests = requests
        data = next
    }

    func deleteRequestSafely(_ expected: ShiftRequest) throws {
        guard !storageWriteBlocked, expected.locationID == selectedLocationID,
              (data.requests ?? []).contains(expected) else { throw RequestWorkflowError(message: "申請または店舗が変更されました。最新の一覧を確認してください。") }
        data.requests = (data.requests ?? []).filter { $0.id != expected.id }
    }

    func addRequest(staffID: UUID, date: Date, reason: String) {
        addRequests(staffID: staffID, dates: [date], reason: reason)
    }

    func addRequests(staffID: UUID, dates: [Date], reason: String) {
        let cleaned = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !dates.isEmpty,
              selectedStaff.contains(where: { $0.id == staffID }) else { return }
        var requests = data.requests ?? []
        // Build the existing-key set once. This avoids a full-array scan for
        // every selected date, and also deduplicates repeated input dates.
        var existingKeys = Set(requests.lazy.filter {
            $0.locationID == self.selectedLocationID && $0.staffID == staffID && $0.reason == cleaned
        }.map(\.dateKey))
        var changed = false
        for date in dates {
            let key = date.shiftDateKey
            guard existingKeys.insert(key).inserted else { continue }
            requests.append(ShiftRequest(staffID: staffID, dateKey: key,
                                         reason: cleaned, locationID: selectedLocationID))
            changed = true
        }
        // Do not publish or write JSON when the selection adds nothing.
        if changed { data.requests = requests }
    }

    func setRequestStatus(_ request: ShiftRequest, status: ShiftRequestStatus) {
        guard var requests = data.requests, let index = requests.firstIndex(where: { $0.id == request.id && $0.locationID == selectedLocationID }),
              data.staff.contains(where: { $0.id == requests[index].staffID && $0.locationID == selectedLocationID }) else { return }
        guard requests[index].status != status else { return }
        requests[index].status = status
        requests[index].updatedAt = Date()
        data.requests = requests
    }

    func deleteRequest(_ request: ShiftRequest) {
        guard let requests = data.requests,
              requests.contains(where: { $0.id == request.id && $0.locationID == selectedLocationID }) else { return }
        data.requests = requests.filter { !($0.id == request.id && $0.locationID == selectedLocationID) }
    }

    func assignment(staffID: UUID, date: Date) -> ShiftAssignment? {
        assignment(staffID: staffID, dateKey: date.shiftDateKey)
    }

    func setShift(staffID: UUID, date: Date, type: ShiftType, note: String? = nil) {
        // Reject stale edit sheets from a previously selected hotel.
        guard data.staff.contains(where: { $0.id == staffID && $0.locationID == selectedLocationID }) else { return }
        let preset = (data.patterns ?? []).first { $0.locationID == selectedLocationID && $0.basicShiftType == type }
        var next = data
        let key = date.shiftDateKey
        let currentWage = next.staff.first(where: { $0.id == staffID })?.hourlyWage
        if let index = next.assignments.firstIndex(where: { $0.locationID == selectedLocationID && $0.staffID == staffID && $0.dateKey == key }) {
            if next.assignments[index].type == type && (note == nil || next.assignments[index].note == note) { return }
            if next.assignments[index].type != type {
                next.assignments[index].patternNameSnapshot = nil
                // Custom times belong to the previous shift type, not the new one.
                next.assignments[index].customStartMinutes = preset?.customStartMinutes
                next.assignments[index].customEndMinutes = preset?.customEndMinutes
                next.assignments[index].customBreakMinutes = preset?.customBreakMinutes
                next.assignments[index].customBreakStartMinutes = preset?.customBreakStartMinutes
            }
            if next.assignments[index].hourlyWageSnapshot == nil { next.assignments[index].hourlyWageSnapshot = currentWage }
            next.assignments[index].type = type
            if let note { next.assignments[index].note = note }
        } else {
            // FIXED252: Paused staff retain historical shifts, but cannot receive new ones.
            guard next.staff.contains(where: { $0.id == staffID && $0.locationID == selectedLocationID && $0.isActive }) else { return }
            next.assignments.append(ShiftAssignment(staffID: staffID, dateKey: key, type: type, note: note ?? "", locationID: selectedLocationID, customStartMinutes: preset?.customStartMinutes, customEndMinutes: preset?.customEndMinutes, customBreakMinutes: preset?.customBreakMinutes, customBreakStartMinutes: preset?.customBreakStartMinutes, hourlyWageSnapshot: currentWage))
        }
        if next.assignments.count == data.assignments.count { publishValueEdit(next) }
        else { data = next }
    }

    func setShiftTimes(staffID: UUID, date: Date, startMinutes: Int, endMinutes: Int, breakMinutes: Int? = nil, breakStartMinutes: Int? = nil) {
        // Reject stale edit sheets from a previously selected hotel.
        guard data.staff.contains(where: { $0.id == staffID && $0.locationID == selectedLocationID }) else { return }
        var next = data
        let key = date.shiftDateKey
        let currentWage = next.staff.first(where: { $0.id == staffID })?.hourlyWage
        let safeStart = min(max(startMinutes, 0), 1439)
        let safeEnd = min(max(endMinutes, safeStart + 15), 2879)
        let safeBreak = breakMinutes.map { min(max(0, $0), safeEnd - safeStart) }
        let safeBreakStart = breakStartMinutes.map { min(max(safeStart, $0), safeEnd - (safeBreak ?? 0)) }
        if let index = next.assignments.firstIndex(where: { $0.locationID == selectedLocationID && $0.staffID == staffID && $0.dateKey == key }) {
            let old = next.assignments[index]
            if old.customStartMinutes == safeStart && old.customEndMinutes == safeEnd && old.customBreakMinutes == safeBreak && old.customBreakStartMinutes == safeBreakStart { return }
            if next.assignments[index].hourlyWageSnapshot == nil { next.assignments[index].hourlyWageSnapshot = currentWage }
            next.assignments[index].customStartMinutes = safeStart
            next.assignments[index].customEndMinutes = safeEnd
            next.assignments[index].customBreakMinutes = safeBreak
            next.assignments[index].customBreakStartMinutes = safeBreakStart
        } else {
            // FIXED252: The time editor must obey the same paused-staff rule.
            guard next.staff.contains(where: { $0.id == staffID && $0.locationID == selectedLocationID && $0.isActive }) else { return }
            next.assignments.append(ShiftAssignment(staffID: staffID, dateKey: key, type: .day, note: "", locationID: selectedLocationID, customStartMinutes: safeStart, customEndMinutes: safeEnd, customBreakMinutes: safeBreak, customBreakStartMinutes: safeBreakStart, hourlyWageSnapshot: currentWage))
        }
        if next.assignments.count == data.assignments.count { publishValueEdit(next) }
        else { data = next }
    }

    // FIXED477: All bar edits are atomic, scoped and checked against the captured value.
    func applyDayTimeline(staffID: UUID, date: Date, span: DayTimelineMath.Span,
                          locationID: UUID, expected: ShiftAssignment?, allowLeave: Bool = false) throws -> DayShiftChange? {
        guard !storageWriteBlocked else { throw DayShiftEditError.storage }
        guard locationID == selectedLocationID else { throw DayShiftEditError.changed }
        guard data.staff.contains(where: { $0.id == staffID && $0.locationID == locationID && $0.isActive }) else { throw DayShiftEditError.unavailable }
        guard span.start >= 0, span.start < 1440, span.end >= span.start + 15, span.end <= 2879 else { throw DayShiftEditError.invalid }
        let key = date.shiftDateKey
        let index = data.assignments.firstIndex { $0.locationID == locationID && $0.staffID == staffID && $0.dateKey == key }
        let current = index.map { data.assignments[$0] }
        guard current == expected else { throw DayShiftEditError.changed }
        guard current == nil || DayTimelineMath.span(current) != nil else { throw DayShiftEditError.changed }
        if !allowLeave && selectedRequestsUnsorted.contains(where: { $0.staffID == staffID && $0.dateKey == key && $0.status == .approved }) {
            throw DayShiftEditError.leave
        }
        let wage = data.staff.first { $0.id == staffID }?.hourlyWage
        var next = current ?? ShiftAssignment(staffID: staffID, dateKey: key, type: .day, locationID: locationID, hourlyWageSnapshot: wage)
        if next.hourlyWageSnapshot == nil { next.hourlyWageSnapshot = wage }
        next.customStartMinutes = span.start
        next.customEndMinutes = span.end
        let duration = span.end - span.start
        if let rest = next.customBreakMinutes { next.customBreakMinutes = min(max(0, rest), duration) }
        if let breakStart = next.customBreakStartMinutes {
            let rest = next.customBreakMinutes ?? min(duration, duration > 480 ? 60 : (duration > 360 ? 45 : 0))
            next.customBreakStartMinutes = min(max(span.start, breakStart), span.end - rest)
        }
        guard next != current else { return nil }
        var updated = data.assignments
        if let index { updated[index] = next } else { updated.append(next) }
        data.assignments = updated
        return DayShiftChange(locationID: locationID, staffID: staffID, dateKey: key, before: current, after: next)
    }

    func restoreDayTimeline(_ change: DayShiftChange, undo: Bool) throws {
        guard !storageWriteBlocked else { throw DayShiftEditError.storage }
        guard selectedLocationID == change.locationID else { throw DayShiftEditError.changed }
        guard data.staff.contains(where: { $0.id == change.staffID && $0.locationID == change.locationID && $0.isActive }) else { throw DayShiftEditError.unavailable }
        let index = data.assignments.firstIndex { $0.locationID == change.locationID && $0.staffID == change.staffID && $0.dateKey == change.dateKey }
        let current = index.map { data.assignments[$0] }
        let expected = undo ? change.after : change.before
        let target = undo ? change.before : change.after
        guard current == expected else { throw DayShiftEditError.changed }
        if DayTimelineMath.span(target) != nil && selectedRequestsUnsorted.contains(where: { $0.staffID == change.staffID && $0.dateKey == change.dateKey && $0.status == .approved }) {
            throw DayShiftEditError.leave
        }
        var updated = data.assignments
        if let index {
            if let target { updated[index] = target } else { updated.remove(at: index) }
        } else if let target { updated.append(target) }
        data.assignments = updated
    }

    // FIXED478: Validate the whole selection before applying any week/month edit.
    func applyScheduleGrid(_ edits: [ScheduleGridEdit], locationID: UUID, revision: UInt64,
                           allowLeave: Bool = false) throws -> ScheduleGridChange? {
        guard !storageWriteBlocked else { throw DayShiftEditError.storage }
        guard locationID == selectedLocationID, revision == pdfRevision else { throw DayShiftEditError.changed }
        guard !edits.isEmpty else { return nil }
        guard Set(edits.map(\.key)).count == edits.count else { throw DayShiftEditError.invalid }
        let activeStaff = Set(selectedStaff.filter(\.isActive).map(\.id))
        let requestedDays = Set(edits.map { $0.key.dateKey })
        let validDays = Set(requestedDays.filter { $0.count == 10 && Date.keyFormatter.date(from: $0)?.shiftDateKey == $0 })
        let positions = lookup.assignmentPositions(location: locationID, days: requestedDays)
        let byCell = Dictionary(grouping: positions) {
            ScheduleGridKey(staffID: data.assignments[$0].staffID, dateKey: data.assignments[$0].dateKey)
        }
        for edit in edits {
            guard activeStaff.contains(edit.key.staffID) else { throw DayShiftEditError.unavailable }
            guard validDays.contains(edit.key.dateKey) else { throw DayShiftEditError.invalid }
            let matches = byCell[edit.key] ?? []
            guard matches.count <= 1, matches.first.map({ data.assignments[$0] }) == edit.before else { throw DayShiftEditError.changed }
            if let next = edit.after {
                guard next.staffID == edit.key.staffID, next.dateKey == edit.key.dateKey, next.locationID == locationID,
                      ShiftMinuteValidation.valid(next) else { throw DayShiftEditError.invalid }
                if !allowLeave && hasApprovedLeave(staffID: edit.key.staffID, dateKey: edit.key.dateKey) && DayTimelineMath.span(next) != nil { throw DayShiftEditError.leave }
            }
        }
        let changes = edits.filter { $0.before != $0.after }
        guard !changes.isEmpty else { return nil }
        var updated: [ShiftAssignment]
        if changes.allSatisfy({ $0.before != nil && $0.after != nil && $0.before?.id == $0.after?.id }) {
            // Positions and identities are stable: copy on write once, then touch edited rows only.
            updated = data.assignments
            for edit in changes {
                if let index = byCell[edit.key]?.first, let after = edit.after { updated[index] = after }
            }
        } else {
            // Insert/delete or identity replacement retains the original full-array semantics.
            let replacements = Dictionary(uniqueKeysWithValues: changes.map { ($0.key, $0) })
            var replaced = Set<ScheduleGridKey>()
            updated = data.assignments.compactMap { current in
                let key = ScheduleGridKey(staffID: current.staffID, dateKey: current.dateKey)
                guard current.locationID == locationID, let edit = replacements[key] else { return current }
                replaced.insert(key)
                return edit.after
            }
            for edit in changes where !replaced.contains(edit.key) {
                if let next = edit.after { updated.append(next) }
            }
        }
        // Keep global ID validation, but avoid an N-element intermediate UUID array.
        guard Set(updated.lazy.map(\.id)).count == updated.count else { throw DayShiftEditError.invalid }
        if changes.allSatisfy({ $0.before != nil && $0.after != nil }) {
            var next = data; next.assignments = updated; publishValueEdit(next)
        } else { data.assignments = updated }
        return ScheduleGridChange(locationID: locationID, edits: changes)
    }

    func restoreScheduleGrid(_ change: ScheduleGridChange, undo: Bool) throws {
        let edits = undo ? change.edits.map { ScheduleGridEdit(key: $0.key, before: $0.after, after: $0.before) } : change.edits
        _ = try applyScheduleGrid(edits, locationID: change.locationID, revision: pdfRevision)
    }

    var selectedPatterns: [ShiftPattern] {
        let patterns = data.patterns ?? []
        return (lookup.patternsByLocation[selectedLocationID] ?? []).compactMap { patterns[$0].basicShiftType == nil ? patterns[$0] : nil }
    }
    var selectedBasicPatterns: [ShiftPattern] {
        ShiftPattern.basicDefaults(locationID: selectedLocationID).map { fallback in
            (data.patterns ?? []).first(where: { $0.locationID == selectedLocationID && $0.basicShiftType == fallback.basicShiftType }) ?? fallback
        }
    }
    private func isValidPattern(_ pattern: ShiftPattern) -> Bool {
        guard ShiftMinuteValidation.valid(start: pattern.customStartMinutes, end: pattern.customEndMinutes,
                  rest: pattern.customBreakMinutes, restStart: pattern.customBreakStartMinutes) else { return false }
        guard pattern.locationID == selectedLocationID,
              pattern.weekdays.count == 7,
              data.locations.contains(where: { $0.id == selectedLocationID }) else { return false }
        if let type = pattern.basicShiftType {
            guard [.early, .day, .late, .night].contains(type), pattern.scope == .everyone,
                  pattern.staffID == nil, pattern.weekdays == Array(repeating: type, count: 7),
                  pattern.customStartMinutes != nil else { return false }
        }
        if let from = pattern.validFrom, let until = pattern.validUntil,
           Calendar.current.startOfDay(for: from) > Calendar.current.startOfDay(for: until) { return false }
        if pattern.scope == .seasonal {
            guard pattern.validFrom != nil, pattern.validUntil != nil else { return false }
        }
        guard !pattern.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if let start = pattern.customStartMinutes {
            guard (0...1439).contains(start),
                  let end = pattern.customEndMinutes, (start + 15...2879).contains(end),
                  let rest = pattern.customBreakMinutes, (0...(end - start)).contains(rest) else { return false }
            if let restStart = pattern.customBreakStartMinutes {
                guard restStart >= start && restStart <= end - rest else { return false }
            }
        }
        if pattern.scope == .individual || pattern.scope == .seasonal {
            guard let staffID = pattern.staffID,
                  data.staff.contains(where: { $0.id == staffID && $0.locationID == selectedLocationID }) else { return false }
        }
        return true
    }
    var selectedPersonalWorkTimes: [PersonalWorkTime] {
        let items = data.personalWorkTimes ?? []
        return (lookup.personalByLocation[selectedLocationID] ?? []).map { items[$0] }
    }
    func savePersonalWorkTime(_ item: PersonalWorkTime) {
        guard item.locationID == selectedLocationID,
              data.staff.contains(where: { $0.id == item.staffID && $0.locationID == selectedLocationID }),
              !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (0...1439).contains(item.startMinutes),
              (1...2879).contains(item.endMinutes),
              item.endMinutes > item.startMinutes,
              (0...180).contains(item.breakMinutes),
              item.breakMinutes <= item.endMinutes - item.startMinutes else { return }
        var entries = data.personalWorkTimes ?? []
        if let index = entries.firstIndex(where: { $0.id == item.id }) {
            guard entries[index].staffID == item.staffID && entries[index].locationID == item.locationID else { return }
            entries[index] = item
        } else { entries.append(item) }
        data.personalWorkTimes = entries
    }
    // FIXED254: Atomic stale-editor check before changing a personal time slot.
    @discardableResult
    func savePersonalWorkTimeSafely(_ item: PersonalWorkTime, expectedOriginal: PersonalWorkTime?) -> Bool {
        guard item.locationID == selectedLocationID,
              let member = selectedStaff.first(where: { $0.id == item.staffID }),
              !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (0...1439).contains(item.startMinutes),
              (1...2879).contains(item.endMinutes),
              item.endMinutes - item.startMinutes >= 15,
              (0...180).contains(item.breakMinutes),
              item.breakMinutes <= item.endMinutes - item.startMinutes else { return false }
        var entries = data.personalWorkTimes ?? []
        if let expectedOriginal {
            guard expectedOriginal.id == item.id,
                  expectedOriginal.staffID == item.staffID,
                  expectedOriginal.locationID == item.locationID,
                  let index = entries.firstIndex(where: { $0.id == item.id }),
                  entries[index] == expectedOriginal else { return false }
            entries[index] = item
        } else {
            guard member.isActive, !entries.contains(where: { $0.id == item.id }) else { return false }
            entries.append(item)
        }
        data.personalWorkTimes = entries
        return true
    }
    // FIXED255: Delete only the exact record the user reviewed in the confirmation dialog.
    // An updated, moved or already-deleted record must never be removed by a stale dialog.
    @discardableResult
    func deletePersonalWorkTimeSafely(_ expected: PersonalWorkTime) -> Bool {
        guard expected.locationID == selectedLocationID,
              selectedStaff.contains(where: { $0.id == expected.staffID }) else { return false }
        var entries = data.personalWorkTimes ?? []
        guard let index = entries.firstIndex(where: { $0.id == expected.id }),
              entries[index] == expected else { return false }
        entries.remove(at: index)
        data.personalWorkTimes = entries
        return true
    }
    func deletePersonalWorkTime(_ item: PersonalWorkTime) {
        guard item.locationID == selectedLocationID else { return }
        data.personalWorkTimes = (data.personalWorkTimes ?? []).filter {
            !($0.id == item.id && $0.staffID == item.staffID && $0.locationID == item.locationID)
        }
    }
    func savePattern(_ pattern: ShiftPattern) {
        guard isValidPattern(pattern) else { return }
        var patterns = data.patterns ?? []
        if let i = patterns.firstIndex(where: { $0.id == pattern.id }) {
            // A stale editor cannot move a pattern between hotels.
            guard patterns[i].locationID == selectedLocationID else { return }
            guard patterns[i] != pattern else { return }
            patterns[i] = pattern
        } else { patterns.append(pattern) }
        data.patterns = patterns
    }
    // FIXED256: Compare the complete record shown when editing/deleting.
    // This prevents stale editors from overwriting another change or recreating a deleted pattern.
    @discardableResult
    func savePatternSafely(_ updated: ShiftPattern, expected: ShiftPattern?) -> Bool {
        guard updated.locationID == selectedLocationID, isValidPattern(updated) else { return false }
        var patterns = data.patterns ?? []
        if let type = updated.basicShiftType {
            guard !patterns.contains(where: { $0.locationID == updated.locationID && $0.basicShiftType == type && $0.id != updated.id }) else { return false }
        }
        if let expected {
            guard expected.id == updated.id,
                  expected.locationID == selectedLocationID,
                  let index = patterns.firstIndex(where: { $0.id == expected.id }),
                  patterns[index] == expected else { return false }
            patterns[index] = updated
        } else {
            guard !patterns.contains(where: { $0.id == updated.id }) else { return false }
            patterns.append(updated)
        }
        data.patterns = patterns
        return true
    }

    @discardableResult
    func deletePatternSafely(_ expected: ShiftPattern) -> Bool {
        guard expected.locationID == selectedLocationID else { return false }
        var patterns = data.patterns ?? []
        guard let index = patterns.firstIndex(where: { $0.id == expected.id }),
              patterns[index] == expected else { return false }
        patterns.remove(at: index)
        data.patterns = patterns
        return true
    }
    func deletePattern(_ pattern: ShiftPattern) {
        // A stale sheet must never remove a pattern from another hotel.
        guard let patterns = data.patterns,
              patterns.contains(where: { $0.id == pattern.id && $0.locationID == selectedLocationID }) else { return }
        data.patterns = patterns.filter { !($0.id == pattern.id && $0.locationID == selectedLocationID) }
    }
    struct LeaveShiftConflict: Identifiable {
        let staffID: UUID
        let staffName: String
        let dateKey: String
        let shiftType: ShiftType
        var id: String { "\(staffID.uuidString)|\(dateKey)" }
    }

    // Read-only inspection: neither shifts nor approved requests are modified.
    func approvedLeaveShiftConflictDetails() -> [LeaveShiftConflict] {
        struct StaffDay: Hashable {
            let staffID: UUID
            let dateKey: String
        }
        let approved = Set((data.requests ?? []).lazy.filter {
            $0.locationID == self.selectedLocationID && $0.status == .approved
        }.map { StaffDay(staffID: $0.staffID, dateKey: $0.dateKey) })
        let names = Dictionary(selectedStaff.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<StaffDay>()
        var conflicts: [LeaveShiftConflict] = []
        for assignment in data.assignments where assignment.locationID == selectedLocationID &&
            assignment.type != .off && assignment.type != .paidLeave && assignment.type != .afterNight {
            let key = StaffDay(staffID: assignment.staffID, dateKey: assignment.dateKey)
            guard approved.contains(key), seen.insert(key).inserted,
                  let name = names[assignment.staffID] else { continue }
            conflicts.append(LeaveShiftConflict(staffID: assignment.staffID,
                staffName: name, dateKey: assignment.dateKey, shiftType: assignment.type))
        }
        return conflicts.sorted {
            if $0.dateKey != $1.dateKey { return $0.dateKey < $1.dateKey }
            return $0.staffName < $1.staffName
        }
    }

    func approvedLeaveShiftConflicts() -> Int {
        approvedLeaveShiftConflictDetails().count
    }

    struct SeasonalPatternConflict: Identifiable {
        let staffName: String
        let dateKey: String
        let otherPatternName: String
        let otherPatternID: UUID
        var id: String { "\(dateKey)|\(otherPatternID.uuidString)|\(staffName)" }
    }

    // FIXED262: Preserve the actual generated shift type and effective time range.
    // Non-working shift types have no clock range; do not invent one for display.
    struct PatternRegisteredShift: Identifiable {
        let dateKey: String
        let type: ShiftType
        let startMinutes: Int?
        let endMinutes: Int?
        let breakMinutes: Int?
        // FIXED264: Calculated from the exact assignment written by the batch operation.
        let hourlyWage: Int
        let estimatedCost: Int
        var id: String { dateKey }

        var breakAndWorkLabel: String {
            guard let startMinutes, let endMinutes, endMinutes > startMinutes else {
                return "休憩・実働：時間設定なし"
            }
            let duration = endMinutes - startMinutes
            let rest = min(duration, max(0, breakMinutes ?? (duration > 480 ? 60 : (duration > 360 ? 45 : 0))))
            let net = duration - rest
            return String(format: "休憩 %d分 ・ 概算実働 %d時間%02d分", rest, net / 60, net % 60)
        }

        var timeLabel: String {
            guard let startMinutes, let endMinutes else { return "時間設定なし" }
            func clock(_ value: Int) -> String {
                String(format: "%02d:%02d", (value / 60) % 24, value % 60)
            }
            let followingDay = endMinutes >= 1440 ? "翌" : ""
            return "\(clock(startMinutes))〜\(followingDay)\(clock(endMinutes))"
        }
    }

    struct PatternStaffResult: Identifiable {
        let staffID: UUID
        let staffName: String
        let added: Int
        let registeredShifts: [PatternRegisteredShift]
        var estimatedCost: Int { registeredShifts.reduce(0) { $0 + $1.estimatedCost } }
        var id: UUID { staffID }
    }

    struct PatternApplicationResult {
        var staffResults: [PatternStaffResult] = []
        var added = 0
        var existingShifts = 0
        var approvedLeave = 0
        var reservedSeasonal = 0
        var overlappingSeasonal = 0
        var seasonalConflictDetails: [SeasonalPatternConflict] = []
    }

    @discardableResult
    func applyPattern(_ pattern: ShiftPattern, from start: Date, through end: Date) -> Int {
        applyPatternWithReport(pattern, from: start, through: end).added
    }

    func applyPatternWithReport(_ pattern: ShiftPattern, from start: Date, through end: Date, previewOnly: Bool = false) -> PatternApplicationResult {
        let cal = Calendar.current
        let first = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: end)
        // FIXED187: Compare calendar days, not the incidental clock times of
        // date pickers. Bound batch operations to one year to avoid freezing
        // the iPad or accidentally filling years of shifts in one tap.
        guard first <= last,
              let dayCount = cal.dateComponents([.day], from: first, to: last).day,
              dayCount < 366,
              isValidPattern(pattern),
              // Only apply the current saved version, never an old sheet snapshot.
              (data.patterns ?? []).contains(where: { $0.id == pattern.id && $0 == pattern }) else { return PatternApplicationResult() }
        let targets = selectedStaff.filter { $0.isActive && (pattern.scope == .everyone || $0.id == pattern.staffID) }
        var date = first
        // Index staff/day pairs once; avoid repeated full-array scans.
        struct StaffDay: Hashable {
            let staffID: UUID
            let dateKey: String
        }
        var occupied = Set(data.assignments.filter { $0.locationID == selectedLocationID }
            .map { StaffDay(staffID: $0.staffID, dateKey: $0.dateKey) })
        let approvedLeave = Set((data.requests ?? []).filter {
            $0.locationID == selectedLocationID && $0.status == .approved
        }.map { StaffDay(staffID: $0.staffID, dateKey: $0.dateKey) })
        // FIXED210: A seasonal rule reserves its matching staff/day even if the
        // ordinary weekly rule is applied first. No existing shift is changed.
        let seasonalPatterns = (data.patterns ?? []).filter {
            $0.locationID == selectedLocationID && $0.scope == .seasonal &&
            $0.staffID != nil && $0.validFrom != nil && $0.validUntil != nil &&
            $0.weekdays.count == 7 && $0.id != pattern.id && isValidPattern($0)
        }
        var additions: [ShiftAssignment] = []
        var report = PatternApplicationResult()
        var addedByStaff: [UUID: Int] = [:]
        var shiftsByStaff: [UUID: [PatternRegisteredShift]] = [:]
        while date <= last {
            let valid = (pattern.validFrom.map { date >= cal.startOfDay(for: $0) } ?? true) && (pattern.validUntil.map { date <= cal.startOfDay(for: $0) } ?? true)
            if valid {
                let weekday = (cal.component(.weekday, from: date) + 5) % 7
                let key = date.shiftDateKey
                for person in targets {
                    let staffDay = StaffDay(staffID: person.id, dateKey: key)
                    // Never let a regular pattern consume a day reserved by a
                    // seasonal pattern. Seasonal application remains explicit.
                    let matchingSeasonal = seasonalPatterns.filter { seasonal in
                        seasonal.staffID == person.id &&
                        date >= cal.startOfDay(for: seasonal.validFrom!) &&
                        date <= cal.startOfDay(for: seasonal.validUntil!)
                    }.sorted { left, right in
                        if left.name != right.name { return left.name < right.name }
                        return left.id.uuidString < right.id.uuidString
                    }
                    if !matchingSeasonal.isEmpty {
                        if pattern.scope == .seasonal {
                            report.overlappingSeasonal += 1
                            // Keep the preview bounded for long date ranges and many staff.
                            if report.seasonalConflictDetails.count < 100 {
                                for other in matchingSeasonal.prefix(100 - report.seasonalConflictDetails.count) {
                                    report.seasonalConflictDetails.append(SeasonalPatternConflict(
                                        staffName: person.name, dateKey: key,
                                        otherPatternName: other.name, otherPatternID: other.id))
                                }
                            }
                        } else { report.reservedSeasonal += 1 }
                        continue
                    }
                    // Existing shifts take precedence; approved leave blocks only empty cells.
                    if occupied.contains(staffDay) {
                        report.existingShifts += 1
                    } else if approvedLeave.contains(staffDay) {
                        report.approvedLeave += 1
                    } else {
                        occupied.insert(staffDay)
                        addedByStaff[person.id, default: 0] += 1
                        let shiftType = pattern.weekdays[weekday]
                        let defaultTimes: (Int, Int)?
                        switch shiftType {
                        case .early: defaultTimes = (360, 900)
                        case .day: defaultTimes = (540, 1080)
                        case .late: defaultTimes = (780, 1320)
                        case .night: defaultTimes = (1260, 1980)
                        default: defaultTimes = nil
                        }
                        let newAssignment = ShiftAssignment(staffID: person.id, dateKey: key,
                            type: shiftType, locationID: selectedLocationID,
                            customStartMinutes: pattern.customStartMinutes,
                            customEndMinutes: pattern.customEndMinutes,
                            customBreakMinutes: pattern.customBreakMinutes,
                            customBreakStartMinutes: pattern.customBreakStartMinutes,
                            hourlyWageSnapshot: person.hourlyWage,
                            patternNameSnapshot: pattern.name)
                        shiftsByStaff[person.id, default: []].append(PatternRegisteredShift(
                            dateKey: key, type: shiftType,
                            startMinutes: defaultTimes.map { pattern.customStartMinutes ?? $0.0 },
                            endMinutes: defaultTimes.map { pattern.customEndMinutes ?? $0.1 },
                            breakMinutes: defaultTimes == nil ? nil : pattern.customBreakMinutes,
                            hourlyWage: person.hourlyWage,
                            estimatedCost: ShiftLaborEstimate.cost(newAssignment, hourlyWage: person.hourlyWage)))
                        additions.append(newAssignment)
                    }
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        if !previewOnly && !additions.isEmpty { data.assignments.append(contentsOf: additions) }
        report.added = additions.count
        report.staffResults = targets.map { person in
            PatternStaffResult(staffID: person.id, staffName: person.name,
                               added: addedByStaff[person.id, default: 0],
                               registeredShifts: shiftsByStaff[person.id, default: []])
        }.sorted { left, right in
            if left.staffName != right.staffName { return left.staffName < right.staffName }
            return left.staffID.uuidString < right.staffID.uuidString
        }
        return report
    }

    func clearShift(staffID: UUID, date: Date) {
        guard data.staff.contains(where: { $0.id == staffID && $0.locationID == selectedLocationID }) else { return }
        let key = date.shiftDateKey
        guard data.assignments.contains(where: { $0.locationID == selectedLocationID && $0.staffID == staffID && $0.dateKey == key }) else { return }
        data.assignments.removeAll { $0.locationID == selectedLocationID && $0.staffID == staffID && $0.dateKey == key }
    }

    func exportCSV() async -> URL? {
        guard !storageWriteBlocked else { return nil }
        let rawHotelName = UserDefaults.standard.string(forKey: "hotelShift.hotelName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hotelName = rawHotelName.isEmpty ? "ホテル名未設定" : rawHotelName
        let safeHotelName = ExportFilename.component(hotelName)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeHotelName)_シフト一覧_\(Date().shiftDateKey)_\(UUID().uuidString).csv")
        let entries = selectedAssignments
        let staffByID = Dictionary(data.staff.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return await Task.detached(priority: .userInitiated) { () -> URL? in
        let sorted = entries.sorted { ($0.dateKey, staffByID[$0.staffID]?.name ?? "") < ($1.dateKey, staffByID[$1.staffID]?.name ?? "") }
        var rows = ["ホテル名,日付,氏名,部署,雇用形態,勤務区分,開始,終了,時給,メモ"]
        for assignment in sorted {
            guard let staff = staffByID[assignment.staffID] else { continue }
            let startText = assignment.customStartMinutes.map { String(format: "%02d:%02d", ($0 / 60) % 24, $0 % 60) } ?? assignment.type.start
            let endText = assignment.customEndMinutes.map {
                let clock = String(format: "%02d:%02d", ($0 / 60) % 24, $0 % 60)
                return $0 >= 1440 ? "翌" + clock : clock
            } ?? assignment.type.end
            let values = [hotelName, assignment.dateKey, staff.name, staff.department, staff.employment, assignment.type.rawValue, startText, endText, String(assignment.hourlyWageSnapshot ?? staff.hourlyWage), assignment.note]
            rows.append(values.map(Self.csvEscape).joined(separator: ","))
        }
        let csv = "\u{FEFF}" + rows.joined(separator: "\r\n")
        guard let encoded = csv.data(using: .utf8), (try? encoded.write(to: url, options: .atomic)) != nil else { return nil }
        return url
        }.value
    }

    // Use date buckets to support the current calendar while preserving source order/duplicates.
    private func pdfAssignments(month: Date) -> [ShiftAssignment] {
        let calendar = Calendar.current
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let dates = Set(range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: start)?.shiftDateKey })
        return selectedAssignments(on: dates)
    }

    func exportShiftPDF(month: Date, paperSize: String = "A4横", showStaffName: Bool = true, showWorkTime: Bool = true, showBreakTime: Bool = true, showMemo: Bool = true, showWage: Bool = false, department: String = "すべて", periodMode: String = "1か月") -> URL? {
        guard !storageWriteBlocked else { return nil }
        return Self.renderShiftPDF(month: month, paperSize: paperSize, showStaffName: showStaffName, showWorkTime: showWorkTime, showBreakTime: showBreakTime, showMemo: showMemo, showWage: showWage, department: department, periodMode: periodMode, selectedStaff: selectedStaff, assignments: pdfAssignments(month: month), selectedLocationID: selectedLocationID, locationName: selectedLocation?.name ?? "ホテル")
    }

    func exportShiftPDFAsync(month: Date, paperSize: String = "A4横", showStaffName: Bool = true, showWorkTime: Bool = true, showBreakTime: Bool = true, showMemo: Bool = true, showWage: Bool = false, department: String = "すべて", periodMode: String = "1か月") async -> URL? {
        guard !storageWriteBlocked else { return nil }
        guard !Task.isCancelled else { return nil }
        let calendar = Calendar.current
        let key = PDFPreparationKey(
            month: month, options: [paperSize, department, periodMode],
            flags: [showStaffName, showWorkTime, showBreakTime, showMemo, showWage],
            locationID: selectedLocationID, revision: pdfRevision,
            calendar: calendar, exportDay: calendar.startOfDay(for: Date()))
        if let preparedPDF, preparedPDF.key == key {
            let url = await preparedPDF.task.value
            // Awaiting a shared task allows the main actor's data/location to change.
            guard !Task.isCancelled, !storageWriteBlocked,
                  key.locationID == selectedLocationID, key.revision == pdfRevision else { return nil }
            if let url, FileManager.default.fileExists(atPath: url.path) { return url }
            // Another waiter may already have replaced this failed preparation.
            // Clear only the exact attempt we awaited, then join its replacement.
            if self.preparedPDF?.id == preparedPDF.id { self.preparedPDF = nil }
            if self.preparedPDF?.key == key {
                return await exportShiftPDFAsync(month: month, paperSize: paperSize,
                    showStaffName: showStaffName, showWorkTime: showWorkTime,
                    showBreakTime: showBreakTime, showMemo: showMemo, showWage: showWage,
                    department: department, periodMode: periodMode)
            }
        }
        // FIXED465: Capture value data on the main actor, then render off the UI thread.
        let staffSnapshot = selectedStaff
        let assignmentSnapshot = pdfAssignments(month: month)
        let locationID = selectedLocationID
        let locationName = selectedLocation?.name ?? "ホテル"
        let task = Task.detached(priority: .userInitiated) {
            Self.renderShiftPDF(month: month, paperSize: paperSize, showStaffName: showStaffName, showWorkTime: showWorkTime, showBreakTime: showBreakTime, showMemo: showMemo, showWage: showWage, department: department, periodMode: periodMode, selectedStaff: staffSnapshot,
                                assignments: assignmentSnapshot, selectedLocationID: locationID,
                                locationName: locationName)
        }
        let preparationID = UUID()
        preparedPDF = (preparationID, key, task)
        let url = await task.value
        // A failed preparation is retried by the next request.
        if url == nil, preparedPDF?.id == preparationID { preparedPDF = nil }
        guard !Task.isCancelled, !storageWriteBlocked,
              key.locationID == selectedLocationID, key.revision == pdfRevision else { return nil }
        return url
    }

    // FIXED473: Measure the complete name using character wrapping, never ellipsis.
    nonisolated private static func staffNameLayout(_ text: String, width: CGFloat, height: CGFloat,
                                                   font: UIFont) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byClipping
        let parts = text.components(separatedBy: "\n")
        let name = parts.first ?? text
        let characters = Array(name)
        var nameLines = [name]
        if characters.count > 7 {
            let middle = (characters.count + 1) / 2
            let spaces = characters.indices.filter { characters[$0].isWhitespace && $0 > 0 && $0 < characters.count - 1 }
            let split = spaces.min { abs($0 - middle) < abs($1 - middle) } ?? middle
            nameLines = [String(characters[..<split]).trimmingCharacters(in: .whitespaces),
                         String(characters[split...]).trimmingCharacters(in: .whitespaces)]
        }
        let lines = nameLines + Array(parts.dropFirst())
        let wrappedText = lines.joined(separator: "\n")
        var pointSize = font.pointSize
        while true {
            let result = NSAttributedString(string: wrappedText, attributes: [
                .font: font.withSize(pointSize), .paragraphStyle: style])
            let measured = result.boundingRect(
                with: CGSize(width: max(1, width - 1), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            let longestWidth = lines.map {
                ($0 as NSString).size(withAttributes: [.font: font.withSize(pointSize)]).width
            }.max() ?? 0
            if (measured.height <= height - 1 && longestWidth <= width - 1) || pointSize <= 0.5 {
                return result
            }
            pointSize = max(0.5, pointSize - 0.25)
        }
    }

    nonisolated private static func renderShiftPDF(month: Date, paperSize: String = "A4横", showStaffName: Bool = true, showWorkTime: Bool = true, showBreakTime: Bool = true, showMemo: Bool = true, showWage: Bool = false, department: String = "すべて", periodMode: String = "1か月", selectedStaff: [StaffMember], assignments: [ShiftAssignment], selectedLocationID: UUID, locationName: String) -> URL? {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        guard let dayRange = calendar.range(of: .day, in: .month, for: start) else { return nil }
        let allDays = dayRange.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
        let days: [Date]
        switch periodMode {
        case "前半": days = allDays.filter { calendar.component(.day, from: $0) <= 15 }
        case "後半": days = allDays.filter { calendar.component(.day, from: $0) >= 16 }
        default: days = allDays
        }
        let isPortrait = paperSize.hasSuffix("縦")
        // FIXED470: Keep monthly output in one table; compact identity columns instead.
        let splitMode = periodMode == "上下分割"
        let firstHalf = allDays.filter { calendar.component(.day, from: $0) <= 15 }
        let secondHalf = allDays.filter { calendar.component(.day, from: $0) >= 16 }
        let staff = selectedStaff.filter { $0.isActive && (department == "すべて" || $0.department == department) }.sorted { ($0.department, $0.name) < ($1.department, $1.name) }
        // Build a location-scoped lookup once per PDF export rather than
        // filtering and scanning all assignments for every staff/day cell.
        struct PDFShiftKey: Hashable {
            let staffID: UUID
            let dateKey: String
        }
        // Format dates once per export instead of once per staff/day cell.
        let dateKeys = Dictionary(uniqueKeysWithValues: allDays.map { ($0, $0.shiftDateKey) })
        let exportedDates = Set(dateKeys.values)
        var pdfAssignments: [PDFShiftKey: ShiftAssignment] = [:]
        for assignment in assignments where assignment.locationID == selectedLocationID && exportedDates.contains(assignment.dateKey) {
            let key = PDFShiftKey(staffID: assignment.staffID, dateKey: assignment.dateKey)
            // Match the previous first(where:) behavior for duplicate records.
            if pdfAssignments[key] == nil { pdfAssignments[key] = assignment }
        }
        let isA3 = paperSize.hasPrefix("A3")
        let landscapeWidth: CGFloat = isA3 ? 1191 : 842
        let landscapeHeight: CGFloat = isA3 ? 842 : 595
        let page = CGRect(x: 0, y: 0, width: isPortrait ? landscapeHeight : landscapeWidth, height: isPortrait ? landscapeWidth : landscapeHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let periodSuffix = periodMode == "前半" ? "_前半" : (periodMode == "後半" ? "_後半" : (splitMode ? "_上下半月分割" : ""))
        // FIXED198: Give each generated PDF its own URL. Reusing the same
        // filename overwrote a preview/share document when another export
        // was created with different settings for the same month.
        let safeFacility = ExportFilename.component(locationName)
        let filename = "\(safeFacility)_シフト_\(start.shiftDateKey.prefix(7))\(periodSuffix)_\(UUID().uuidString).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        let smallFont = UIFont.systemFont(ofSize: 6)
        let ink = UIColor(red: 0.08, green: 0.17, blue: 0.28, alpha: 1)
        let compactPortrait = paperSize == "A4縦" && periodMode == "1か月"
        // FIXED471: Compact identity columns and margins for portrait half-months too.
        let compactColumns = compactPortrait || (isPortrait && ["前半", "後半"].contains(periodMode))
        let left: CGFloat = compactColumns ? 12 : 22
        let top: CGFloat = 24
        // FIXED456: Adapt name-column width to the selected paper orientation.
        let usableWidth = page.width - left * 2
        let staffWidth: CGFloat = showStaffName
            ? min(showWage ? 165 : 140, usableWidth * (isPortrait ? 0.25 : 0.26))
            : 42
        // FIXED195: Keep long names, department labels and notes inside their
        // cells. UIKit string drawing does not automatically clip to a cell.
        // FIXED466: Reuse text measurement, font fitting and attributes for repeated cells.
        struct PDFTextLayoutKey: Hashable {
            let text: String
            let fontName: String
            let fontSize: CGFloat
            let width: CGFloat
            let height: CGFloat
            let color: UIColor
            let alignment: Int
            let centered: Bool
        }
        struct PDFTextLayout {
            let text: NSAttributedString
            let yOffset: CGFloat
            let height: CGFloat
        }
        var textLayouts: [PDFTextLayoutKey: PDFTextLayout] = [:]
        func draw(_ text: String, in rect: CGRect, font: UIFont, color: UIColor = .black, align: NSTextAlignment = .center, verticallyCentered: Bool = false) {
            guard rect.width > 0, rect.height > 0 else { return }
            let key = PDFTextLayoutKey(text: text, fontName: font.fontName,
                                       fontSize: font.pointSize, width: rect.width, height: rect.height,
                                       color: color, alignment: align.rawValue, centered: verticallyCentered)
            let prepared: PDFTextLayout
            if let cached = textLayouts[key] {
                prepared = cached
            } else {
                let style = NSMutableParagraphStyle()
                style.alignment = align
                style.lineBreakMode = .byTruncatingTail
                let lines = text.components(separatedBy: "\n")
                // FIXED461: Fit both dimensions, including compact IN/OUT rows.
                var fittedFont = font
                let lineCount = CGFloat(max(lines.count, 1))
                let heightScale = min(1, rect.height / (font.lineHeight * lineCount))
                fittedFont = font.withSize(max(0.5, font.pointSize * heightScale))
                let longestWidth = lines.map {
                    ($0 as NSString).size(withAttributes: [.font: fittedFont]).width
                }.max() ?? 0
                if longestWidth > rect.width {
                    fittedFont = fittedFont.withSize(max(0.5, fittedFont.pointSize * rect.width / longestWidth))
                }
                let clipped = text as NSString
                // FIXED462: Center the measured text block vertically in identity cells.
                var textRect = rect
                if verticallyCentered {
                    let measuredHeight = clipped.boundingRect(
                        with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: fittedFont, .paragraphStyle: style], context: nil).height
                    let textHeight = min(rect.height, ceil(measuredHeight))
                    textRect = CGRect(x: rect.minX, y: rect.midY - textHeight / 2,
                                      width: rect.width, height: textHeight)
                }
                prepared = PDFTextLayout(
                    text: NSAttributedString(string: text, attributes: [.font: fittedFont,
                                             .foregroundColor: color, .paragraphStyle: style]),
                    yOffset: textRect.minY - rect.minY, height: textRect.height)
                textLayouts[key] = prepared
            }
            UIGraphicsGetCurrentContext()?.saveGState()
            UIGraphicsGetCurrentContext()?.clip(to: rect)
            prepared.text.draw(in: CGRect(x: rect.minX, y: rect.minY + prepared.yOffset,
                                          width: rect.width, height: prepared.height))
            UIGraphicsGetCurrentContext()?.restoreGState()
        }
        struct PDFNameLayoutKey: Hashable {
            let text: String
            let width: CGFloat
            let height: CGFloat
        }
        var nameLayouts: [PDFNameLayoutKey: NSAttributedString] = [:]
        func drawStaffName(_ text: String, in rect: CGRect) {
            let key = PDFNameLayoutKey(text: text, width: rect.width, height: rect.height)
            let prepared: NSAttributedString
            if let cached = nameLayouts[key] { prepared = cached }
            else {
                prepared = Self.staffNameLayout(text, width: rect.width, height: rect.height,
                                               font: UIFont.boldSystemFont(ofSize: isA3 ? 14 : 12))
                nameLayouts[key] = prepared
            }
            let measured = prepared.boundingRect(
                with: CGSize(width: max(1, rect.width - 1), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            UIGraphicsGetCurrentContext()?.saveGState()
            UIGraphicsGetCurrentContext()?.clip(to: rect)
            prepared.draw(with: CGRect(x: rect.minX + 0.5, y: rect.midY - measured.height / 2,
                                       width: max(1, rect.width - 1), height: measured.height + 0.5),
                          options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            UIGraphicsGetCurrentContext()?.restoreGState()
        }
        let tableHeaderHeight: CGFloat = isA3 ? 34 : (isPortrait ? 28 : 30)
        let tableTitleHeight: CGFloat = 36
        // FIXED457: Printed roster follows the supplied reference: dark date header,
        // grey weekends, department dividers, IN/OUT lines and a right-hand total.
        func drawTable(_ tableDays: [Date], title tableTitle: String, y: CGFloat, height: CGFloat, context: UIGraphicsPDFRendererContext, tableStaff: [StaffMember]? = nil) {
            let roster = tableStaff ?? staff
            let tableWidth = page.width - left * 2
            let headerHeight = tableHeaderHeight
            let titleHeight = tableTitleHeight
            let departmentCount = Set(roster.map(\.department)).count
            let departmentHeight: CGFloat = splitMode ? 11 : 16
            let available = max(8, height - titleHeight - headerHeight - 5 - CGFloat(departmentCount) * departmentHeight)
            let rowHeight = splitMode
                ? min(isA3 ? 39 : 35, available / CGFloat(max(roster.count, 1)))
                : min(isA3 ? 36 : 30, available / CGFloat(max(roster.count, 1)))
            let numberWidth: CGFloat = compactColumns ? 20 : (isA3 ? 28 : 24)
            let inOutWidth: CGFloat = showWorkTime ? (compactPortrait ? 8 : 13) : 0
            let totalWidth: CGFloat = compactPortrait ? 24 : 35
            // FIXED474: Reserve seven full-width characters at the normal name font size.
            let nameFont = UIFont.boldSystemFont(ofSize: isA3 ? 14 : 12)
            let sevenCharacterWidth = ("田田田田田田田" as NSString).size(withAttributes: [.font: nameFont]).width + 6
            let nameWidth: CGFloat = showStaffName
                ? max(sevenCharacterWidth, compactColumns ? 0 : staffWidth - numberWidth - inOutWidth)
                : (compactColumns ? 28 : 45)
            let dayWidth = max(5, (tableWidth - numberWidth - nameWidth - inOutWidth - totalWidth) / CGFloat(max(tableDays.count, 1)))
            let headerY = y + titleHeight
            let black = UIColor.black
            let weekend = UIColor(white: 0.72, alpha: 1)
            let lightWeekend = UIColor(white: 0.94, alpha: 1)
            let borderColor = UIColor(white: 0.35, alpha: 1)
            let textFont = UIFont.boldSystemFont(ofSize: isA3 ? 13 : (isPortrait ? 10 : 11))
            // FIXED476: Store on the left, shift period in the center; no year/month line.
            draw(locationName, in: CGRect(x: left, y: y, width: tableWidth * 0.28, height: 17),
                 font: UIFont.boldSystemFont(ofSize: isA3 ? 16 : 13), color: ink,
                 align: .left, verticallyCentered: true)
            let periodTitle: String
            if let first = tableDays.first, let last = tableDays.last {
                periodTitle = "\(calendar.component(.month, from: first))月\(calendar.component(.day, from: first))日〜\(calendar.component(.month, from: last))月\(calendar.component(.day, from: last))日"
            } else { periodTitle = tableTitle }
            draw(periodTitle, in: CGRect(x: left + tableWidth * 0.30, y: y,
                                        width: tableWidth * 0.40, height: 17),
                 font: UIFont.boldSystemFont(ofSize: isA3 ? 16 : 13), color: ink,
                 align: .center, verticallyCentered: true)
            func cell(_ rect: CGRect, fill: UIColor, border: UIColor = .gray) {
                fill.setFill()
                UIRectFill(rect)
                border.setStroke()
                UIBezierPath(rect: rect).stroke()
            }
            func headerCell(_ label: String, x: CGFloat, width: CGFloat, font: UIFont? = nil) {
                let rect = CGRect(x: x, y: headerY, width: width, height: headerHeight)
                cell(rect, fill: black, border: black)
                draw(label, in: rect.insetBy(dx: 1, dy: 2), font: font ?? textFont, color: .white,
                     align: .center, verticallyCentered: true)
            }
            headerCell("No.", x: left, width: numberWidth,
                       font: UIFont.boldSystemFont(ofSize: compactColumns ? 9 : 11))
            headerCell(showStaffName ? "氏名" : "番号", x: left + numberWidth, width: nameWidth,
                       font: UIFont.boldSystemFont(ofSize: isA3 ? 13 : 11))
            if showWorkTime {
                headerCell("入\n出", x: left + numberWidth + nameWidth, width: inOutWidth)
            }
            let dayStartX = left + numberWidth + nameWidth + inOutWidth
            for (i, date) in tableDays.enumerated() {
                let weekday = calendar.component(.weekday, from: date)
                let weekendDay = weekday == 1 || weekday == 7
                let rect = CGRect(x: dayStartX + CGFloat(i) * dayWidth, y: headerY, width: dayWidth, height: headerHeight)
                cell(rect, fill: weekendDay ? weekend : black, border: black)
                let weekdayLabel = ["日","月","火","水","木","金","土"][weekday - 1]
                // FIXED464: Center the date/weekday block within the full header.
                let dateFont = UIFont.boldSystemFont(ofSize: isA3 ? 14 : (isPortrait ? 11 : 12))
                let weekdayFont = UIFont.boldSystemFont(ofSize: isA3 ? 11 : (isPortrait ? 8 : 9))
                let dateHeight = ceil(dateFont.lineHeight)
                let weekdayHeight = ceil(weekdayFont.lineHeight)
                let lineGap: CGFloat = 1
                let blockHeight = dateHeight + lineGap + weekdayHeight
                let blockY = rect.midY - blockHeight / 2
                let headerInk: UIColor = weekendDay ? .black : .white
                draw("\(calendar.component(.day, from: date))",
                     in: CGRect(x: rect.minX, y: blockY, width: rect.width, height: dateHeight),
                     font: dateFont, color: headerInk, align: .center, verticallyCentered: true)
                draw(weekdayLabel,
                     in: CGRect(x: rect.minX, y: blockY + dateHeight + lineGap,
                                width: rect.width, height: weekdayHeight),
                     font: weekdayFont, color: headerInk, align: .center, verticallyCentered: true)
            }
            headerCell("計", x: dayStartX + CGFloat(tableDays.count) * dayWidth, width: totalWidth)
            var rowY = headerY + headerHeight
            var currentDepartment: String?
            for (index, person) in roster.enumerated() {
                if currentDepartment != person.department {
                    currentDepartment = person.department
                    let rect = CGRect(x: left, y: rowY, width: tableWidth, height: departmentHeight)
                    // FIXED468: Department labels sit directly on the unpainted page.
                    draw("\(person.department)", in: rect.insetBy(dx: 4, dy: 0),
                         font: UIFont.boldSystemFont(ofSize: splitMode ? 8 : 10),
                         align: .left, verticallyCentered: true)
                    rowY += departmentHeight
                }
                let numberRect = CGRect(x: left, y: rowY, width: numberWidth, height: rowHeight)
                let nameRect = CGRect(x: left + numberWidth, y: rowY, width: nameWidth, height: rowHeight)
                cell(numberRect, fill: .white, border: borderColor)
                cell(nameRect, fill: .white, border: borderColor)
                draw("\(index + 1)", in: numberRect.insetBy(dx: 1, dy: 1),
                     font: UIFont.boldSystemFont(ofSize: isA3 ? 13 : 11),
                     align: .center, verticallyCentered: true)
                let name = showStaffName ? person.name + (showWage ? "\n¥\(person.hourlyWage)" : "") : String(format: "%02d", index + 1)
                drawStaffName(name, in: nameRect.insetBy(dx: 2, dy: 1))
                if showWorkTime {
                    let rect = CGRect(x: left + numberWidth + nameWidth, y: rowY, width: inOutWidth, height: rowHeight)
                    cell(rect, fill: UIColor(white: 0.94, alpha: 1), border: borderColor)
                    let half = rect.height / 2
                    let inset = min(1, half * 0.1)
                    draw("入", in: CGRect(x: rect.minX, y: rect.minY + inset, width: rect.width, height: half - inset * 2),
                         font: UIFont.boldSystemFont(ofSize: isA3 ? 10 : 9),
                         align: .center, verticallyCentered: true)
                    draw("出", in: CGRect(x: rect.minX, y: rect.minY + half + inset, width: rect.width, height: half - inset * 2),
                         font: UIFont.boldSystemFont(ofSize: isA3 ? 10 : 9),
                         align: .center, verticallyCentered: true)
                }
                var totalMinutes = 0
                for (i, date) in tableDays.enumerated() {
                    let weekday = calendar.component(.weekday, from: date)
                    let weekendDay = weekday == 1 || weekday == 7
                    let rect = CGRect(x: dayStartX + CGFloat(i) * dayWidth, y: rowY, width: dayWidth, height: rowHeight)
                    cell(rect, fill: weekendDay ? lightWeekend : .white, border: borderColor)
                    guard let assignment = pdfAssignments[PDFShiftKey(staffID: person.id, dateKey: dateKeys[date] ?? date.shiftDateKey)] else { continue }
                    if [ShiftType.off, .paidLeave, .afterNight].contains(assignment.type) {
                        let label = assignment.type == .off ? "-" : assignment.type.rawValue
                        draw(label, in: rect.insetBy(dx: 1, dy: 1),
                             font: UIFont.systemFont(ofSize: assignment.type == .off ? 10 : 6),
                             align: .center, verticallyCentered: true)
                        continue
                    }
                    // FIXED460: Use the same time and break conventions as ShiftLaborEstimate.
                    let defaultRange: (Int, Int)
                    switch assignment.type {
                    case .early: defaultRange = (360, 900)
                    case .day: defaultRange = (540, 1080)
                    case .late: defaultRange = (780, 1320)
                    case .night: defaultRange = (1260, 1980)
                    default: continue
                    }
                    let startMinutes = assignment.customStartMinutes ?? defaultRange.0
                    let endMinutes = assignment.customEndMinutes ?? defaultRange.1
                    let duration = max(0, endMinutes - startMinutes)
                    let rest = min(duration, max(0, assignment.customBreakMinutes ??
                        (duration > 480 ? 60 : (duration > 360 ? 45 : 0))))
                    totalMinutes += max(0, duration - rest)
                    func clock(_ minutes: Int) -> String {
                        String(format: "%d:%02d", (minutes / 60) % 24, minutes % 60)
                    }
                    if showWorkTime {
                        // Render each line separately: the previous literal "\\n" printed
                        // as text and compressed both times into a single tiny line.
                        let lineHeight = rect.height / 2
                        let inset = min(2, lineHeight * 0.1)
                        let baseTimeFont = compactPortrait
                            ? UIFont.systemFont(ofSize: 7, weight: .semibold, width: .condensed)
                            : UIFont.boldSystemFont(ofSize: min(isA3 ? 10 : 9, max(6, dayWidth * 0.40)))
                        let widestTime = max(
                            (clock(startMinutes) as NSString).size(withAttributes: [.font: baseTimeFont]).width,
                            (clock(endMinutes) as NSString).size(withAttributes: [.font: baseTimeFont]).width)
                        let scale = min(1, max(0.5, rect.width - 3.5) / max(1, widestTime))
                        let timeFont = baseTimeFont.withSize(baseTimeFont.pointSize * scale * 0.92)
                        draw(clock(startMinutes), in: CGRect(x: rect.minX + 1.5, y: rect.minY + inset,
                             width: rect.width - 3, height: lineHeight - inset * 2), font: timeFont,
                             align: .center, verticallyCentered: true)
                        draw(clock(endMinutes), in: CGRect(x: rect.minX + 1.5, y: rect.minY + lineHeight + inset,
                             width: rect.width - 3, height: lineHeight - inset * 2), font: timeFont,
                             align: .center, verticallyCentered: true)
                    } else {
                        draw(assignment.type.rawValue, in: rect.insetBy(dx: 0.5, dy: 1),
                             font: UIFont.systemFont(ofSize: 6))
                    }
                }
                let totalRect = CGRect(x: dayStartX + CGFloat(tableDays.count) * dayWidth, y: rowY,
                                       width: totalWidth, height: rowHeight)
                cell(totalRect, fill: UIColor(white: 0.93, alpha: 1), border: borderColor)
                let hours = Double(totalMinutes) / 60
                draw(String(format: "%.1fh", hours), in: totalRect.insetBy(dx: 1, dy: 1),
                     font: UIFont.boldSystemFont(ofSize: splitMode ? 7 : 9),
                     align: .center, verticallyCentered: true)
                rowY += rowHeight
            }
        }
        let pdf = renderer.pdfData { context in
            if splitMode {
                let gap: CGFloat = 8
                let halfHeight = (page.height - top - 28 - gap) / 2
                // FIXED452: Print all selected staff on a single physical sheet.
                // Row height automatically scales to the available space.
                let staffPages: [[StaffMember]] = [staff]
                for pageIndex in staffPages.indices {
                    context.beginPage()
                    UIGraphicsPushContext(context.cgContext)
                    let pageStaff = staffPages[pageIndex]
                    drawTable(firstHalf, title: "前半（1〜15日）", y: top, height: halfHeight, context: context, tableStaff: pageStaff)
                    let separatorY = top + halfHeight + gap / 2
                    UIColor.darkGray.setStroke()
                    let separator = UIBezierPath()
                    separator.move(to: CGPoint(x: left, y: separatorY))
                    separator.addLine(to: CGPoint(x: page.width - left, y: separatorY))
                    separator.lineWidth = 1
                    separator.stroke()
                    drawTable(secondHalf, title: "後半（16日〜月末）", y: top + halfHeight + gap, height: halfHeight, context: context, tableStaff: pageStaff)
                    draw("出力日：\(Date().formatted(date: .numeric, time: .omitted))　\(showBreakTime ? "休憩時間：各勤務設定に準ずる　" : "")", in: CGRect(x: left, y: page.height - 15, width: page.width - left * 2, height: 10), font: smallFont, color: .darkGray, align: .left)
                    UIGraphicsPopContext()
                }
            } else {
                // FIXED194: The normal monthly / half-month modes must paginate
                // staff as well. Previously a large roster compressed every row
                // into a few points and could make the PDF unreadable.
                let tableHeight = page.height - top - 36
                let minimumReadableRowHeight: CGFloat = 24
                // FIXED461: Account for department dividers in pagination.
                let bodyHeight = tableHeight - tableTitleHeight - tableHeaderHeight - 5
                var staffPages: [[StaffMember]] = []
                var currentPage: [StaffMember] = []
                var usedHeight: CGFloat = 0
                var lastDepartment: String?
                for person in staff {
                    let dividerHeight: CGFloat = lastDepartment == person.department ? 0 : 16
                    if !currentPage.isEmpty && usedHeight + dividerHeight + minimumReadableRowHeight > bodyHeight {
                        staffPages.append(currentPage)
                        currentPage = []
                        usedHeight = 0
                        lastDepartment = nil
                    }
                    usedHeight += (lastDepartment == person.department ? 0 : 16) + minimumReadableRowHeight
                    currentPage.append(person)
                    lastDepartment = person.department
                }
                if !currentPage.isEmpty || staffPages.isEmpty { staffPages.append(currentPage) }
                for pageIndex in staffPages.indices {
                    context.beginPage()
                    UIGraphicsPushContext(context.cgContext)
                    let continuation = staffPages.count > 1 ? "（スタッフ続き \(pageIndex + 1)/\(staffPages.count)）" : ""
                    draw(continuation, in: CGRect(x: page.width - left - (page.width - left * 2) * 0.25,
                                                  y: top + 18, width: (page.width - left * 2) * 0.25, height: 14),
                         font: UIFont.systemFont(ofSize: 8), color: ink, align: .right)
                    drawTable(days, title: periodMode == "前半" ? "前半（1〜15日）" : (periodMode == "後半" ? "後半（16日〜月末）" : "月間シフト"), y: top, height: tableHeight, context: context, tableStaff: staffPages[pageIndex])
                    draw("出力日：\(Date().formatted(date: .numeric, time: .omitted))　\(showBreakTime ? "休憩時間：各勤務設定に準ずる　" : "")※勤務区分の略称はアプリのシフト表に準じます", in: CGRect(x: left, y: page.height - 24, width: page.width - left * 2, height: 12), font: smallFont, color: .darkGray, align: .left)
                    UIGraphicsPopContext()
                }
            }
        }
        guard (try? pdf.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    private func staffName(for id: UUID) -> String { data.staff.first(where: { $0.id == id })?.name ?? "" }
    nonisolated private static func csvEscape(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    func addStaff(name: String, department: String, employment: String, wage: Int) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !department.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (0...1_000_000).contains(wage),
              data.locations.contains(where: { $0.id == selectedLocationID }) else { return }
        data.staff.append(StaffMember(name: name.trimmingCharacters(in: .whitespacesAndNewlines), department: department.trimmingCharacters(in: .whitespacesAndNewlines), employment: employment, hourlyWage: wage, locationID: selectedLocationID))
    }

    // FIXED222: Never apply a stale staff editor to another hotel or a deleted record.
    @discardableResult
    func updateStaff(id: UUID, expectedLocationID: UUID?, name: String, department: String,
                     employment: String, wage: Int, photoData: Data?) -> Bool {
        guard expectedLocationID == selectedLocationID,
              let index = data.staff.firstIndex(where: { $0.id == id && $0.locationID == selectedLocationID }),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !department.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              wage >= 0 && wage <= 1_000_000 else { return false }
        var next = data
        next.staff[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.staff[index].department = department.trimmingCharacters(in: .whitespacesAndNewlines)
        next.staff[index].employment = employment
        // Freeze existing assignments at the previous rate before changing staff pay.
        // Older JSON records have no snapshot; preserve their last known rate.
        let previousWage = next.staff[index].hourlyWage
        if previousWage != wage {
            for shiftIndex in next.assignments.indices where next.assignments[shiftIndex].staffID == id && next.assignments[shiftIndex].hourlyWageSnapshot == nil {
                next.assignments[shiftIndex].hourlyWageSnapshot = previousWage
            }
        }
        if previousWage != wage, let locationID = next.staff[index].locationID {
            var changes = next.wageChanges ?? []
            changes.append(StaffWageChange(staffID: id, locationID: locationID,
                                           changedAt: Date(), previousHourlyWage: previousWage,
                                           newHourlyWage: wage))
            next.wageChanges = changes
        }
        next.staff[index].hourlyWage = wage
        next.staff[index].photoData = photoData
        publishValueEdit(next)
        return true
    }

    // FIXED484: Profile edits preserve the existing wage-history implementation.
    func saveStaffProfile(expected: StaffMember, name: String, department: String,
                          employment: String, wage: Int, photoData: Data?) -> Bool {
        guard !storageWriteBlocked, expected.locationID == selectedLocationID,
              data.staff.first(where: { $0.id == expected.id && $0.locationID == selectedLocationID }) == expected else { return false }
        return updateStaff(id: expected.id, expectedLocationID: expected.locationID, name: name,
                           department: department, employment: employment, wage: wage, photoData: photoData)
    }
    func setStaffProfileActive(expected: StaffMember, active: Bool) -> Bool {
        guard !storageWriteBlocked, expected.locationID == selectedLocationID,
              let index = data.staff.firstIndex(where: { $0.id == expected.id && $0.locationID == selectedLocationID }),
              data.staff[index] == expected else { return false }
        data.staff[index].isActive = active
        return true
    }

    // FIXED484: Do not let a stale staff-detail date editor overwrite another update.
    func saveStaffEmploymentDates(expected: StaffMember, join: String?, leave: String?) -> Bool {
        guard !storageWriteBlocked, expected.locationID == selectedLocationID,
              let index = data.staff.firstIndex(where: { $0.id == expected.id && $0.locationID == selectedLocationID }),
              data.staff[index] == expected,
              StaffProfileValidation.validDates(join: join, leave: leave) else { return false }
        var updated = expected
        updated.joinDate = StaffProfileValidation.normalized(join)
        updated.leaveDate = StaffProfileValidation.normalized(leave)
        data.staff[index] = updated
        return true
    }

    // FIXED484: Apply a personal time template only after confirming the exact cell/staff/template.
    func applyStaffPersonalTime(_ item: PersonalWorkTime, date: Date, expectedStaff: StaffMember,
                                expectedAssignment: ShiftAssignment?, allowLeave: Bool = false) throws {
        guard !storageWriteBlocked else { throw DayShiftEditError.storage }
        guard expectedStaff.locationID == selectedLocationID, item.locationID == selectedLocationID,
              item.staffID == expectedStaff.id else { throw DayShiftEditError.changed }
        guard let person = data.staff.first(where: { $0.id == expectedStaff.id && $0.locationID == selectedLocationID }),
              person == expectedStaff, person.isActive else { throw DayShiftEditError.unavailable }
        guard selectedPersonalWorkTimes.first(where: { $0.id == item.id }) == item else { throw DayShiftEditError.changed }
        guard (0...1439).contains(item.startMinutes), item.endMinutes >= item.startMinutes + 15,
              item.endMinutes <= 2879, item.breakMinutes >= 0,
              item.breakMinutes <= item.endMinutes - item.startMinutes else { throw DayShiftEditError.invalid }
        let key = date.shiftDateKey
        let matches = data.assignments.indices.filter { data.assignments[$0].staffID == person.id && data.assignments[$0].locationID == selectedLocationID && data.assignments[$0].dateKey == key }
        let current = matches.first.map { data.assignments[$0] }
        guard matches.count <= 1, current == expectedAssignment else { throw DayShiftEditError.changed }
        if !allowLeave && selectedRequestsUnsorted.contains(where: { $0.staffID == person.id && $0.dateKey == key && $0.status == .approved }) { throw DayShiftEditError.leave }
        var next = current ?? ShiftAssignment(staffID: person.id, dateKey: key, type: .day, locationID: selectedLocationID, hourlyWageSnapshot: person.hourlyWage)
        if DayTimelineMath.span(next) == nil { next.type = .day }
        next.customStartMinutes = item.startMinutes; next.customEndMinutes = item.endMinutes
        next.customBreakMinutes = item.breakMinutes; next.customBreakStartMinutes = nil
        next.patternNameSnapshot = item.name
        if next.hourlyWageSnapshot == nil { next.hourlyWageSnapshot = person.hourlyWage }
        var updated = data.assignments
        if let index = matches.first { updated[index] = next } else { updated.append(next) }
        data.assignments = updated
    }

    func wageHistory(for staffID: UUID) -> [StaffWageChange] {
        (data.wageChanges ?? []).filter { $0.staffID == staffID && $0.locationID == selectedLocationID }
            .sorted { $0.changedAt > $1.changedAt }
    }

    // FIXED223: Read-only impact summary; counts match the records removed by deleteStaff.
    struct StaffDeletionImpact {
        let assignments: Int
        let requests: Int
        let patterns: Int
        let personalWorkTimes: Int
    }

    func staffDeletionImpact(_ staff: StaffMember) -> StaffDeletionImpact? {
        guard staff.locationID == selectedLocationID,
              data.staff.contains(where: { $0.id == staff.id && $0.locationID == selectedLocationID }) else { return nil }
        return StaffDeletionImpact(
            assignments: data.assignments.filter { $0.staffID == staff.id && $0.locationID == selectedLocationID }.count,
            requests: (data.requests ?? []).filter { $0.staffID == staff.id && $0.locationID == selectedLocationID }.count,
            patterns: (data.patterns ?? []).filter { $0.staffID == staff.id && $0.locationID == selectedLocationID }.count,
            personalWorkTimes: (data.personalWorkTimes ?? []).filter { $0.staffID == staff.id && $0.locationID == selectedLocationID }.count
        )
    }

    // FIXED224: Pause/reactivate without deleting historical shifts or staff-linked records.
    @discardableResult
    func setStaffActive(id: UUID, expectedLocationID: UUID?, active: Bool) -> Bool {
        guard expectedLocationID == selectedLocationID,
              let index = data.staff.firstIndex(where: { $0.id == id && $0.locationID == selectedLocationID }) else { return false }
        data.staff[index].isActive = active
        return true
    }

    func deleteStaff(_ staff: StaffMember) {
        // FIXED184: Reject a stale confirmation from another selected hotel.
        guard staff.locationID == selectedLocationID,
              data.staff.contains(where: { $0.id == staff.id && $0.locationID == selectedLocationID }) else { return }
        // Historical data must not be silently cascaded away. Pause the staff instead.
        guard let impact = staffDeletionImpact(staff),
              impact.assignments == 0, impact.requests == 0,
              impact.patterns == 0, impact.personalWorkTimes == 0 else { return }
        var next = data
        next.wageChanges = (next.wageChanges ?? []).filter { $0.staffID != staff.id || $0.locationID != selectedLocationID }
        next.staff.removeAll { $0.id == staff.id && $0.locationID == selectedLocationID }
        next.assignments.removeAll { $0.staffID == staff.id && $0.locationID == selectedLocationID }
        next.requests = (next.requests ?? []).filter { $0.staffID != staff.id || $0.locationID != selectedLocationID }
        next.patterns = (next.patterns ?? []).filter { !($0.locationID == selectedLocationID && $0.staffID == staff.id) }
        next.personalWorkTimes = (next.personalWorkTimes ?? []).filter { !($0.locationID == selectedLocationID && $0.staffID == staff.id) }
        data = next
    }

    func addLocation(name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let location = HotelLocation(name: name)
        data.locations.append(location)
        selectedLocationID = location.id
    }

    func renameLocation(id: UUID, name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let index = data.locations.firstIndex(where: { $0.id == id }) else { return }
        data.locations[index].name = cleaned
    }

    func updateLocationProfile(id: UUID, name: String, address: String, phone: String, roomCount: Int?, floorCount: Int?) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let index = data.locations.firstIndex(where: { $0.id == id }) else { return }
        var next = data
        next.locations[index].name = cleaned
        next.locations[index].address = address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : address.trimmingCharacters(in: .whitespacesAndNewlines)
        next.locations[index].phone = phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : phone.trimmingCharacters(in: .whitespacesAndNewlines)
        next.locations[index].roomCount = roomCount
        next.locations[index].floorCount = floorCount
        publishValueEdit(next)
    }

    func updateLocationPhoto(id: UUID, photoData: Data?) {
        guard let index = data.locations.firstIndex(where: { $0.id == id }) else { return }
        data.locations[index].photoData = photoData
    }

    func deleteLocation(id: UUID) {
        guard data.locations.count > 1, data.locations.contains(where: { $0.id == id }) else { return }
        var next = data
        next.locations.removeAll { $0.id == id }
        next.assignments.removeAll { $0.locationID == id }
        next.wageChanges = (next.wageChanges ?? []).filter { $0.locationID != id }
        next.staff.removeAll { $0.locationID == id }
        next.requests = (next.requests ?? []).filter { $0.locationID != id }
        next.patterns = (next.patterns ?? []).filter { $0.locationID != id }
        next.personalWorkTimes = (next.personalWorkTimes ?? []).filter { $0.locationID != id }
        data = next
        if selectedLocationID == id, let first = data.locations.first {
            selectedLocationID = first.id
        }
    }

    func exportRequestTransfer() -> URL? {
        guard !storageWriteBlocked else { return nil }
        let staffByID = Dictionary(uniqueKeysWithValues: data.staff.map { ($0.id, $0.name) })
        let items = selectedRequests.map { request in
            RequestTransferItem(id: request.id, staffID: request.staffID, staffName: staffByID[request.staffID] ?? "不明なスタッフ", dateKey: request.dateKey, reason: request.reason, status: request.status, createdAt: request.createdAt, updatedAt: request.updatedAt)
        }
        let packet = RequestTransferPacket(facilityName: selectedLocation?.name ?? "施設", requests: items)
        let safeName = ExportFilename.component(selectedLocation?.name ?? "施設")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName)_希望休申請_\(Date().shiftDateKey)_\(UUID().uuidString).json")
        guard let encoded = try? JSONEncoder().encode(packet), (try? encoded.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    @discardableResult
    func importRequestTransfer(from url: URL) -> (imported: Int, skipped: Int)? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let bytes = try? Data(contentsOf: url),
              let packet = try? JSONDecoder().decode(RequestTransferPacket.self, from: bytes),
              packet.formatVersion == 1 else { return nil }
        var requests = data.requests ?? []
        // Index only the selected facility. Keep the first matching record, as the
        // previous firstIndex search did, even when an old file has duplicates.
        let facilityID = selectedLocationID
        let staff = selectedStaff
        var staffByID: [UUID: StaffMember] = [:]
        var staffByName: [String: StaffMember] = [:]
        for member in staff {
            if staffByID[member.id] == nil { staffByID[member.id] = member }
            if staffByName[member.name] == nil { staffByName[member.name] = member }
        }
        struct RequestKey: Hashable {
            let staffID: UUID
            let dateKey: String
            let reason: String
        }
        var indexByID: [UUID: Int] = [:]
        var indexByKey: [RequestKey: Int] = [:]
        for (index, request) in requests.enumerated() where request.locationID == facilityID {
            if indexByID[request.id] == nil { indexByID[request.id] = index }
            let key = RequestKey(staffID: request.staffID, dateKey: request.dateKey, reason: request.reason)
            if indexByKey[key] == nil { indexByKey[key] = index }
        }
        var imported = 0
        var skipped = 0
        for item in packet.requests {
            guard let member = staffByID[item.staffID] ?? staffByName[item.staffName] else {
                skipped += 1
                continue
            }
            let key = RequestKey(staffID: member.id, dateKey: item.dateKey, reason: item.reason)
            // The earlier implementation searched for either match in array order.
            let byID = indexByID[item.id]
            let byKey = indexByKey[key]
            let existingIndex = [byID, byKey].compactMap { $0 }.min()
            if let existingIndex {
                let incomingRevision = item.updatedAt ?? item.createdAt
                let existingRevision = requests[existingIndex].updatedAt ?? requests[existingIndex].createdAt
                if incomingRevision > existingRevision && requests[existingIndex].status != item.status {
                    requests[existingIndex].status = item.status
                    requests[existingIndex].updatedAt = item.updatedAt ?? item.createdAt
                    imported += 1
                } else {
                    skipped += 1
                }
                continue
            }
            let newIndex = requests.count
            requests.append(ShiftRequest(id: item.id, staffID: member.id, dateKey: item.dateKey, reason: item.reason, status: item.status, createdAt: item.createdAt, updatedAt: item.updatedAt, locationID: facilityID))
            if indexByID[item.id] == nil { indexByID[item.id] = newIndex }
            if indexByKey[key] == nil { indexByKey[key] = newIndex }
            imported += 1
        }
        // No mutation means no unnecessary JSON rewrite.
        if imported > 0 { data.requests = requests }
        return (imported, skipped)
    }

    // Reject inconsistent backup files before replacing current data.
    nonisolated private static func isValidBackup(_ backup: ShiftData) -> Bool {
        guard !backup.locations.isEmpty else { return false }
        let locations = backup.locations.map(\.id)
        let staffIDs = backup.staff.map(\.id)
        let wageChangeIDs = (backup.wageChanges ?? []).map(\.id)
        let assignments = backup.assignments.map(\.id)
        let requests = (backup.requests ?? []).map(\.id)
        let patterns = (backup.patterns ?? []).map(\.id)
        let personalWorkTimeIDs = (backup.personalWorkTimes ?? []).map(\.id)
        guard Set(personalWorkTimeIDs).count == personalWorkTimeIDs.count,
              Set(wageChangeIDs).count == wageChangeIDs.count,
              Set(locations).count == locations.count,
              Set(staffIDs).count == staffIDs.count,
              Set(assignments).count == assignments.count,
              Set(requests).count == requests.count,
              Set(patterns).count == patterns.count else { return false }
        // Validate each distinct date once, rather than parsing every historical row.
        let dateKeys = Set(backup.assignments.lazy.map(\.dateKey))
            .union((backup.requests ?? []).lazy.map(\.dateKey))
        guard dateKeys.allSatisfy({ key in
            key.count == 10 && Date.keyFormatter.date(from: key)?.shiftDateKey == key
        }) else { return false }
        let locationSet = Set(locations)
        // Legacy backups may omit facility IDs on staff and shifts. They are
        // migrated to the first facility after validation. Explicit facility
        // IDs, however, must agree with the staff member's facility; otherwise
        // a restored shift/request could appear under the wrong hotel.
        let fallbackID = backup.locations[0].id
        let staffLocationByID = Dictionary(uniqueKeysWithValues: backup.staff.map {
            ($0.id, $0.locationID ?? fallbackID)
        })
        guard (backup.wageChanges ?? []).allSatisfy({ change in
            staffLocationByID[change.staffID] == change.locationID &&
            (0...1_000_000).contains(change.previousHourlyWage) &&
            (0...1_000_000).contains(change.newHourlyWage) &&
            change.previousHourlyWage != change.newHourlyWage
        }) else { return false }
        return backup.staff.allSatisfy { staff in
                (staff.locationID.map { locationSet.contains($0) } ?? true) &&
                (0...1_000_000).contains(staff.hourlyWage) &&
                StaffProfileValidation.validDates(join: staff.joinDate, leave: staff.leaveDate)
            }
            && backup.assignments.allSatisfy { assignment in
                guard let staffLocation = staffLocationByID[assignment.staffID],
                      ShiftMinuteValidation.valid(assignment),
                      assignment.hourlyWageSnapshot.map({ $0 >= 0 && $0 <= 1_000_000 }) ?? true else { return false }
                return (assignment.locationID ?? staffLocation) == staffLocation
            }
            && (backup.requests ?? []).allSatisfy { request in
                staffLocationByID[request.staffID] == request.locationID
            }
            && (backup.personalWorkTimes ?? []).allSatisfy { item in
                guard staffLocationByID[item.staffID] == item.locationID,
                      !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      (0...1439).contains(item.startMinutes),
                      (1...2879).contains(item.endMinutes),
                      item.endMinutes > item.startMinutes,
                      (0...180).contains(item.breakMinutes),
                      item.breakMinutes <= item.endMinutes - item.startMinutes else { return false }
                return true
            }
            && (backup.patterns ?? []).allSatisfy { pattern in
                guard locationSet.contains(pattern.locationID), pattern.weekdays.count == 7,
                      !pattern.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      ShiftMinuteValidation.valid(start: pattern.customStartMinutes, end: pattern.customEndMinutes,
                          rest: pattern.customBreakMinutes, restStart: pattern.customBreakStartMinutes) else { return false }
                if pattern.customStartMinutes != nil && (pattern.customEndMinutes == nil || pattern.customBreakMinutes == nil) { return false }
                if let from = pattern.validFrom, let until = pattern.validUntil,
                   Calendar.current.startOfDay(for: from) > Calendar.current.startOfDay(for: until) { return false }
                if pattern.scope == .seasonal && (pattern.validFrom == nil || pattern.validUntil == nil) { return false }
                if let type = pattern.basicShiftType {
                    guard [.early, .day, .late, .night].contains(type), pattern.scope == .everyone,
                          pattern.staffID == nil, pattern.weekdays == Array(repeating: type, count: 7),
                          pattern.customStartMinutes != nil else { return false }
                }
                if pattern.scope == .everyone { return true }
                guard let staffID = pattern.staffID else { return false }
                return staffLocationByID[staffID] == pattern.locationID
            }
    }

    func exportBackup() async -> URL? {
        guard !storageWriteBlocked, let bytes = await cloudSnapshot() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HOTEL_SHIFT_backup_\(Date().shiftDateKey)_\(UUID().uuidString).json")
        do {
            try await Task.detached(priority: .utility) { try bytes.write(to: url, options: .atomic) }.value
            return url
        } catch { return nil }
    }
    func importBackup(from url: URL) async -> Bool {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let revision = pdfRevision
        let bytes = try? await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value
        guard let bytes, revision == pdfRevision else { return false }
        if !storageWriteBlocked, needsSave {
            guard await persistSnapshot(notifyCloud: false) != nil else { return false }
        }
        let restored = await installSnapshot(bytes, allowRecovery: true)
        if restored { cloudSync.localSaved() }
        return restored
    }

    var hasSampleLocations: Bool { data.locations.contains { SampleShiftData.locationIDs.contains($0.id) } }
    @discardableResult
    func addSampleData(anchor: Date = Date()) -> Bool {
        guard !storageWriteBlocked, !hasSampleLocations else { return false }
        let sample = SampleShiftData.make(anchor: anchor)
        var next = data
        next.locations.append(contentsOf: sample.locations)
        next.staff.append(contentsOf: sample.staff)
        next.assignments.append(contentsOf: sample.assignments)
        next.requests = (next.requests ?? []) + (sample.requests ?? [])
        next.patterns = (next.patterns ?? []) + (sample.patterns ?? [])
        next.personalWorkTimes = (next.personalWorkTimes ?? []) + (sample.personalWorkTimes ?? [])
        data = next
        selectedLocationID = sample.locations[0].id
        flushPendingSave()
        return !needsSave
    }

    // Shared snapshots use exactly the validated backup format, with deterministic key order.
    func cloudSnapshot() async -> Data? {
        guard !storageWriteBlocked else { return nil }
        if let cached = serializedSnapshot, cached.revision == pdfRevision, !needsSave { return cached.bytes }
        return await persistSnapshot(notifyCloud: false)
    }
    nonisolated static func validCloudSnapshot(_ bytes: Data) -> Bool {
        guard let decoded = Self.decodeCompatibleData(bytes) else { return false }
        return Self.isValidBackup(decoded)
    }
    func archiveCloudSnapshot(_ bytes: Data) async throws {
        let url = fileURL.deletingLastPathComponent().appendingPathComponent("hotel-shift-cloud-safety-\(UUID().uuidString).json")
        try await Task.detached(priority: .utility) { try bytes.write(to: url, options: .atomic) }.value
    }
    func installCloudSnapshot(_ bytes: Data, preservingConflict: Bool = false) async -> Bool {
        await installSnapshot(bytes, allowRecovery: false, preservingConflict: preservingConflict)
    }
    private func installSnapshot(_ bytes: Data, allowRecovery: Bool, preservingConflict: Bool = false) async -> Bool {
        guard allowRecovery || !storageWriteBlocked else { return false }
        let revision = pdfRevision
        let prepared = await Task.detached(priority: .utility) { () -> (ShiftData, Data, ShiftLookupIndex)? in
            guard let decoded = Self.decodeCompatibleData(bytes), Self.isValidBackup(decoded) else { return nil }
            var migrated = decoded
            let fallback = migrated.locations[0].id
            let locations = Dictionary(uniqueKeysWithValues: migrated.staff.map { ($0.id, $0.locationID ?? fallback) })
            for i in migrated.staff.indices where migrated.staff[i].locationID == nil { migrated.staff[i].locationID = fallback }
            for i in migrated.assignments.indices where migrated.assignments[i].locationID == nil { migrated.assignments[i].locationID = locations[migrated.assignments[i].staffID] ?? fallback }
            guard let canonical = try? ShiftPersistenceWriter.encode(migrated) else { return nil }
            return (migrated, canonical, ShiftLookupIndex(migrated))
        }.value
        guard let (replacement, canonical, index) = prepared, revision == pdfRevision else { return false }
        let ticket = persistence.reserve()
        let safetyPrefix = allowRecovery ? "hotel-shift-before-restore-" : (preservingConflict ? "hotel-shift-cloud-safety-" : "hotel-shift-before-cloud-sync-")
        let safety = fileURL.deletingLastPathComponent().appendingPathComponent(safetyPrefix + UUID().uuidString + ".json")
        do {
            _ = try await persistence.install(canonical, to: fileURL, ticket: ticket, preservingTo: safety)
            guard revision == pdfRevision else {
                // A local edit during the disk operation wins; repair durable local state.
                flushPendingSave()
                return false
            }
            cloudImportInProgress = true
            storageWriteBlocked = false
            if storageWarning != nil { storageWarning = nil }
            replacementLookup = index
            data = replacement
            replacementLookup = nil
            pendingSave?.cancel(); pendingSave = nil
            needsSave = false; serializedSnapshot = (pdfRevision, canonical)
            if !replacement.locations.contains(where: { $0.id == selectedLocationID }) { selectedLocationID = replacement.locations[0].id }
            cloudImportInProgress = false
            if !allowRecovery && !preservingConflict { await persistence.pruneAutomaticCloudCopies(in: fileURL.deletingLastPathComponent()) }
            return true
        } catch { return false }
    }

    // Batch rapid edits into a single atomic write.
    private func scheduleSave() {
        guard !storageWriteBlocked else { return }
        needsSave = true
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            _ = await self?.persistSnapshot()
        }
    }

    // Automatic saves serialize a value snapshot away from the UI actor.
    private func persistSnapshot(notifyCloud: Bool = true) async -> Data? {
        guard !storageWriteBlocked else { return nil }
        if let cached = serializedSnapshot, cached.revision == pdfRevision, !needsSave { return cached.bytes }
        let revision = pdfRevision
        let job: (revision: UInt64, ticket: UInt64, task: Task<Data, Error>)
        if let activePersistence, activePersistence.revision == revision { job = activePersistence }
        else {
            let ticket = persistence.reserve(), snapshot = data, url = fileURL, writer = persistence
            let task = Task.detached(priority: .utility) { try await writer.write(snapshot, to: url, ticket: ticket) }
            job = (revision, ticket, task); activePersistence = job
        }
        defer { if activePersistence?.ticket == job.ticket { activePersistence = nil } }
        do {
            let bytes = try await job.task.value
            guard revision == pdfRevision else { return nil }
            finishSave(bytes, revision: revision, notifyCloud: notifyCloud)
            return bytes
        } catch ShiftPersistenceError.superseded {
            return serializedSnapshot?.revision == pdfRevision ? serializedSnapshot?.bytes : nil
        } catch {
            if revision == pdfRevision { storageWarning = "変更内容を保存できませんでした。空き容量を確認してください。" }
            return nil
        }
    }
    private func finishSave(_ bytes: Data, revision: UInt64, notifyCloud: Bool = true) {
        if let cached = serializedSnapshot, cached.revision == revision, !needsSave { return }
        needsSave = false
        serializedSnapshot = (revision, bytes)
        if storageWarning != nil { storageWarning = nil }
        if notifyCloud && !cloudImportInProgress { cloudSync.localSaved() }
    }
    func flushPendingSave() {
        pendingSave?.cancel(); pendingSave = nil
        guard !storageWriteBlocked, needsSave else { return }
        do {
            let bytes = try persistence.writeSynchronously(data, to: fileURL)
            finishSave(bytes, revision: pdfRevision)
        } catch {
            storageWarning = "変更内容を端末に保存できませんでした。空き容量を確認し、アプリを終了せずに再度保存をお試しください。"
        }
    }
}
