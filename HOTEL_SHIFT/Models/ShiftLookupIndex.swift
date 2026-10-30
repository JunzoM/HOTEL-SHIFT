import Foundation

// Indices refer to positions, so photographs and historical rows are not duplicated.
struct ShiftLookupIndex {
    struct Period: Hashable { let location: UUID; let value: String }
    struct Cell: Hashable { let location: UUID; let staff: UUID; let day: String }
    var staffByID: [UUID: Int] = [:]
    var staffByLocation: [UUID: [Int]] = [:]
    var assignmentsByLocation: [UUID: [Int]] = [:]
    var assignmentsByMonth: [Period: [Int]] = [:]
    var assignmentsByDay: [Period: [Int]] = [:]
    var assignmentByCell: [Cell: Int] = [:]
    var requestsByLocation: [UUID: [Int]] = [:]
    var requestsByCell: [Cell: [Int]] = [:]
    var patternsByLocation: [UUID: [Int]] = [:]
    var personalByLocation: [UUID: [Int]] = [:]
    init(_ data: ShiftData) {
        for (i, person) in data.staff.enumerated() {
            if staffByID[person.id] == nil { staffByID[person.id] = i }
            if let location = person.locationID { staffByLocation[location, default: []].append(i) }
        }
        for (i, shift) in data.assignments.enumerated() {
            guard let location = shift.locationID else { continue }
            assignmentsByLocation[location, default: []].append(i)
            assignmentsByMonth[Period(location: location, value: String(shift.dateKey.prefix(7))), default: []].append(i)
            assignmentsByDay[Period(location: location, value: shift.dateKey), default: []].append(i)
            let cell = Cell(location: location, staff: shift.staffID, day: shift.dateKey)
            if assignmentByCell[cell] == nil { assignmentByCell[cell] = i }
        }
        for (i, request) in (data.requests ?? []).enumerated() {
            requestsByLocation[request.locationID, default: []].append(i)
            requestsByCell[Cell(location: request.locationID, staff: request.staffID, day: request.dateKey), default: []].append(i)
        }
        for (i, pattern) in (data.patterns ?? []).enumerated() { patternsByLocation[pattern.locationID, default: []].append(i) }
        for (i, item) in (data.personalWorkTimes ?? []).enumerated() { personalByLocation[item.locationID, default: []].append(i) }
    }
    private static func sharesStorage<T>(_ left: [T], _ right: [T]) -> Bool {
        guard left.count == right.count else { return false }
        return left.withUnsafeBufferPointer { a in right.withUnsafeBufferPointer { b in a.baseAddress == b.baseAddress } }
    }
    mutating func refresh(from old: ShiftData, to data: ShiftData) {
        if !Self.sharesStorage(old.staff, data.staff), old.staff.map(\.id) != data.staff.map(\.id) || old.staff.map(\.locationID) != data.staff.map(\.locationID) {
            staffByID = [:]; staffByLocation = [:]
            for (i, person) in data.staff.enumerated() {
                if staffByID[person.id] == nil { staffByID[person.id] = i }
                if let location = person.locationID { staffByLocation[location, default: []].append(i) }
            }
        }
        if !Self.sharesStorage(old.assignments, data.assignments) {
            let prefixUnchanged = data.assignments.count >= old.assignments.count && zip(old.assignments, data.assignments).allSatisfy {
                $0.staffID == $1.staffID && $0.dateKey == $1.dateKey && $0.locationID == $1.locationID
            }
            if !prefixUnchanged {
                assignmentsByLocation = [:]; assignmentsByMonth = [:]; assignmentsByDay = [:]; assignmentByCell = [:]
            }
            let start = prefixUnchanged ? old.assignments.count : 0
            for i in start..<data.assignments.count {
                let shift = data.assignments[i]
                guard let location = shift.locationID else { continue }
                assignmentsByLocation[location, default: []].append(i)
                assignmentsByMonth[Period(location: location, value: String(shift.dateKey.prefix(7))), default: []].append(i)
                assignmentsByDay[Period(location: location, value: shift.dateKey), default: []].append(i)
                let cell = Cell(location: location, staff: shift.staffID, day: shift.dateKey)
                if assignmentByCell[cell] == nil { assignmentByCell[cell] = i }
            }
        }
        let oldRequests = old.requests ?? [], requests = data.requests ?? []
        if !Self.sharesStorage(oldRequests, requests) {
            requestsByLocation = [:]; requestsByCell = [:]
            for (i, request) in requests.enumerated() {
                requestsByLocation[request.locationID, default: []].append(i)
                requestsByCell[Cell(location: request.locationID, staff: request.staffID, day: request.dateKey), default: []].append(i)
            }
        }
        let oldPatterns = old.patterns ?? [], patterns = data.patterns ?? []
        if !Self.sharesStorage(oldPatterns, patterns) {
            patternsByLocation = [:]
            for (i, pattern) in patterns.enumerated() { patternsByLocation[pattern.locationID, default: []].append(i) }
        }
        let oldItems = old.personalWorkTimes ?? [], items = data.personalWorkTimes ?? []
        if !Self.sharesStorage(oldItems, items) {
            personalByLocation = [:]
            for (i, item) in items.enumerated() { personalByLocation[item.locationID, default: []].append(i) }
        }
    }
    func assignmentPositions(location: UUID, days: Set<String>) -> [Int] {
        // Preserve the original record order, including legacy duplicate cells.
        days.flatMap { assignmentsByDay[Period(location: location, value: $0)] ?? [] }.sorted()
    }
}

// A bounded memo store owned by each screen. Revision is part of every key.
final class ShiftRenderCache {
    private var entries: [AnyHashable: Any] = [:]
    private var order: [AnyHashable] = []
    private var generation: UInt64?
    func value<T>(for key: AnyHashable, make: () -> T) -> T {
        if let revision = (key.base as? ShiftRenderKey)?.revision, generation != revision {
            entries.removeAll(keepingCapacity: true); order.removeAll(keepingCapacity: true)
            generation = revision
        }
        if let cached = entries[key] as? T { return cached }
        let result = make()
        entries[key] = result; order.append(key)
        if order.count > 8 { entries.removeValue(forKey: order.removeFirst()) }
        return result
    }
}

struct ShiftRenderKey: Hashable {
    let revision: UInt64
    let location: UUID
    let scope: AnyHashable
}
