from pathlib import Path
import subprocess,tempfile,sys
r=Path(__file__).resolve().parents[1]
s=(Path(sys.argv[1]) if len(sys.argv)>1 else r/'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()
a=s.index('    func exportCSV()');b=s.index('    // Use date buckets',a)
method=s[a:b]
a=s.index('    nonisolated private static func csvEscape(');b=s.index('    func addStaff(',a)
escape=s[a:b]
program=r'''
import Foundation
@MainActor final class Store {
    var data:ShiftData
    var storageWriteBlocked=false
    var selectedAssignments:[ShiftAssignment] { data.assignments }
    init(_ data:ShiftData){self.data=data}
METHOD
ESCAPE
}
@main struct Runner {
    @MainActor static func main() async throws {
        let location=HotelLocation(name:"Test")
        let staff=StaffMember(name:"A",department:"Front",employment:"Full",hourlyWage:1500,locationID:location.id)
        var rows=(1...3).map { day in ShiftAssignment(staffID:staff.id,dateKey:String(format:"2026-10-%02d",day),type:.day,locationID:location.id) }
        rows[0].hourlyWageSnapshot=1100
        rows[0].type = .night;rows[0].customStartMinutes=1320;rows[0].customEndMinutes=1800
        rows[2].customEndMinutes=1440
        rows[2].hourlyWageSnapshot=0;rows[2].note="A,\"B\"\nC"
        let store=Store(ShiftData(locations:[location],staff:[staff],assignments:rows))
        guard let url=await store.exportCSV() else { print("FAIL: CSV export failed");exit(1) }
        defer { try? FileManager.default.removeItem(at:url) }
        let text=try String(contentsOf:url,encoding:.utf8)
        let lines=text.components(separatedBy:"\r\n")
        for (i,wage) in [1100,1500,0].enumerated() {
            let actual=lines[i+1].components(separatedBy:",")[8]
            if actual != "\"\(wage)\"" { print("FAIL: historical/legacy/zero wage CSV mismatch");exit(1) }
        }
        let end=lines[1].components(separatedBy:",")[7]
        if end != "\"翌06:00\"" { print("FAIL: next-day CSV end time lost");exit(1) }
        precondition(lines[3].components(separatedBy:",")[7] == "\"翌00:00\"")
        precondition(text.contains("\"A,\"\"B\"\"\nC\""))
        store.storageWriteBlocked=true
        let blocked=await store.exportCSV();precondition(blocked==nil)
        print("CSV: historical, legacy fallback, zero wage, overnight/midnight end times, escaping and protected-storage checks passed")
    }
}
'''.replace('METHOD',method).replace('ESCAPE',escape)
with tempfile.TemporaryDirectory(prefix='fixed557-csv-') as folder:
    p=Path(folder);(p/'Runner.swift').write_text(program)
    subprocess.run(['swiftc','-parse-as-library',str(r/'HOTEL_SHIFT/Models/ShiftModels.swift'),str(p/'Runner.swift'),'-o',str(p/'test')],check=True)
    subprocess.run([str(p/'test')],check=True)
