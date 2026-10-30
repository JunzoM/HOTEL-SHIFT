from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
s=(root/'HOTEL_SHIFT/Services/CloudSync.swift').read_text()
a=s.index('enum CloudSyncDecision:');b=s.index('struct CloudSyncTarget:')
policy=s[a:b]+s[s.index("struct CloudSyncConflict:"):s.index("struct CloudSharePresentation:")]
a=s.index('    private func stageConflict(');b=s.index('    private func sharingPresentation(',a)
methods=s[a:b].replace('private func stageConflict','func stageConflict')
program='''import Foundation
'''+policy+'''
struct CKRecord {
 var recordChangeTag:String?
 var modificationDate:Date?=Date(timeIntervalSince1970:1)
 var bytes:Data
}
class Database {
 var record=CKRecord(recordChangeTag:"1",bytes:Data("A".utf8))
 var metadataReads=0,fullReads=0
 var uploaded=[Data]()
 func records(for ids:[String],desiredKeys:[String]) async throws->[String:Result<CKRecord,Error>] {
  precondition(!desiredKeys.contains("payload"));metadataReads+=1;return [ids[0]:.success(record)]
 }
 func record(for id:String) async throws->CKRecord {fullReads+=1;return record}
}
struct Target {let account="account";let recordID="root"}
enum CloudSyncError:Error {case message(String)}
@MainActor class Store {
 var cloudImportInProgress=false
 var pdfRevision:UInt64=1
 var bytes=Data("A".utf8)
 var mutateOnSnapshot=false,mutateOnArchive=false
 var installs=0
 func cloudSnapshot() async->Data? {
  let captured=bytes
  if mutateOnSnapshot {pdfRevision+=1;bytes=Data("M".utf8);mutateOnSnapshot=false}
  return captured
 }
 func installCloudSnapshot(_ data:Data,preservingConflict:Bool=false) async->Bool {bytes=data;pdfRevision+=1;installs+=1;return true}
 func archiveCloudSnapshot(_ data:Data) async throws {
  if mutateOnArchive {pdfRevision+=1;bytes=Data("new local edit".utf8)}
 }
}
@MainActor class Sync {
 var enabled=true,busy=false
 var shareSheet:Int?
 var store:Store?=Store()
 var target:Target?=Target()
 var status=""
 var baselineHash:String?=Data("A".utf8).base64EncodedString()
 var baselineTag:String?="1"
 var conflict:CloudSyncConflict?
 var fingerprint:(revision:UInt64,value:String)?
 let db=Database()
 func account() async throws->String {"account"}
 func database(_ target:Target)->Database{db}
 func hash(_ data:Data) async->String{data.base64EncodedString()}
 func localHash(_ bytes:Data,revision:UInt64) async->String {
  if let fingerprint,fingerprint.revision==revision{return fingerprint.value}
  let value=await hash(bytes);fingerprint=(revision,value);return value
 }
 func payload(_ record:CKRecord) async throws->Data{record.bytes}
 func withAsset(_ bytes:Data,record:CKRecord,database:Database) async throws->CKRecord {
  database.uploaded.append(bytes);database.record=CKRecord(recordChangeTag:"saved",bytes:bytes);return database.record
 }
 func success(_ bytes:Data,record:CKRecord,digest:String?=nil) async {
  if let digest{baselineHash=digest}else{baselineHash=await hash(bytes)}
  baselineTag=record.recordChangeTag;conflict=nil;status="success"
 }
 func report(_ error:Error){status="error"}
'''+methods+'''}
@main struct Runner {
 @MainActor static func main() async throws {
  let idle=Sync();await idle.synchronize()
  precondition(idle.db.metadataReads==1 && idle.db.fullReads==0 && idle.db.uploaded.isEmpty)
  // Reproduce an edit between awaiting a snapshot and resuming the caller.
  let resumed=Sync();resumed.store!.mutateOnSnapshot=true
  await resumed.synchronize()
  precondition(resumed.db.metadataReads==0 && resumed.fingerprint==nil && !resumed.busy)
  await resumed.synchronize()
  precondition(resumed.db.uploaded==[Data("M".utf8)] && resumed.baselineHash==Data("M".utf8).base64EncodedString())
  // Both sides changed: retain confirmation identity on unchanged polling.
  let conflict=Sync();conflict.store!.bytes=Data("L".utf8)
  conflict.db.record=CKRecord(recordChangeTag:"2",bytes:Data("R".utf8))
  await conflict.synchronize();let firstID=conflict.conflict!.id
  await conflict.synchronize();precondition(conflict.conflict!.id==firstID)
  await conflict.synchronize(preferCloud:true,expectedConflictID:UUID())
  precondition(conflict.store!.installs==0)
  await conflict.synchronize(preferCloud:true,expectedConflictID:firstID)
  precondition(conflict.store!.installs==1 && conflict.store!.bytes==Data("R".utf8))
  // A local edit during preservation prevents sending the obsolete selected snapshot.
  let archived=Sync();archived.store!.bytes=Data("L".utf8)
  archived.db.record=CKRecord(recordChangeTag:"2",bytes:Data("R".utf8))
  await archived.synchronize();let id=archived.conflict!.id
  archived.store!.mutateOnArchive=true
  await archived.synchronize(preferCloud:false,expectedConflictID:id)
  precondition(archived.db.uploaded.isEmpty)
  let closed=Sync();closed.shareSheet=1;await closed.synchronize();precondition(closed.db.metadataReads==0)
  print("Actual sync flow: metadata-only idle, snapshot-resume race, correct next upload, stable conflict identity, stale confirmation rejection, remote install, edit-during-archive protection and modal exclusion passed")
 }
}
'''
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)/'Runner.swift';p.write_text(program)
 subprocess.run(['swiftc','-parse-as-library','-module-cache-path',tmp+'/cache',str(p),'-o',tmp+'/test'],check=True)
 subprocess.run([tmp+'/test'],check=True)
