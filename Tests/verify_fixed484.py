#!/usr/bin/env python3
"""Execute production profile/date save methods and old-backup decoding."""
from pathlib import Path
import subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
class StaffProfileTests(unittest.TestCase):
 def test_profile_saves_and_compatibility(self):
  source=(ROOT/'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()
  start=source.index('    @discardableResult\n    func updateStaff(')
  end=source.index('    func wageHistory(',start)
  methods=source[start:end]
  program='''import Foundation
@MainActor final class Store {
 var data: ShiftData
 func publishValueEdit(_ updated:ShiftData){data=updated}
 var selectedLocationID: UUID
 var storageWriteBlocked=false
 var selectedPersonalWorkTimes: [PersonalWorkTime] { (data.personalWorkTimes ?? []).filter { $0.locationID == selectedLocationID } }
 var selectedRequestsUnsorted: [ShiftRequest] { (data.requests ?? []).filter { $0.locationID == selectedLocationID } }
 init(_ data: ShiftData, _ locationID: UUID) { self.data=data; selectedLocationID=locationID }
'''+methods+'''}
@main struct Runner {
 @MainActor static func main() throws {
  let location=UUID(), other=UUID()
  let person=StaffMember(name:"Test",department:"Front",employment:"Custom value",hourlyWage:1200,locationID:location)
  var oldJSON=try JSONSerialization.jsonObject(with:JSONEncoder().encode(person)) as! [String:Any]
  oldJSON.removeValue(forKey:"joinDate"); oldJSON.removeValue(forKey:"leaveDate")
  let decoded=try JSONDecoder().decode(StaffMember.self,from:JSONSerialization.data(withJSONObject:oldJSON))
  precondition(decoded.joinDate==nil && decoded.leaveDate==nil && decoded.employment=="Custom value")
  precondition(StaffProfileValidation.validDates(join:nil,leave:nil))
  precondition(StaffProfileValidation.validDates(join:" 2026-01-01 ",leave:"2026-12-31"))
  precondition(!StaffProfileValidation.validDates(join:"2026-02-30",leave:nil))
  precondition(!StaffProfileValidation.validDates(join:"2026-2-01",leave:nil))
  precondition(!StaffProfileValidation.validDates(join:"2026-12-31",leave:"2026-01-01"))
  let shift=ShiftAssignment(staffID:person.id,dateKey:"2026-10-27",type:.day,note:"Keep",locationID:location)
  let pattern=ShiftPattern(name:"Weekly",scope:.individual,locationID:location,staffID:person.id)
  let store=Store(ShiftData(locations:[],staff:[person],assignments:[shift],patterns:[pattern]),location)
  precondition(store.saveStaffEmploymentDates(expected:person,join:" 2026-01-01 ",leave:"2026-12-31"))
  let dated=store.data.staff[0]
  precondition(dated.joinDate=="2026-01-01" && dated.leaveDate=="2026-12-31")
  precondition(store.data.assignments==[shift] && store.data.patterns==[pattern])
  precondition(!store.saveStaffEmploymentDates(expected:person,join:nil,leave:nil))
  precondition(!store.saveStaffEmploymentDates(expected:dated,join:"2027-01-01",leave:"2026-01-01"))
  precondition(store.saveStaffProfile(expected:dated,name:"Changed",department:"Kitchen",employment:"Custom value",wage:1300,photoData:Data([0,1])))
  let edited=store.data.staff[0]
  precondition(edited.name=="Changed" && edited.joinDate==dated.joinDate && edited.leaveDate==dated.leaveDate)
  precondition(edited.photoData==Data([0,1]) && edited.employment=="Custom value")
  precondition(store.data.assignments[0].hourlyWageSnapshot==1200 && store.data.assignments[0].note=="Keep")
  precondition(store.data.wageChanges?.count==1 && store.data.wageChanges?.first?.previousHourlyWage==1200)
  precondition(!store.saveStaffProfile(expected:dated,name:"Stale",department:"Wrong",employment:"",wage:1400,photoData:nil))
  store.selectedLocationID=other
  precondition(!store.setStaffProfileActive(expected:edited,active:false))
  precondition(!store.saveStaffEmploymentDates(expected:edited,join:nil,leave:nil))
  store.selectedLocationID=location
  store.storageWriteBlocked=true
  precondition(!store.setStaffProfileActive(expected:edited,active:false))
  precondition(!store.saveStaffProfile(expected:edited,name:"Blocked",department:"Kitchen",employment:"",wage:1400,photoData:nil))
  precondition(!store.saveStaffEmploymentDates(expected:edited,join:nil,leave:nil))
  store.storageWriteBlocked=false
  let assignments=store.data.assignments
  precondition(store.setStaffProfileActive(expected:edited,active:false))
  precondition(store.data.assignments==assignments && store.data.patterns==[pattern] && !store.data.staff[0].isActive)
  let inactive=store.data.staff[0]
  precondition(store.saveStaffEmploymentDates(expected:inactive,join:nil,leave:nil))
  precondition(store.data.staff[0].joinDate==nil && store.data.staff[0].leaveDate==nil)
  let paused=store.data.staff[0]
  precondition(store.setStaffProfileActive(expected:paused,active:true))
  let active=store.data.staff[0]
  let item=PersonalWorkTime(staffID:active.id,locationID:location,name:"Personal",startMinutes:660,endMinutes:1140,breakMinutes:45)
  store.data.personalWorkTimes=[item]
  let beforeApply=store.data.assignments[0]
  try store.applyStaffPersonalTime(item,date:Date.keyFormatter.date(from:beforeApply.dateKey)!,expectedStaff:active,expectedAssignment:beforeApply)
  let applied=store.data.assignments[0]
  precondition(applied.customStartMinutes==660 && applied.customEndMinutes==1140 && applied.customBreakMinutes==45)
  precondition(applied.note==beforeApply.note && applied.hourlyWageSnapshot==1200 && applied.patternNameSnapshot=="Personal")
  let leaveDate=Date.keyFormatter.date(from:"2026-10-29")!
  store.data.requests=[ShiftRequest(staffID:active.id,dateKey:leaveDate.shiftDateKey,reason:"Leave",status:.approved,locationID:location)]
  do { try store.applyStaffPersonalTime(item,date:leaveDate,expectedStaff:active,expectedAssignment:nil); preconditionFailure("approved leave overwritten") } catch DayShiftEditError.leave {}
  precondition(store.data.assignments.count==1)
  try store.applyStaffPersonalTime(item,date:leaveDate,expectedStaff:active,expectedAssignment:nil,allowLeave:true)
  precondition(store.data.assignments.count==2 && store.data.assignments[1].hourlyWageSnapshot==1300)
  store.data.personalWorkTimes?[0].name="Changed template"
  do { try store.applyStaffPersonalTime(item,date:leaveDate,expectedStaff:active,expectedAssignment:store.data.assignments[1],allowLeave:true); preconditionFailure("stale template accepted") } catch DayShiftEditError.changed {}
  print("Old backup decoding, date order/normalization, profile/photo edits, wage freezing/history, stale/hotel/protected guards and status preservation passed")
 }
}
'''
  with tempfile.TemporaryDirectory() as tmp:
   src=Path(tmp)/'Runner.swift';src.write_text(program)
   r=subprocess.run(['swiftc','-parse-as-library','-module-cache-path',tmp+'/cache',str(ROOT/'HOTEL_SHIFT/Models/ShiftModels.swift'),str(ROOT/'HOTEL_SHIFT/Models/DayTimelineMath.swift'),str(src),'-o',tmp+'/test'],capture_output=True,text=True,timeout=60)
   self.assertEqual(r.returncode,0,r.stderr)
   r=subprocess.run([tmp+'/test'],capture_output=True,text=True,timeout=30)
   self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__': unittest.main()
