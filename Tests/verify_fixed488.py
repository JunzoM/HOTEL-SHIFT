from pathlib import Path
import subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
class RequestTests(unittest.TestCase):
 def test_workflow(self):
  source=(ROOT/'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()
  methods=source[source.index('    // FIXED488: Receive'):source.index('    func addRequest(staffID:')]
  program='''import Foundation
@MainActor final class Store {
 var data: ShiftData
 var selectedLocationID: UUID
 var storageWriteBlocked = false
 var selectedStaff: [StaffMember] { data.staff.filter { $0.locationID == selectedLocationID } }
 var selectedAssignments: [ShiftAssignment] { data.assignments.filter { $0.locationID == selectedLocationID } }
 init(_ data:ShiftData,_ location:UUID) { self.data=data; selectedLocationID=location }
'''+methods+'''}
@main struct Runner {
 @MainActor static func main() throws {
  let month=Date.keyFormatter.date(from:"2026-11-01")!
  let form=RequestInboxTools.fields("名前：山田 太郎\\n休みたい日：11/3、11/10〜12\\n理由：9時、20人で通院")!
  precondition(form.name=="山田 太郎")
  precondition(RequestInboxTools.dates(form.dates,month:month)==["2026-11-03","2026-11-10","2026-11-11","2026-11-12"])
  precondition(RequestInboxTools.dates("２０２８年２月２９日、2/30、13/2",month:month)==["2028-02-29"])
  precondition(RequestInboxTools.dates("1/2",month:Date.keyFormatter.date(from:"2026-12-01")!)==["2027-01-02"])
  precondition(RequestInboxTools.dates("2025/11/3",month:month)==["2025-11-03"])
  precondition(RequestInboxTools.dates("11/3 9:00〜18:00",month:month)==["2026-11-03"])
  let loc=UUID(), other=UUID()
  let p=StaffMember(name:"山田 太郎",department:"フロント",employment:"社員",hourlyWage:1200,locationID:loc)
  let q=StaffMember(name:"山田 花子",department:"フロント",employment:"社員",hourlyWage:1200,locationID:loc)
  precondition(RequestInboxTools.detect("山田太郎",staff:[p,q])==p.id)
  precondition(RequestInboxTools.detect("山田です",staff:[p,q])==nil)
  let s=ShiftAssignment(staffID:p.id,dateKey:"2026-11-03",type:.day,note:"keep",locationID:loc,customStartMinutes:540,customEndMinutes:1080,hourlyWageSnapshot:1100)
  let paid=ShiftAssignment(staffID:p.id,dateKey:"2026-11-10",type:.paidLeave,locationID:loc)
  let store=Store(ShiftData(locations:[HotelLocation(id:loc,name:"Test"),HotelLocation(id:other,name:"Other")],staff:[p,q],assignments:[s,paid]),loc)
  let result=try store.receiveRequestText(expectedStaff:p,dateKeys:["2026-11-03","2026-11-03","2026-11-10"],reason:"通院")
  precondition(result.added==2)
  let duplicate=try store.receiveRequestText(expectedStaff:p,dateKeys:["2026-11-03"],reason:"別の理由"); precondition(duplicate.skipped==1)
  let rows=store.data.requests!
  try store.decideRequestBatch(expected:rows,staffSnapshot:store.selectedStaff,assignmentSnapshot:store.selectedAssignments,locationID:loc,status:.approved,alsoOff:false)
  precondition(store.data.assignments==[s,paid])
  let approved=store.data.requests!
  try store.decideRequestBatch(expected:approved,staffSnapshot:store.selectedStaff,assignmentSnapshot:store.selectedAssignments,locationID:loc,status:.approved,alsoOff:true)
  precondition(store.data.assignments[0].type == .off && store.data.assignments[0].customStartMinutes == nil)
  precondition(store.data.assignments[0].note=="keep" && store.data.assignments[0].hourlyWageSnapshot==1100)
  precondition(store.data.assignments[1]==paid)
  precondition(RequestInboxTools.reply(staff:[p],requests:store.data.requests!).contains("山田 太郎さん"))
  let frozen=store.data.requests!
  do { try store.decideRequestBatch(expected:rows,staffSnapshot:store.selectedStaff,assignmentSnapshot:store.selectedAssignments,locationID:loc,status:.rejected,alsoOff:false); preconditionFailure("stale accepted") } catch {}
  precondition(store.data.requests! == frozen)
  store.selectedLocationID=other
  do { _=try store.receiveRequestText(expectedStaff:p,dateKeys:["2026-11-20"],reason:""); preconditionFailure("wrong store") } catch {}
  store.selectedLocationID=loc; store.storageWriteBlocked=true
  do { try store.deleteRequestSafely(frozen[0]); preconditionFailure("blocked delete") } catch {}
  store.storageWriteBlocked=false
  let oldShifts=store.selectedAssignments; store.data.assignments[0].note="changed"
  do { try store.decideRequestBatch(expected:frozen,staffSnapshot:store.selectedStaff,assignmentSnapshot:oldShifts,locationID:loc,status:.approved,alsoOff:true); preconditionFailure("stale shift") } catch {}
  try store.decideRequestBatch(expected:frozen,staffSnapshot:store.selectedStaff,assignmentSnapshot:store.selectedAssignments,locationID:loc,status:.pending,alsoOff:false)
  precondition(store.data.assignments[0].type == .off)
  try store.decideRequestBatch(expected:store.data.requests!,staffSnapshot:store.selectedStaff,assignmentSnapshot:store.selectedAssignments,locationID:loc,status:.rejected,alsoOff:false)
  let retry=try store.receiveRequestText(expectedStaff:p,dateKeys:["2026-11-03"],reason:""); precondition(retry.added==1)
  let delete=store.data.requests!.last!; try store.deleteRequestSafely(delete)
  precondition(!store.data.requests!.contains(delete))
  let visiting=StaffMember(name:"Other Staff",department:"Front",employment:"社員",hourlyWage:1200,locationID:other)
  store.data.staff.append(visiting)
  let received=try store.receiveRequestAtLocation(expectedStaff:visiting,locationID:other,dateKeys:["2026-11-21"],reason:"other store")
  precondition(received.added==1 && store.selectedLocationID==loc)
  precondition(store.data.requests!.last!.locationID==other && store.data.requests!.last!.staffID==visiting.id)
  do { _=try store.receiveRequestAtLocation(expectedStaff:visiting,locationID:loc,dateKeys:["2026-11-22"],reason:""); preconditionFailure("staff shop mismatch") } catch {}
  store.storageWriteBlocked=true
  do { _=try store.receiveRequestAtLocation(expectedStaff:visiting,locationID:other,dateKeys:["2026-11-22"],reason:""); preconditionFailure("protected intake") } catch {}

 }
}
'''
  with tempfile.TemporaryDirectory() as tmp:
   src=Path(tmp)/'Runner.swift';src.write_text(program)
   r=subprocess.run(['swiftc','-parse-as-library','-module-cache-path',tmp+'/cache',str(ROOT/'HOTEL_SHIFT/Models/ShiftModels.swift'),str(src),'-o',tmp+'/test'],capture_output=True,text=True,timeout=60)
   self.assertEqual(r.returncode,0,r.stderr)
   r=subprocess.run([tmp+'/test'],capture_output=True,text=True,timeout=30)
   self.assertEqual(r.returncode,0,r.stderr)
if __name__=='__main__': unittest.main()
