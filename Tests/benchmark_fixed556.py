"""Build a release-mode benchmark from actual old/new methods and production indices."""
from pathlib import Path
import subprocess, tempfile
root=Path(__file__).resolve().parents[1]
store=(root/'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()
views=(root/'HOTEL_SHIFT/Views/StaffAndOtherViews.swift').read_text()
def between(text,start,end):return text[text.index(start):text.index(end,text.index(start))]
old_batch=(root/'Tests/fixtures/fixed555_decideRequestBatch.txt').read_text().replace('decideRequestBatch(', 'decideBaseline(')
new_batch=between(store,'    func decideRequestBatch(','    func deleteRequestSafely(').replace('decideRequestBatch(', 'decideOptimized(')
old_preview=(root/'Tests/fixtures/fixed555_assignmentLookup.txt').read_text().replace('private func assignmentLookup','func previewBaseline').replace('store.','self.')
new_preview=between(views,'    private func assignmentLookup(for dates:', '    var body: some View {').replace('private func assignmentLookup','func previewOptimized').replace('store.','self.')
pdf=between(store,'    private func pdfAssignments(month:', '    func exportShiftPDF(month:').replace('private func','func')
program=r'''
import Foundation
struct ScheduleGridKey: Hashable { let staffID: UUID; let dateKey:String }
@MainActor final class Harness {
    var data: ShiftData { didSet { lookup.refresh(from:oldValue,to:data) } }
    var lookup: ShiftLookupIndex
    var storageWriteBlocked=false
    var selectedLocationID:UUID
    init(_ data:ShiftData,_ index:ShiftLookupIndex) { self.data=data;lookup=index;selectedLocationID=data.locations[0].id }
    var selectedStaff:[StaffMember] { (lookup.staffByLocation[selectedLocationID] ?? []).map{data.staff[$0]} }
    var selectedAssignments:[ShiftAssignment] { (lookup.assignmentsByLocation[selectedLocationID] ?? []).map{data.assignments[$0]} }
    func selectedAssignments(on dates:Set<String>)->[ShiftAssignment] { lookup.assignmentPositions(location:selectedLocationID,days:dates).map{data.assignments[$0]} }
OLDBATCH
NEWBATCH
OLDPREVIEW
NEWPREVIEW
PDF
}
@main struct Runner {
    @MainActor static var sink=0
    @MainActor static func measured(_ count:Int,_ body:()->Void)->Double {
        var samples:[Double]=[]
        for _ in 0..<count { let start=ProcessInfo.processInfo.systemUptime;body();samples.append((ProcessInfo.processInfo.systemUptime-start)*1000) }
        return samples.sorted()[samples.count/2]
    }
    @MainActor static func main() throws {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone = .current
        let start=Date.keyFormatter.date(from:"2024-01-01")!
        let days=(0..<1096).map{calendar.date(byAdding:.day,value:$0,to:start)!}
        let keys=days.map(\.shiftDateKey)
        let locations=(0..<10).map{HotelLocation(name:"Hotel \($0)")}
        var staff:[StaffMember]=[],assignments:[ShiftAssignment]=[]
        assignments.reserveCapacity(548000)
        for location in locations {
            let people=(0..<50).map{StaffMember(name:"Staff \($0)",department:"Front",employment:"Full",hourlyWage:1500,locationID:location.id)}
            staff+=people
            for (d,key) in keys.enumerated() { for person in people {
                assignments.append(ShiftAssignment(staffID:person.id,dateKey:key,type:d%7<5 ? .day:.off,locationID:location.id,hourlyWageSnapshot:1500))
            } }
        }
        let expected=staff.prefix(50).flatMap{person in (1...4).map{day in ShiftRequest(staffID:person.id,dateKey:String(format:"2026-10-%02d",day),reason:"test",locationID:locations[0].id)}}
        let fixture=ShiftData(locations:locations,staff:staff,assignments:assignments,requests:expected)
        let indexStart=ProcessInfo.processInfo.systemUptime
        let index=ShiftLookupIndex(fixture)
        let indexMS=(ProcessInfo.processInfo.systemUptime-indexStart)*1000
        let query=Harness(fixture,index)
        let visible=days.filter{$0.shiftDateKey.hasPrefix("2026-10")}
        let old=query.previewBaseline(for:visible),new=query.previewOptimized(for:visible)
        precondition(old==new)
        let previewOld=measured(7){sink+=query.previewBaseline(for:visible).count}
        let previewNew=measured(7){sink+=query.previewOptimized(for:visible).count}
        let targetMonth=Date.keyFormatter.date(from:"2026-10-01")!
        let subset=query.pdfAssignments(month:targetMonth)
        let expectedRows=fixture.assignments.filter{$0.locationID==locations[0].id && $0.dateKey.hasPrefix("2026-10")}
        precondition(subset==expectedRows && subset.count==1550)
        let roster=query.selectedStaff,history=query.selectedAssignments
        let batchOld=measured(3){
            let h=Harness(fixture,index)
            try! h.decideBaseline(expected:expected,staffSnapshot:roster,assignmentSnapshot:history,locationID:locations[0].id,status:.approved,alsoOff:true)
            sink+=h.data.requests!.filter{$0.status == .approved}.count
        }
        let batchNew=measured(3){
            let h=Harness(fixture,index)
            try! h.decideOptimized(expected:expected,staffSnapshot:roster,assignmentSnapshot:history,locationID:locations[0].id,status:.approved,alsoOff:true)
            sink+=h.data.requests!.filter{$0.status == .approved}.count
        }
        let a=Harness(fixture,index),b=Harness(fixture,index)
        try a.decideBaseline(expected:expected,staffSnapshot:roster,assignmentSnapshot:history,locationID:locations[0].id,status:.approved,alsoOff:true)
        try b.decideOptimized(expected:expected,staffSnapshot:roster,assignmentSnapshot:history,locationID:locations[0].id,status:.approved,alsoOff:true)
        precondition(a.data.assignments==b.data.assignments)
        precondition(a.data.requests!.map(\.status)==b.data.requests!.map(\.status))
        // Sparse/duplicate-cell semantics use a small fixture, separate from timings.
        for duplicate in [false,true] {
            var small=ShiftData(locations:[locations[0]],staff:[staff[0]],assignments:[],requests:[])
            let r1=ShiftRequest(staffID:staff[0].id,dateKey:"2026-10-01",reason:"one",locationID:locations[0].id)
            var r2=r1;r2.id=UUID();r2.reason="two"
            small.requests=[r1,r2]
            if duplicate {
                let row=ShiftAssignment(staffID:staff[0].id,dateKey:r1.dateKey,type:.day,locationID:locations[0].id)
                var other=row;other.id=UUID();small.assignments=[row,other]
            }
            let h=Harness(small,ShiftLookupIndex(small))
            do {
                try h.decideOptimized(expected:[r1,r2],staffSnapshot:h.selectedStaff,assignmentSnapshot:h.selectedAssignments,locationID:locations[0].id,status:.approved,alsoOff:true)
                precondition(!duplicate && h.data.assignments.count==1 && h.data.assignments[0].type == .off)
            } catch { precondition(duplicate && h.data.requests!.allSatisfy{$0.status == .pending}) }
        }
        let report:[String:Any]=[
            "rows":fixture.assignments.count,"locations":10,"staff_per_location":50,"days":1096,
            "index_build_ms":indexMS,"preview_baseline_ms":previewOld,"preview_optimized_ms":previewNew,
            "preview_speedup":previewOld/previewNew,"batch_requests":200,
            "batch_baseline_ms":batchOld,"batch_optimized_ms":batchNew,"batch_speedup":batchOld/batchNew,
            "pdf_snapshot_rows_before":fixture.assignments.count,"pdf_snapshot_rows_after":subset.count,
            "shift_struct_stride_bytes":MemoryLayout<ShiftAssignment>.stride,
            "correctness":"before/after equal; missing/duplicate cells checked",
            "scope":"release-mode query/batch core; excludes PDF drawing, UI, JSON persistence and cloud sync"
        ]
        print(String(data:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
    }
}
'''.replace('OLDBATCH',old_batch).replace('NEWBATCH',new_batch).replace('OLDPREVIEW',old_preview).replace('NEWPREVIEW',new_preview).replace('\nPDF\n','\n'+pdf+'\n').replace('\\.', '\.')
with tempfile.TemporaryDirectory(prefix='fixed556-bench-') as folder:
    folder=Path(folder);(folder/'Runner.swift').write_text(program)
    subprocess.run(['swiftc','-O','-parse-as-library',str(root/'HOTEL_SHIFT/Models/ShiftModels.swift'),str(root/'HOTEL_SHIFT/Models/ShiftLookupIndex.swift'),str(folder/'Runner.swift'),'-o',str(folder/'bench')],check=True)
    result=subprocess.run([str(folder/'bench')],capture_output=True,text=True,check=True,timeout=180)
    print(result.stdout)
    (root/'reports/fixed556_benchmark.json').write_text(result.stdout)
