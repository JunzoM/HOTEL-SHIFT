"""Actual old/new grid and weekly-summary code on 548,000 shift records."""
from pathlib import Path
import subprocess,tempfile,json,zipfile
r=Path(__file__).resolve().parents[1]
store=(r/'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()
view=(r/'HOTEL_SHIFT/Views/StaffAndOtherViews.swift').read_text()
fixtures=r/'Tests/fixtures';fixtures.mkdir(exist_ok=True)
old_grid=fixtures/'fixed557_applyScheduleGrid.txt';old_weekly=fixtures/'fixed557_weeklyHourAlerts.txt'
def section(s,a,b):return s[s.index(a):s.index(b,s.index(a))]
if not old_grid.exists() or not old_weekly.exists():
    with zipfile.ZipFile(r.parent/'HOTEL_SHIFT_Starter_FIXED557.zip') as z:
        baseline=z.read('HOTEL_SHIFT/HOTEL_SHIFT/Services/ShiftStore.swift').decode()
        old_grid.write_text(section(baseline,'    func applyScheduleGrid(', '    func restoreScheduleGrid('))
        baseline=z.read('HOTEL_SHIFT/HOTEL_SHIFT/Views/StaffAndOtherViews.swift').decode()
        old_weekly.write_text(section(baseline,'    private var weeklyHourAlerts:', '    private var previousMonthEstimate:'))
a=old_grid.read_text().replace('applyScheduleGrid(', 'baselineGrid(')
b=section(store,'    func applyScheduleGrid(', '    func restoreScheduleGrid(').replace('applyScheduleGrid(', 'optimizedGrid(')
c=old_weekly.read_text().replace('private var weeklyHourAlerts:', 'var baselineWeekly:')
d=section(view,'    private var weeklyHourAlerts:', '    private var previousMonthEstimate:').replace('private var weeklyHourAlerts:', 'var optimizedWeekly:')
program=r'''
import Foundation
@MainActor final class Store {
    var data:ShiftData {didSet{pdfRevision+=1;if !valueOnlyEdit{lookup.refresh(from:oldValue,to:data)}}}
    var lookup:ShiftLookupIndex
    var pdfRevision:UInt64=0
    var valueOnlyEdit=false
    var selectedLocationID:UUID
    var storageWriteBlocked=false
    init(_ data:ShiftData,_ index:ShiftLookupIndex){self.data=data;lookup=index;selectedLocationID=data.locations[0].id}
    func publishValueEdit(_ updated:ShiftData){valueOnlyEdit=true;defer{valueOnlyEdit=false};data=updated}
    var selectedStaff:[StaffMember]{(lookup.staffByLocation[selectedLocationID] ?? []).map{data.staff[$0]}}
    var selectedAssignments:[ShiftAssignment]{(lookup.assignmentsByLocation[selectedLocationID] ?? []).map{data.assignments[$0]}}
    var selectedRequestsUnsorted:[ShiftRequest]{data.requests ?? []}
    func hasApprovedLeave(staffID:UUID,dateKey:String)->Bool {
        let requests=data.requests ?? []
        return (lookup.requestsByCell[.init(location:selectedLocationID,staff:staffID,day:dateKey)] ?? []).contains{requests[$0].status == .approved}
    }
    func selectedAssignments(on dates:Set<String>)->[ShiftAssignment]{lookup.assignmentPositions(location:selectedLocationID,days:dates).map{data.assignments[$0]}}
OLDGRID
NEWGRID
}
@MainActor final class Labor {
    let store:Store
    let selectedMonth:Date
    var monthPrefix:String{String(selectedMonth.shiftDateKey.prefix(7))}
    var renderCache=ShiftRenderCache()
    init(_ store:Store,_ month:Date){self.store=store;selectedMonth=month}
OLDWEEKLY
NEWWEEKLY
}
@main struct Runner {
    @MainActor static var sink=0
    @MainActor static func measured(_ count:Int,_ work:()->Void)->Double {
        var samples:[Double]=[]
        for _ in 0..<count {let start=ProcessInfo.processInfo.systemUptime;work();samples.append((ProcessInfo.processInfo.systemUptime-start)*1000)}
        return samples.sorted()[samples.count/2]
    }
    @MainActor static func main() throws {
        let calendar=Calendar(identifier:.gregorian)
        let start=Date.keyFormatter.date(from:"2024-01-01")!
        let dates=(0..<1096).map{calendar.date(byAdding:.day,value:$0,to:start)!}
        let keys=dates.map(\.shiftDateKey)
        let locations=(0..<10).map{HotelLocation(name:"Hotel \($0)")}
        var staff:[StaffMember]=[],rows:[ShiftAssignment]=[]
        rows.reserveCapacity(548000)
        for location in locations {
            let people=(0..<50).map{StaffMember(name:"Person \($0)",department:"Front",employment:"Full",hourlyWage:1500,locationID:location.id)}
            staff+=people
            for (day,key) in keys.enumerated(){for (personIndex,person) in people.enumerated(){
                rows.append(ShiftAssignment(staffID:person.id,dateKey:key,type:day%7<5 ? (personIndex%4==0 ? .night:.day):.off,locationID:location.id))
            }}
        }
        let data=ShiftData(locations:locations,staff:staff,assignments:rows)
        let index=ShiftLookupIndex(data), store=Store(data,index)
        func normalized(_ values:[(name:String,week:String,hours:Double)])->[String]{values.map{"\($0.name)|\($0.week)|\($0.hours)"}.sorted()}
        // Include year boundaries, leap February and neighboring-month weeks.
        for month in ["2024-01-01","2024-02-01","2026-10-01","2026-12-01"] {
            let labor=Labor(store,Date.keyFormatter.date(from:month)!)
            let before=normalized(labor.baselineWeekly);labor.renderCache=ShiftRenderCache()
            precondition(before==normalized(labor.optimizedWeekly),"weekly result changed at \(month)")
        }
        let noon=Date.keyFormatter.date(from:"2026-02-01")!.addingTimeInterval(12*3600)
        let noonLabor=Labor(store,noon)
        let noonBefore=normalized(noonLabor.baselineWeekly);noonLabor.renderCache=ShiftRenderCache()
        precondition(noonBefore==normalized(noonLabor.optimizedWeekly),"non-midnight month boundary changed")
        let month=Date.keyFormatter.date(from:"2026-10-01")!
        let labor=Labor(store,month)
        let oldWeekly=measured(3){labor.renderCache=ShiftRenderCache();sink+=labor.baselineWeekly.count}
        let newWeekly=measured(5){labor.renderCache=ShiftRenderCache();sink+=labor.optimizedWeekly.count}
        let weeks=WeeklyLaborSummary.weeks(overlapping:month)
        let candidateCount=store.selectedAssignments(on:Set(weeks.keys)).count
        var gridResults:[String:Any]=[:]
        for count in [1,50] {
            let edits=staff.prefix(count).map {person->ScheduleGridEdit in
                let i=index.assignmentByCell[.init(location:locations[0].id,staff:person.id,day:"2026-10-15")]!
                let before=data.assignments[i];var after=before;after.note="changed"
                return ScheduleGridEdit(key:.init(staffID:person.id,dateKey:before.dateKey),before:before,after:after)
            }
            let old=measured(3){let h=Store(data,index);sink += (try! h.baselineGrid(edits,locationID:locations[0].id,revision:0))!.edits.count}
            let new=measured(3){let h=Store(data,index);sink += (try! h.optimizedGrid(edits,locationID:locations[0].id,revision:0))!.edits.count}
            let a=Store(data,index),b=Store(data,index)
            _=try a.baselineGrid(edits,locationID:locations[0].id,revision:0)
            _=try b.optimizedGrid(edits,locationID:locations[0].id,revision:0)
            precondition(a.data.assignments==b.data.assignments)
            gridResults[String(count)]=["before_ms":old,"after_ms":new,"speedup":old/new]
        }
        let noopBefore=measured(3){let h=Store(data,index);precondition(try! h.baselineGrid([],locationID:locations[0].id,revision:0)==nil)}
        let noopAfter=measured(3){let h=Store(data,index);precondition(try! h.optimizedGrid([],locationID:locations[0].id,revision:0)==nil)}
        let report:[String:Any]=[
            "rows":rows.count,"locations":10,"staff_per_location":50,"days":1096,
            "weekly_before_ms":oldWeekly,"weekly_after_ms":newWeekly,"weekly_speedup":oldWeekly/newWeekly,
            "weekly_records_before":store.selectedAssignments.count,"weekly_records_after":candidateCount,
            "weekly_dates_prepared":weeks.count,"grid":gridResults,"noop_before_ms":noopBefore,"noop_after_ms":noopAfter,
            "uuid_temporary_array_bytes_removed":rows.count*MemoryLayout<UUID>.stride,
            "correctness":"weekly year/leap/month boundaries and complete edited arrays match",
            "scope":"Swift -O local Mac; query/edit core only; excludes UI, disk persistence and cloud"
        ]
        print(String(data:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
    }
}
'''.replace('OLDGRID',a).replace('NEWGRID',b).replace('OLDWEEKLY',c).replace('NEWWEEKLY',d).replace('\\.','\.')
with tempfile.TemporaryDirectory(prefix='fixed558-bench-') as folder:
    p=Path(folder);(p/'Runner.swift').write_text(program)
    sources=[r/'HOTEL_SHIFT/Models'/name for name in ['ShiftModels.swift','ShiftLookupIndex.swift','DayTimelineMath.swift','ScheduleGridSupport.swift']]
    subprocess.run(['swiftc','-O','-parse-as-library',*[str(s) for s in sources],str(p/'Runner.swift'),'-o',str(p/'bench')],check=True)
    result=subprocess.run([str(p/'bench')],capture_output=True,text=True,check=True,timeout=240)
    print(result.stdout);(r/'reports/fixed558_benchmark.json').write_text(result.stdout)
