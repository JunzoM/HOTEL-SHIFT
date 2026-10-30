#!/usr/bin/env python3
"""Execute actual presentation and atomic batch methods, including old-backup decoding."""
from pathlib import Path
import subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
class GridTests(unittest.TestCase):
 def test_display_and_batches(self):
  source=(ROOT/'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()
  start=source.index('    func applyScheduleGrid(')
  end=source.index('    var selectedPatterns:',start)
  methods=source[start:end]
  ui=(ROOT/'HOTEL_SHIFT/Views/IntegratedScheduleGrid.swift').read_text()
  copy_start=ui.index('    private func prepareCopyWeek()')
  copy_end=ui.index('    private func commit(',copy_start)
  leave_start=ui.index('    private func hasLeave(')
  leave_end=ui.index('    private func prepareBulk(',leave_start)
  batch_start=ui.index('    private struct PendingBatch {')
  batch_end=ui.index('    private struct TimeEdit:',batch_start)
  copy_methods=ui[leave_start:leave_end]+ui[copy_start:copy_end]
  batch_type=ui[batch_start:batch_end].replace('private struct','struct',1)
  program='''import Foundation
@MainActor final class Store {
 var pdfRevision: UInt64 = 0
 var data: ShiftData { didSet { pdfRevision += 1 } }
 func publishValueEdit(_ updated:ShiftData){data=updated}
 var selectedLocationID: UUID
 var storageWriteBlocked = false
 var lookup:ShiftLookupIndex { ShiftLookupIndex(data) }
 func assignment(staffID: UUID, date: Date) -> ShiftAssignment? {
  data.assignments.first { $0.staffID == staffID && $0.dateKey == date.shiftDateKey && $0.locationID == selectedLocationID }
 }
 var selectedStaff:[StaffMember] {data.staff.filter{$0.locationID==selectedLocationID}}
 var selectedAssignments:[ShiftAssignment] {data.assignments.filter{$0.locationID==selectedLocationID}}
 func hasApprovedLeave(staffID:UUID,dateKey:String)->Bool {(data.requests ?? []).contains{$0.locationID==selectedLocationID && $0.staffID==staffID && $0.dateKey==dateKey && $0.status == .approved}}
 var selectedRequestsUnsorted: [ShiftRequest] { (data.requests ?? []).filter { $0.locationID == selectedLocationID } }
 init(_ data: ShiftData, _ location: UUID) { self.data=data; selectedLocationID=location }
'''+methods+'''}
@MainActor final class CopyGrid {
 let store: Store
 let people: [StaffMember]
 let visibleDates: [Date]
 let calendar=Calendar.current
 var selecting = false
 var selected: Set<ScheduleGridKey> = []
 var pending: PendingBatch?
 var message: String?
 init(_ store: Store, _ people: [StaffMember], _ dates: [Date]) { self.store=store; self.people=people; visibleDates=dates }
 func run() { prepareCopyWeek() }
'''+batch_type+copy_methods+'''}
@main struct Runner {
 @MainActor static func main() throws {
  let location=UUID(), other=UUID()
  let a=StaffMember(name:"A",department:"Front",employment:"Full",hourlyWage:1200,locationID:location)
  let b=StaffMember(name:"B",department:"Front",employment:"Full",hourlyWage:1300,locationID:location)
  let date="2026-10-27"
  let octoberFirst=Calendar.current.date(from:DateComponents(year:2026,month:10,day:1))!
  precondition(ScheduleGridSupport.dateLabel(octoberFirst)=="10/1")
  let night=ShiftAssignment(staffID:a.id,dateKey:date,type:.night,locationID:location)
  precondition(ScheduleGridSupport.timeLines(night)==["21:00","翌9:00"])
  var custom=night
  custom.customStartMinutes=675; custom.customEndMinutes=1500; custom.customBreakMinutes=45
  custom.patternNameSnapshot="Evening pattern"
  precondition(ScheduleGridSupport.timeLines(custom)==["11:15","翌1:00"])
  precondition(ScheduleGridSupport.label(custom)=="Evening pattern")
  let reset=ScheduleGridSupport.replacing(custom,type:.early,staff:a,dateKey:date,locationID:location)
  precondition(reset.patternNameSnapshot==nil && reset.customStartMinutes==nil)
  precondition(ScheduleGridSupport.timeLines(reset)==["6:00","15:00"])
  precondition(ScheduleGridSupport.replacing(custom,type:.night,staff:a,dateKey:date,locationID:location).customStartMinutes==675)
  let off=ShiftAssignment(staffID:b.id,dateKey:date,type:.off,locationID:location)
  precondition(ScheduleGridSupport.timeLines(off).isEmpty)
  var pattern=ShiftPattern(name:"Test Pattern",scope:.everyone,locationID:location)
  precondition(ScheduleGridSupport.patternTimeLines(pattern,type:.night)==["21:00","翌9:00"])
  pattern.customStartMinutes=675; pattern.customEndMinutes=1500
  precondition(ScheduleGridSupport.patternTimeLines(pattern,type:.day)==["11:15","翌1:00"])
  precondition(ScheduleGridSupport.patternTimeLines(pattern,type:.off).isEmpty)
  let summary=ScheduleGridSupport.summary([night,off])
  precondition(summary.days==1 && summary.hours==11)
  var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(night)) as! [String:Any]
  object.removeValue(forKey:"patternNameSnapshot")
  let old=try JSONDecoder().decode(ShiftAssignment.self,from:JSONSerialization.data(withJSONObject:object))
  precondition(old.patternNameSnapshot==nil)
  let store=Store(ShiftData(locations:[],staff:[a,b],assignments:[]),location)
  let first=ScheduleGridEdit(key:.init(staffID:a.id,dateKey:date),before:nil,after:custom)
  let second=ScheduleGridEdit(key:.init(staffID:b.id,dateKey:date),before:nil,after:off)
  let change=try store.applyScheduleGrid([first,second],locationID:location,revision:store.pdfRevision)!
  precondition(store.data.assignments.count==2 && store.pdfRevision==1)
  try store.restoreScheduleGrid(change,undo:true)
  precondition(store.data.assignments.isEmpty)
  try store.restoreScheduleGrid(change,undo:false)
  precondition(store.data.assignments==[custom,off])
  let before=store.data.assignments
  let empty=ScheduleGridEdit(key:.init(staffID:a.id,dateKey:date),before:custom,after:nil)
  let stale=ScheduleGridEdit(key:.init(staffID:b.id,dateKey:date),before:nil,after:off)
  do { _=try store.applyScheduleGrid([empty,stale],locationID:location,revision:store.pdfRevision); preconditionFailure("partial stale edit accepted") } catch DayShiftEditError.changed {}
  precondition(store.data.assignments==before)
  do { _=try store.applyScheduleGrid([empty],locationID:location,revision:0); preconditionFailure("old confirmation accepted") } catch DayShiftEditError.changed {}
  do { _=try store.applyScheduleGrid([empty],locationID:other,revision:store.pdfRevision); preconditionFailure("wrong hotel accepted") } catch DayShiftEditError.changed {}
  let invalid=ScheduleGridEdit(key:.init(staffID:a.id,dateKey:"2026-99-99"),before:nil,after:nil)
  do { _=try store.applyScheduleGrid([invalid],locationID:location,revision:store.pdfRevision); preconditionFailure("invalid date accepted") } catch DayShiftEditError.invalid {}
  store.data.requests=[ShiftRequest(staffID:a.id,dateKey:date,reason:"Leave",status:.approved,locationID:location)]
  let working=ScheduleGridEdit(key:first.key,before:custom,after:reset)
  do { _=try store.applyScheduleGrid([working],locationID:location,revision:store.pdfRevision); preconditionFailure("leave overwritten") } catch DayShiftEditError.leave {}
  _=try store.applyScheduleGrid([working],locationID:location,revision:store.pdfRevision,allowLeave:true)
  precondition(store.data.assignments[0]==reset)
  do { _=try store.applyScheduleGrid([empty,empty],locationID:location,revision:store.pdfRevision); preconditionFailure("duplicate cells accepted") } catch DayShiftEditError.invalid {}
  // Execute the production copy-week UI planner with existing/leave destinations.
  var bSource=off
  bSource.type = .day
  var occupied=off
  occupied.id=UUID(); occupied.dateKey="2026-11-03"
  let copyStore=Store(ShiftData(locations:[],staff:[a,b],assignments:[custom,bSource,occupied]),location)
  let copyDate=Date.keyFormatter.date(from:date)!
  let copyGrid=CopyGrid(copyStore,[a,b],[copyDate])
  copyGrid.run()
  precondition(copyGrid.pending?.edits.count==1)
  let copied=copyGrid.pending!.edits[0].after!
  precondition(copied.id != custom.id && copied.dateKey=="2026-11-03")
  precondition(copied.customStartMinutes==675 && copied.customEndMinutes==1500 && copied.patternNameSnapshot==custom.patternNameSnapshot && copied.hourlyWageSnapshot==a.hourlyWage)
  let selectedCopy=CopyGrid(copyStore,[a,b],[copyDate])
  selectedCopy.selecting=true
  selectedCopy.selected=[ScheduleGridKey(staffID:b.id,dateKey:date)]
  selectedCopy.run()
  precondition(selectedCopy.pending==nil, "Unselected source was copied")
  copyStore.data.requests=[ShiftRequest(staffID:a.id,dateKey:"2026-11-03",reason:"Leave",status:.approved,locationID:location)]
  let leaveCopy=CopyGrid(copyStore,[a,b],[copyDate])
  leaveCopy.run()
  precondition(leaveCopy.pending==nil && leaveCopy.message != nil)
  // The optimized position-update path must retain full-array ID validation.
  var duplicateID=off;duplicateID.id=custom.id
  let damaged=Store(ShiftData(locations:[],staff:[a,b],assignments:[custom,duplicateID]),location)
  var noted=custom;noted.note="new note"
  let noteEdit=ScheduleGridEdit(key:first.key,before:custom,after:noted)
  do { _=try damaged.applyScheduleGrid([noteEdit],locationID:location,revision:damaged.pdfRevision);preconditionFailure("global duplicate IDs accepted by fast path") } catch DayShiftEditError.invalid {}
  precondition(damaged.data.assignments==[custom,duplicateID])
  let safe=Store(ShiftData(locations:[],staff:[a,b],assignments:[custom,off]),location)
  let noteChange=try safe.applyScheduleGrid([noteEdit],locationID:location,revision:safe.pdfRevision)!
  precondition(safe.data.assignments==[noted,off])
  try safe.restoreScheduleGrid(noteChange,undo:true)
  precondition(safe.data.assignments==[custom,off])
  var collision=custom;collision.id=off.id
  do { _=try safe.applyScheduleGrid([ScheduleGridEdit(key:first.key,before:custom,after:collision)],locationID:location,revision:safe.pdfRevision);preconditionFailure("replacement ID collision accepted") } catch DayShiftEditError.invalid {}
  precondition(safe.data.assignments==[custom,off])
  let unchanged=try safe.applyScheduleGrid([],locationID:location,revision:safe.pdfRevision)
  precondition(unchanged==nil)
  do { _=try safe.applyScheduleGrid([],locationID:other,revision:safe.pdfRevision);preconditionFailure("empty edit bypassed hotel guard") } catch DayShiftEditError.changed {}
  safe.storageWriteBlocked=true
  do { _=try safe.applyScheduleGrid([],locationID:location,revision:safe.pdfRevision);preconditionFailure("empty edit bypassed storage guard") } catch DayShiftEditError.storage {}
  print("Actual/default/overnight display, pattern snapshots, old backups, summaries, atomic bulk, undo/redo, revision/hotel/date/leave/duplicate guards passed")
 }
}
'''
  with tempfile.TemporaryDirectory() as tmp:
   src=Path(tmp)/'Runner.swift'; src.write_text(program)
   args=['swiftc','-parse-as-library','-module-cache-path',tmp+'/cache']+[str(ROOT/'HOTEL_SHIFT/Models'/name) for name in ['ShiftModels.swift','DayTimelineMath.swift','ScheduleGridSupport.swift','ShiftLookupIndex.swift']]+[str(src),'-o',tmp+'/test']
   r=subprocess.run(args,capture_output=True,text=True,timeout=60); self.assertEqual(r.returncode,0,r.stderr)
   r=subprocess.run([tmp+'/test'],capture_output=True,text=True,timeout=30); self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__': unittest.main()
