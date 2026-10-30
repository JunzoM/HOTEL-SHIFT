from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
s=(root/'HOTEL_SHIFT/Services/CloudSync.swift').read_text()
a=s.index('    private func sharingPresentation(');b=s.index('    func acceptInvitation()',a)
methods=s[a:b]
program='''import Foundation
typealias CKRecordValue=String
let CKCurrentUserDefaultName="owner"
struct CKError:Error {enum Code{case unknownItem};var code:Code}
enum CloudSyncError:Error {case message(String)}
class CKRecord {
 struct ID:Hashable {var recordName:String;var zoneID:CKRecordZone.ID}
 struct Reference {var recordID:ID}
 let recordID:ID
 var share:Reference?
 var fields=[String:String]()
 init(recordType:String,recordID:ID){self.recordID=recordID}
 subscript(_ key:String)->String? {get{fields[key]}set{fields[key]=newValue}}
}
class CKShare:CKRecord {
 enum Permission{case none};var publicPermission=Permission.none
 enum SystemFieldKey {static let title="title"}
 let root:CKRecord
 init(rootRecord:CKRecord){root=rootRecord;super.init(recordType:"Share",recordID:.init(recordName:"share",zoneID:rootRecord.recordID.zoneID))}
}
class CKRecordZone {
 struct ID:Hashable {var zoneName:String;var ownerName:String}
 let zoneID:ID
 init(zoneID:ID){self.zoneID=zoneID}
}
class CKDatabase {
 var records=[CKRecord.ID:CKRecord]()
 func record(for id:CKRecord.ID) async throws->CKRecord {
  guard let record=records[id] else{throw CKError(code:.unknownItem)};return record
 }
 func save(_ zone:CKRecordZone) async throws->CKRecordZone {zone}
}
class CKContainer {let privateCloudDatabase=CKDatabase()}
struct CloudSyncTarget {
 var zone:String;var owner:String;var root:String;var shared:Bool;var account:String
 var recordID:CKRecord.ID{.init(recordName:root,zoneID:.init(zoneName:zone,ownerName:owner))}
}
struct CloudSharePresentation {let share:CKShare;let container:CKContainer}
class Store {func cloudSnapshot() async->Data? {Data("LOCAL".utf8)}}
@MainActor class Sync {
 var events=[String]()
 var busy=false {didSet{events.append("busy:\\(busy)")}}
 var shareSheet:CloudSharePresentation? {didSet{precondition(!busy);events.append("present")}}
 var store:Store?=Store()
 var container=CKContainer()
 var target:CloudSyncTarget?
 var baselineHash:String?="original",baselineTag:String?="1"
 var enabled=false;var status="";var savedPayloads=[Data]();var failed=false
 func account() async throws->String{if failed{throw CloudSyncError.message("fail")};return "account"}
 func database(_ target:CloudSyncTarget)->CKDatabase{container.privateCloudDatabase}
 func save(_ records:[CKRecord],database:CKDatabase) async throws->Bool {
  for r in records{database.records[r.recordID]=r;if let share=r as? CKShare{share.root.share = .init(recordID:share.recordID)}};return true
 }
 func withAsset(_ bytes:Data,record:CKRecord,database:CKDatabase,share:CKShare?) async throws->CKRecord {
  savedPayloads.append(bytes);_=try await save([record]+(share.map{[$0]} ?? []),database:database);return record
 }
 func success(_ bytes:Data,record:CKRecord) async {}
 func report(_ error:Error){status="error"}
'''+methods+'''}
@main struct Runner {
 @MainActor static func main() async throws {
 let suiteKey="hotelShift.cloud.enabled"
 let previous=UserDefaults.standard.object(forKey:suiteKey)
 defer {if let previous{UserDefaults.standard.set(previous,forKey:suiteKey)}else{UserDefaults.standard.removeObject(forKey:suiteKey)}}
 let zone=CKRecordZone.ID(zoneName:"HotelShiftWorkspace",ownerName:"owner")
 let id=CKRecord.ID(recordName:"workspace",zoneID:zone)
 // Existing workspace and saved share: first tap must open, without publishing local payload.
 let reconnect=Sync(),root=CKRecord(recordType:"Workspace",recordID:id)
 let share=CKShare(rootRecord:root)
 _=try await reconnect.save([root,share],database:reconnect.container.privateCloudDatabase)
 await reconnect.prepareSharing()
 precondition(reconnect.shareSheet != nil && reconnect.target != nil && reconnect.savedPayloads.isEmpty)
 precondition(reconnect.events.suffix(2)==["busy:false","present"])
 let events=reconnect.events;await reconnect.prepareSharing();precondition(events==reconnect.events)
 // Already connected: reuse the saved share in one tap.
 reconnect.shareSheet=nil;await reconnect.prepareSharing();precondition(reconnect.shareSheet != nil)
 // Existing root without a share: create its share, preserving the payload.
 let unshared=Sync(),root2=CKRecord(recordType:"Workspace",recordID:id)
 unshared.container.privateCloudDatabase.records[id]=root2
 await unshared.prepareSharing();precondition(unshared.shareSheet != nil && unshared.savedPayloads.isEmpty)
 // Fresh workspace: publish once, then present the saved share.
 let fresh=Sync();await fresh.prepareSharing()
 precondition(fresh.shareSheet != nil && fresh.savedPayloads==[Data("LOCAL".utf8)])
 // Errors end preparation without presenting or requiring a second dismissal.
 let failed=Sync();failed.failed=true;await failed.prepareSharing()
 precondition(!failed.busy && failed.shareSheet==nil && failed.status=="error")
 print("First-tap reconnect/existing-share/new-share/fresh-workspace paths, payload preservation, presentation after preparation, duplicate-open guard and error cleanup passed")
 }
}
'''
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)/'Runner.swift';p.write_text(program)
 subprocess.run(['swiftc','-parse-as-library','-module-cache-path',tmp+'/cache',str(p),'-o',tmp+'/test'],check=True)
 subprocess.run([tmp+'/test'],check=True)
view=(root/'HOTEL_SHIFT/Views/StaffAndOtherViews.swift').read_text()
assert '.sheet(item: $cloud.shareSheet)' in view
assert '.sheet(item: $sync.shareSheet)' not in s
assert 'shareSheet == nil' in s[s.index('    func synchronize('):a]
print('Stable Settings presenter and background-sync exclusion checked; real CloudKit/iOS sharing UI not exercised')
