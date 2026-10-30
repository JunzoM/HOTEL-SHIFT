from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
s=(root/'HOTEL_SHIFT/Services/ShiftStore.swift').read_text().replace('nonisolated private static func isValidBackup', 'private static func isValidBackup')
validator=s[s.index('    private static func isValidBackup('):s.index('    func exportBackup()')].replace('private static func','static func')
methods=s[s.index('    var hasSampleLocations:'):s.index('    // Shared snapshots use exactly')]
program='''import Foundation
final class Store {
 var data:ShiftData
 var selectedLocationID:UUID
 var storageWriteBlocked=false
 var needsSave=false
 init(_ data:ShiftData){self.data=data;selectedLocationID=data.locations[0].id}
 func flushPendingSave(){}
'''+validator+methods+'''}
@main struct Runner {
 static func main() throws {
 let anchor=Date.keyFormatter.date(from:"2026-10-28")!
 let sample=SampleShiftData.make(anchor:anchor)
 precondition(Store.isValidBackup(sample))
 precondition(sample.locations.count==4 && sample.staff.count==100 && sample.assignments.count==6100)
 precondition(sample.requests?.count==200 && sample.patterns?.count==20 && sample.personalWorkTimes?.count==100)
 for shop in sample.locations {
  let staff=sample.staff.filter{$0.locationID==shop.id}
  precondition(staff.count==25 && Set(staff.map(\\.name)).count==25)
  precondition(Set(staff.map(\\.department)).count==5)
 }
 let keys=Set(sample.assignments.map{String($0.staffID.uuidString)+$0.dateKey})
 precondition(keys.count==sample.assignments.count)
 for request in sample.requests! where request.status == .approved {
  precondition(sample.assignments.first{$0.staffID==request.staffID && $0.dateKey==request.dateKey}?.type == .off)
 }
 let same=SampleShiftData.make(anchor:anchor)
 precondition(sample.locations==same.locations && sample.staff==same.staff && sample.assignments==same.assignments)
 let real=HotelLocation(name:"既存店舗")
 let person=StaffMember(name:"既存",department:"既存部署",employment:"正社員",hourlyWage:1300,locationID:real.id)
 let assignment=ShiftAssignment(staffID:person.id,dateKey:"2026-10-28",type:.day,locationID:real.id)
 let old=ShiftData(locations:[real],staff:[person],assignments:[assignment])
 let store=Store(old)
 precondition(store.addSampleData(anchor:anchor))
 precondition(store.data.locations.count==5 && store.data.staff.count==101)
 precondition(store.data.locations[0]==real && store.data.staff[0]==person && store.data.assignments[0]==assignment)
 precondition(!store.addSampleData(anchor:anchor) && store.data.staff.count==101)
 precondition(Store.isValidBackup(store.data))
 let protected=Store(old);protected.storageWriteBlocked=true
 precondition(!protected.addSampleData(anchor:anchor) && protected.data.staff==[person])
 for key in ["2028-02-29","2026-12-31"] {
  precondition(Store.isValidBackup(SampleShiftData.make(anchor:Date.keyFormatter.date(from:key)!)))
 }
 let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
 let bytes=try encoder.encode(sample)
 let decoded=try JSONDecoder().decode(ShiftData.self,from:bytes)
 precondition(Store.isValidBackup(decoded))
 try bytes.write(to:URL(fileURLWithPath:CommandLine.arguments[1]),options:.atomic)
 print("4 stores x 25 staff; 6100 shifts, 200 requests; approved-leave consistency, stable/unique IDs, existing-data preservation, duplicate/protected guards, leap/year-boundary and backup roundtrip passed")
 }
}
'''
(root/'Samples').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)/'Runner.swift';p.write_text(program)
 subprocess.run(['swiftc','-parse-as-library','-module-cache-path',tmp+'/cache',str(root/'HOTEL_SHIFT/Models/ShiftModels.swift'),str(p),'-o',tmp+'/test'],check=True)
 subprocess.run([tmp+'/test',str(root/'Samples/サンプル4店舗_各25人_2026-10_11.json')],check=True)
