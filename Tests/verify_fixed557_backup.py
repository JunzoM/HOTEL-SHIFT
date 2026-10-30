from pathlib import Path
import subprocess,tempfile,sys
r=Path(__file__).resolve().parents[1]
s=(Path(sys.argv[1]) if len(sys.argv)>1 else r/'HOTEL_SHIFT/Services/ShiftStore.swift').read_text()
a=s.index('    nonisolated private static func isValidBackup(');b=s.index('    func exportBackup()',a)
validator=s[a:b].replace('nonisolated private static func','static func')
program=r'''
import Foundation
final class Store {
VALIDATOR
}
@main struct Runner {
    static func main() {
        var checks=0
        func check(_ condition:Bool,_ label:String) {
            if !condition { print("FAIL: " + label);exit(1) };checks+=1
        }
        let location=HotelLocation(name:"Test")
        let staff=StaffMember(name:"A",department:"Front",employment:"Full",hourlyWage:1500,locationID:location.id)
        let shift=ShiftAssignment(staffID:staff.id,dateKey:"2026-10-01",type:.day,locationID:location.id)
        let request=ShiftRequest(staffID:staff.id,dateKey:"2026-10-02",reason:"leave",locationID:location.id)
        let pattern=ShiftPattern(name:"Work",scope:.everyone,locationID:location.id)
        let base=ShiftData(locations:[location],staff:[staff],assignments:[shift],requests:[request],patterns:[pattern])
        check(Store.isValidBackup(base),"valid base")
        var legacy=base;legacy.staff[0].locationID=nil;legacy.assignments[0].locationID=nil
        check(Store.isValidBackup(legacy),"legacy location migration")
        var leap=base;leap.assignments[0].dateKey="2028-02-29"
        check(Store.isValidBackup(leap),"leap date")
        var overnight=base;overnight.assignments[0].customStartMinutes=1260;overnight.assignments[0].customEndMinutes=1980
        overnight.assignments[0].customBreakMinutes=60;overnight.assignments[0].customBreakStartMinutes=1500
        check(Store.isValidBackup(overnight),"overnight")
        var defaults=base;defaults.patterns=ShiftPattern.basicDefaults(locationID:location.id)
        check(Store.isValidBackup(defaults),"standard preset compatibility")
        var partial=base;partial.assignments[0].customStartMinutes=1200
        check(!Store.isValidBackup(partial),"start exceeds default end")
        partial.assignments[0].customStartMinutes=600
        check(Store.isValidBackup(partial),"valid legacy partial times")
        for extreme in [Int.min,Int.max,-1,2880] {
            for field in 0..<4 {
                var value=base
                switch field {
                case 0:value.assignments[0].customStartMinutes=extreme
                case 1:value.assignments[0].customEndMinutes=extreme
                case 2:value.assignments[0].customBreakMinutes=extreme
                default:value.assignments[0].customBreakStartMinutes=extreme
                }
                check(!Store.isValidBackup(value),"out-of-range assignment field \(field):\(extreme)")
            }
        }
        var backwards=base;backwards.assignments[0].customStartMinutes=600;backwards.assignments[0].customEndMinutes=500
        check(!Store.isValidBackup(backwards),"backwards shift")
        var tooMuchBreak=overnight;tooMuchBreak.assignments[0].customBreakMinutes=800
        check(!Store.isValidBackup(tooMuchBreak),"break exceeds duration")
        var lateBreak=overnight;lateBreak.assignments[0].customBreakStartMinutes=1970
        check(!Store.isValidBackup(lateBreak),"break ends after shift")
        for key in ["2026-02-30","bad","2026-13-01"] {
            var a=base;a.assignments[0].dateKey=key
            check(!Store.isValidBackup(a),"invalid shift date")
            var b=base;b.requests![0].dateKey=key
            check(!Store.isValidBackup(b),"invalid request date")
        }
        var employment=base;employment.staff[0].joinDate="2026-10-02";employment.staff[0].leaveDate="2026-10-01"
        check(!Store.isValidBackup(employment),"backwards employment dates")
        employment.staff[0].leaveDate="2026-10-03"
        check(Store.isValidBackup(employment),"valid employment dates")
        for field in 0..<4 {
            var a=base
            switch field {
            case 0:a.patterns![0].customStartMinutes=Int.max
            case 1:a.patterns![0].customEndMinutes=Int.max
            case 2:a.patterns![0].customBreakMinutes=Int.max
            default:a.patterns![0].customBreakStartMinutes=Int.max
            }
            check(!Store.isValidBackup(a),"extreme pattern field")
        }
        var seasonal=base;seasonal.patterns![0].scope = .seasonal;seasonal.patterns![0].staffID=staff.id
        check(!Store.isValidBackup(seasonal),"seasonal dates missing")
        seasonal.patterns![0].validFrom=Date(timeIntervalSince1970:200000)
        seasonal.patterns![0].validUntil=Date(timeIntervalSince1970:100000)
        check(!Store.isValidBackup(seasonal),"seasonal dates reversed")
        var basic=base;basic.patterns![0].basicShiftType = .off
        check(!Store.isValidBackup(basic),"invalid basic pattern type")
        var dates=base;dates.staff[0].joinDate="2026-02-30"
        check(!Store.isValidBackup(dates),"invalid employment date")
        check(Store.isValidBackup(SampleShiftData.make(anchor:Date.keyFormatter.date(from:"2026-10-28")!)),"existing sample compatibility")
        let restored=try! JSONDecoder().decode(ShiftData.self,from:JSONEncoder().encode(overnight))
        check(Store.isValidBackup(restored),"valid JSON roundtrip")
        print("Backup validation: \(checks) boundary/compatibility checks passed")
    }
}
'''.replace('VALIDATOR',validator)
with tempfile.TemporaryDirectory(prefix='fixed557-backup-') as folder:
    p=Path(folder);(p/'Runner.swift').write_text(program)
    subprocess.run(['swiftc','-parse-as-library',str(r/'HOTEL_SHIFT/Models/ShiftModels.swift'),str(p/'Runner.swift'),'-o',str(p/'test')],check=True)
    subprocess.run([str(p/'test')],check=True)
