from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
view=(root/'HOTEL_SHIFT/Views/StaffAndOtherViews.swift').read_text()
store=(root/'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()
rename=view[view.index('    private func renameDepartment()'):view.index('    private func addDepartment()')].replace('private func','func').replace('UserDefaults.standard','defaults')
valid=store[store.index('    private func isValidPattern('):store.index('    var selectedPersonalWorkTimes:')]
methods=store[store.index('    @discardableResult\n    func savePatternSafely('):store.index('    func deletePattern(_')]
methods += store[store.index('    func setShift(staffID:'):store.index('    func setShiftTimes(')]
methods += store[store.index('    var selectedBasicPatterns:'):store.index('    private func isValidPattern(')]
program='''import Foundation
final class Store {
 var data: ShiftData
 func publishValueEdit(_ updated:ShiftData){data=updated}
 var selectedLocationID: UUID
 init(_ data: ShiftData,_ id:UUID) {self.data=data;selectedLocationID=id}
'''+valid+methods+'''}
final class Departments {
 let store:Store
 let defaults:UserDefaults
 var builtInDepartments=["フロント","キッチン","ルームメイク"]
 var customDepartments=[String]()
 var departmentToEdit:String?
 var editedDepartmentName=""
 var selectedDepartment="フロント"
 var allDepartments:[String] {Array(Set(builtInDepartments+customDepartments+store.data.staff.map(\\.department)))}
 init(_ store:Store,_ defaults:UserDefaults){self.store=store;self.defaults=defaults}
'''+rename+'''}
@main struct Runner {
 static func main() throws {
 let suite="fixed499-test-"+UUID().uuidString
 let prefs=UserDefaults(suiteName:suite)!
 defer {prefs.removePersistentDomain(forName:suite)}
 let location=HotelLocation(name:"Test")
 let person=StaffMember(name:"A",department:"フロント",employment:"正社員",hourlyWage:1200,locationID:location.id)
 let assignment=ShiftAssignment(staffID:person.id,dateKey:"2026-10-28",type:.day,note:"keep",locationID:location.id)
 let store=Store(ShiftData(locations:[location],staff:[person],assignments:[assignment]),location.id)
 let basics=store.selectedBasicPatterns
 precondition(basics.map(\.name)==["早番","日勤","遅番","夜勤"])
 precondition(basics.map{$0.customStartMinutes!}==[360,540,780,1260])
 precondition(basics.map{$0.customEndMinutes!}==[900,1080,1320,1980])
 precondition(Set(basics.map(\.id)).count==4 && store.selectedBasicPatterns==basics)
 var early=basics[0];early.customStartMinutes=420
 early.customBreakStartMinutes=660
 precondition(store.savePatternSafely(early,expected:nil))
 precondition(store.selectedBasicPatterns[0]==early)
 precondition(store.data.assignments==[assignment])
 let testDate=Date.keyFormatter.date(from:"2026-11-01")!
 store.setShift(staffID:person.id,date:testDate,type:.early)
 precondition(store.data.assignments.last?.customStartMinutes==420)
 let snapshot=store.data.assignments.last!
 let gridNew=ScheduleGridSupport.replacing(nil,type:.early,staff:person,dateKey:"2026-11-03",locationID:location.id,preset:early)
 precondition(gridNew.customStartMinutes==420 && gridNew.customEndMinutes==900)
 let gridSame=ScheduleGridSupport.replacing(gridNew,type:.early,staff:person,dateKey:gridNew.dateKey,locationID:location.id,preset:basics[0])
 precondition(gridSame==gridNew)
 let gridOff=ScheduleGridSupport.replacing(gridNew,type:.off,staff:person,dateKey:gridNew.dateKey,locationID:location.id)
 precondition(gridOff.customStartMinutes==nil && gridOff.customEndMinutes==nil)
 var changedEarly=early;changedEarly.customStartMinutes=450
 precondition(store.savePatternSafely(changedEarly,expected:early))
 precondition(store.data.assignments.last==snapshot)
 let nextDate=Date.keyFormatter.date(from:"2026-11-02")!
 store.setShift(staffID:person.id,date:nextDate,type:.early)
 precondition(store.data.assignments.last?.customStartMinutes==450)
 var bad=changedEarly;bad.scope = .individual
 precondition(!store.savePatternSafely(bad,expected:changedEarly))
 store.data.assignments=[assignment]
 store.data.patterns=[]
 let deps=Departments(store,prefs)
 deps.departmentToEdit="フロント";deps.editedDepartmentName="  接客  ";deps.renameDepartment()
 precondition(deps.builtInDepartments==["接客","キッチン","ルームメイク"])
 precondition(prefs.stringArray(forKey:"hotelShift.standardDepartments")==deps.builtInDepartments)
 precondition(store.data.staff[0].department=="接客" && deps.selectedDepartment=="接客")
 precondition(store.data.assignments==[assignment] && store.data.staff[0].id==person.id)
 deps.departmentToEdit="接客";deps.editedDepartmentName="キッチン";deps.renameDepartment()
 precondition(deps.builtInDepartments[0]=="接客")
 deps.editedDepartmentName="   ";deps.renameDepartment();precondition(deps.builtInDepartments[0]=="接客")
 deps.customDepartments=["宴会"];deps.departmentToEdit="宴会";deps.editedDepartmentName="料飲";deps.renameDepartment()
 precondition(deps.customDepartments==["料飲"] && prefs.stringArray(forKey:"hotelShift.customDepartments")==["料飲"])
 var pattern=ShiftPattern(name:"基本",scope:.everyone,locationID:location.id)
 pattern.weekdays=[.day,.day,.day,.day,.day,.off,.off]
 pattern.customStartMinutes=540;pattern.customEndMinutes=1080;pattern.customBreakMinutes=60
 precondition(store.savePatternSafely(pattern,expected:nil))
 var updated=pattern;updated.name="変更";updated.customEndMinutes=1140
 precondition(store.savePatternSafely(updated,expected:pattern))
 precondition(!store.savePatternSafely(pattern,expected:pattern))
 var invalid=updated;invalid.customEndMinutes=500
 precondition(!store.savePatternSafely(invalid,expected:updated))
 let restored=try JSONDecoder().decode(ShiftData.self,from:JSONEncoder().encode(store.data))
 precondition(restored.patterns==[updated] && restored.assignments==[assignment])
 store.selectedLocationID=UUID();precondition(!store.savePatternSafely(updated,expected:updated))
 print("Standard preset defaults, stable IDs, edit/persistence, future assignments and grid edits, existing-shift preservation, invalid/stale/location rejection and JSON roundtrip passed")
 }
}
'''
with tempfile.TemporaryDirectory() as tmp:
 src=Path(tmp)/'Runner.swift';src.write_text(program)
 subprocess.run(['swiftc','-parse-as-library','-module-cache-path',tmp+'/cache',str(root/'HOTEL_SHIFT/Models/ShiftModels.swift'),str(root/'HOTEL_SHIFT/Models/DayTimelineMath.swift'),str(root/'HOTEL_SHIFT/Models/ScheduleGridSupport.swift'),str(src),'-o',tmp+'/test'],check=True)
 subprocess.run([tmp+'/test'],check=True)
