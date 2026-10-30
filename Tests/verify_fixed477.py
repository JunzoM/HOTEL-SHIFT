#!/usr/bin/env python3
"""Execute actual timeline math and storage methods without an iOS UI runtime."""
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
class TimelineTests(unittest.TestCase):
 def test_math_and_atomic_storage(self):
  text=(ROOT/'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()
  start=text.index('    func applyDayTimeline(')
  end=text.index('    // FIXED478:',start)
  methods=text[start:end]
  program='''import Foundation
@MainActor final class Store {
 var data: ShiftData
 var selectedLocationID: UUID
 var storageWriteBlocked = false
 var selectedRequestsUnsorted: [ShiftRequest] { (data.requests ?? []).filter { $0.locationID == selectedLocationID } }
 init(_ data: ShiftData, _ location: UUID) { self.data=data; selectedLocationID=location }
'''+methods+'''}
@main struct Runner {
 @MainActor static func main() throws {
  let location=UUID(), other=UUID()
  let person=StaffMember(name: "Test",department: "Front",employment: "Full",hourlyWage: 1200,locationID: location)
  let date=Date.keyFormatter.date(from: "2026-10-27")!
  let night=ShiftAssignment(staffID: person.id,dateKey: date.shiftDateKey,type: .night,note: "keep note",locationID: location,customBreakMinutes: 60,customBreakStartMinutes: 1500,hourlyWageSnapshot: 900)
  precondition(DayTimelineMath.span(night) == DayTimelineMath.Span(start:1260,end:1980))
  precondition(DayTimelineMath.span(ShiftAssignment(staffID: person.id,dateKey: date.shiftDateKey,type: .off)) == nil)
  precondition(DayTimelineMath.label(1980) == "翌9:00")
  precondition(DayTimelineMath.newSpan(at: 1440, step: 30) == nil)
  precondition(DayTimelineMath.newSpan(at: 1260, step: 30) == .init(start:1260,end:1740))
  precondition(DayTimelineMath.headcount([.init(start:540,end:600),.init(start:600,end:660)],hour:10)==1)
  for step in [15,30] {
   for initial in [DayTimelineMath.Span(start:0,end:480),.init(start:1260,end:1980),.init(start:1439,end:2879)] {
    for delta in stride(from:-4000,through:4000,by:step) {
     for mode in [DayTimelineMath.Mode.move,.start,.end] {
      let next=DayTimelineMath.changed(initial,mode:mode,delta:delta,step:step)
      precondition(next.start>=0 && next.start<1440 && next.end<=2879 && next.end>next.start)
      if case .move=mode { precondition(next.end-next.start == initial.end-initial.start) }
     }
    }
    precondition(DayTimelineMath.changed(initial,mode:.move,delta:0,step:step)==initial)
   }
  }
  let store=Store(ShiftData(locations:[],staff:[person],assignments:[night]),location)
  let change=try store.applyDayTimeline(staffID:person.id,date:date,span:.init(start:1320,end:1350),locationID:location,expected:night)!
  precondition(change.after.customBreakMinutes==30 && change.after.customBreakStartMinutes==1320)
  precondition(change.after.note==night.note && change.after.hourlyWageSnapshot==900 && change.after.type == .night)
  try store.restoreDayTimeline(change,undo:true)
  precondition(store.data.assignments == [night])
  try store.restoreDayTimeline(change,undo:false)
  precondition(store.data.assignments == [change.after])
  let before=store.data.assignments
  do { _ = try store.applyDayTimeline(staffID:person.id,date:date,span:.init(start:540,end:1020),locationID:location,expected:night); preconditionFailure("stale edit accepted") } catch DayShiftEditError.changed {}
  precondition(store.data.assignments==before)
  store.selectedLocationID=other
  do { try store.restoreDayTimeline(change,undo:true); preconditionFailure("wrong hotel accepted") } catch DayShiftEditError.changed {}
  store.selectedLocationID=location
  store.data.assignments=[]
  let created=try store.applyDayTimeline(staffID:person.id,date:date,span:.init(start:540,end:1020),locationID:location,expected:nil)!
  precondition(created.before==nil && created.after.type == .day && created.after.hourlyWageSnapshot==1200)
  try store.restoreDayTimeline(created,undo:true)
  precondition(store.data.assignments.isEmpty)
  try store.restoreDayTimeline(created,undo:false)
  precondition(store.data.assignments == [created.after])
  store.data.requests=[ShiftRequest(staffID:person.id,dateKey:date.shiftDateKey,reason:"Leave",status:.approved,locationID:location)]
  do { _ = try store.applyDayTimeline(staffID:person.id,date:date,span:.init(start:600,end:1080),locationID:location,expected:created.after); preconditionFailure("leave overwritten without confirmation") } catch DayShiftEditError.leave {}
  _ = try store.applyDayTimeline(staffID:person.id,date:date,span:.init(start:600,end:1080),locationID:location,expected:created.after,allowLeave:true)
  store.storageWriteBlocked=true
  do { _ = try store.applyDayTimeline(staffID:person.id,date:date,span:.init(start:0,end:10),locationID:location,expected:nil); preconditionFailure("protected storage changed") } catch DayShiftEditError.storage {}
  store.storageWriteBlocked=false
  store.data.staff[0].isActive=false
  do { _ = try store.applyDayTimeline(staffID:person.id,date:date,span:.init(start:0,end:480),locationID:location,expected:nil); preconditionFailure("paused staff assigned") } catch DayShiftEditError.unavailable {}
  print("Timeline boundaries, overnight, headcounts, undo/redo, metadata, stale/hotel/leave/storage/active guards passed")
 }
}
'''
  with tempfile.TemporaryDirectory() as tmp:
   src=Path(tmp)/'Runner.swift'; src.write_text(program)
   binary=Path(tmp)/'test'
   args=['swiftc','-parse-as-library','-module-cache-path',tmp+'/cache',str(ROOT/'HOTEL_SHIFT/Models/ShiftModels.swift'),str(ROOT/'HOTEL_SHIFT/Models/DayTimelineMath.swift'),str(src),'-o',str(binary)]
   r=subprocess.run(args,capture_output=True,text=True,timeout=60)
   self.assertEqual(r.returncode,0,r.stderr)
   r=subprocess.run([str(binary)],capture_output=True,text=True,timeout=30)
   self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__': unittest.main()
