import Foundation
@main struct IndexRegression504 {
    static func equal(_ a: ShiftLookupIndex, _ b: ShiftLookupIndex) {
        precondition(a.staffByID == b.staffByID)
        precondition(a.staffByLocation == b.staffByLocation)
        precondition(a.assignmentsByLocation == b.assignmentsByLocation)
        precondition(a.assignmentsByMonth == b.assignmentsByMonth)
        precondition(a.assignmentsByDay == b.assignmentsByDay)
        precondition(a.assignmentByCell == b.assignmentByCell)
        precondition(a.requestsByLocation == b.requestsByLocation && a.requestsByCell == b.requestsByCell)
        precondition(a.patternsByLocation == b.patternsByLocation && a.personalByLocation == b.personalByLocation)
    }
    static func main() throws {
        var data = SampleShiftData.make(anchor: Date.keyFormatter.date(from: "2026-10-28")!)
        var index = ShiftLookupIndex(data)
        for step in 0..<180 {
            let old = data
            switch step % 12 {
            case 0: data.assignments[step].note = "edit\(step)"
            case 1: data.assignments[step].type = .paidLeave
            case 2:
                var row = data.assignments[step]; row.id = UUID(); row.dateKey = "2027-01-01"
                data.assignments.append(row)
            case 3: data.assignments.remove(at: step)
            case 4: data.assignments.swapAt(step, step+100)
            case 5: data.staff[step % 100].department = "changed"
            case 6: data.staff[step % 100].locationID = data.locations[step % 4].id
            case 7: data.requests?[step % 200].status = .rejected
            case 8: data.requests?[step % 200].dateKey = "2027-01-02"
            case 9: data.patterns?[step % 20].locationID = data.locations[step % 4].id
            case 10: data.personalWorkTimes?[step % 100].locationID = data.locations[step % 4].id
            default: data.staff.swapAt(step % 100, (step+1) % 100)
            }
            index.refresh(from: old, to: data)
            equal(index, ShiftLookupIndex(data))
        }
        let cache = ShiftRenderCache(); var builds = 0
        for i in 0..<12 { let value: Int = cache.value(for: i) { builds += 1; return i }; precondition(value == i) }
        let _: Int = cache.value(for: 0) { builds += 1; return 0 }; precondition(builds == 13)
        final class Sentinel { }
        let revisionCache = ShiftRenderCache()
        weak var previousGeneration: Sentinel?
        do {
            let retained: Sentinel = revisionCache.value(for: ShiftRenderKey(revision: 1, location: data.locations[0].id, scope: "photos")) { Sentinel() }
            previousGeneration = retained
        }
        precondition(previousGeneration != nil)
        let _: Int = revisionCache.value(for: ShiftRenderKey(revision: 2, location: data.locations[0].id, scope: "photos")) { 1 }
        precondition(previousGeneration == nil)
        // Long history: only display values change, not the membership indices.
        let fixture = SampleShiftData.make(anchor: Date.keyFormatter.date(from: "2026-10-28")!)
        var history = fixture
        for block in 1..<12 {
            let anchor = Calendar.current.date(byAdding: .month, value: 2*block, to: Date.keyFormatter.date(from:"2026-10-28")!)!
            let extra = SampleShiftData.make(anchor: anchor).assignments.map { shift -> ShiftAssignment in var value=shift; value.id=UUID(); return value }
            history.assignments.append(contentsOf: extra)
        }
        var historyIndex = ShiftLookupIndex(history)
        let before = history
        history.assignments[history.assignments.count-1].note = "time or note only"
        let start = ProcessInfo.processInfo.systemUptime
        historyIndex.refresh(from: before, to: history)
        let elapsed = (ProcessInfo.processInfo.systemUptime-start)*1000
        equal(historyIndex, ShiftLookupIndex(history))
        let result:[String:Any] = ["differential_mutations":180,"long_history_assignments":history.assignments.count,"metadata_index_refresh_ms":elapsed,"checks":["append","delete","reorder","note/type edit","staff moves","request edits","pattern/time location edits","bounded cache eviction", "old-generation-photo-references-released"]]
        let url=URL(fileURLWithPath:CommandLine.arguments[1])
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:url)
        print(String(data:try Data(contentsOf:url),encoding:.utf8)!)
    }
}
