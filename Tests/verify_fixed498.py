from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
view=(root/'HOTEL_SHIFT/Views/StaffAndOtherViews.swift').read_text()
store=(root/'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()
rename=view[view.index('    private func renameDepartment()'):view.index('    private func addDepartment()')].replace('private func','func').replace('UserDefaults.standard','defaults')
valid=store[store.index('    private func isValidPattern('):store.index('    var selectedPersonalWorkTimes:')]
methods=store[store.index('    @discardableResult\n    func savePatternSafely('):store.index('    func deletePattern(_')]
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
 let suite="fixed498-test-"+UUID().uuidString
 let prefs=UserDefaults(suiteName:suite)!
 defer {prefs.removePersistentDomain(forName:suite)}
 let location=HotelLocation(name:"Test")
 let person=StaffMember(name:"A",department:"フロント",employment:"正社員",hourlyWage:1200,locationID:location.id)
 let assignment=ShiftAssignment(staffID:person.id,dateKey:"2026-10-28",type:.day,note:"keep",locationID:location.id)
 let store=Store(ShiftData(locations:[location],staff:[person],assignments:[assignment]),location.id)
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
 print("Department rename, persistence, duplicates/blank, assignment preservation, pattern create/edit/validation/stale/location and JSON roundtrip passed")
 }
}
'''
with tempfile.TemporaryDirectory() as tmp:
 src=Path(tmp)/'Runner.swift';src.write_text(program)
 subprocess.run(['swiftc','-parse-as-library','-module-cache-path',tmp+'/cache',str(root/'HOTEL_SHIFT/Models/ShiftModels.swift'),str(src),'-o',tmp+'/test'],check=True)
 subprocess.run([tmp+'/test'],check=True)
