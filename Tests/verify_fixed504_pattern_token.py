from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
s=(root/'HOTEL_SHIFT/Views/ShiftCalendarView.swift').read_text()
a=s.index('    private func snapshot() -> Data?');b=s.index('    // FIXED265:',a)
method=s[a:b].replace('private func snapshot','func snapshot')
program='''import Foundation
final class Store {var selectedLocationID=UUID();var selectedPatterns:[ShiftPattern]=[];var pdfRevision:UInt64=0}
struct Screen {
 let store:Store;var pattern:ShiftPattern
 var from=Date(timeIntervalSince1970:1000),until=Date(timeIntervalSince1970:2000)
 var validRange=true
'''+method+'''}
@main struct Runner {
 static func main() {
  let store=Store();let pattern=ShiftPattern(name:"test",scope:.everyone,locationID:store.selectedLocationID)
  store.selectedPatterns=[pattern]
  var screen=Screen(store:store,pattern:pattern)
  let initial=screen.snapshot()!;precondition(initial.count<256 && initial==screen.snapshot())
  store.pdfRevision+=1;precondition(screen.snapshot() != initial)
  let next=screen.snapshot();screen.from=Date(timeIntervalSince1970:1100);precondition(screen.snapshot() != next)
  screen.validRange=false;precondition(screen.snapshot()==nil)
  screen.validRange=true;store.selectedLocationID=UUID();precondition(screen.snapshot()==nil)
  store.selectedLocationID=pattern.locationID;store.selectedPatterns=[];precondition(screen.snapshot()==nil)
  print("Actual pattern confirmation: compact token, every data revision invalidates, range/selection/deleted-pattern protection preserved; no whole-photo JSON encoding")
 }
}
'''
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)/'Runner.swift';p.write_text(program)
 subprocess.run(['swiftc','-parse-as-library','-module-cache-path',tmp+'/cache',str(root/'HOTEL_SHIFT/Models/ShiftModels.swift'),str(p),'-o',tmp+'/test'],check=True)
 subprocess.run([tmp+'/test'],check=True)
