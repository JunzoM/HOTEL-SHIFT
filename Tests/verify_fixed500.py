from pathlib import Path
import subprocess,tempfile,plistlib
root=Path(__file__).resolve().parents[1]
s=(root/'HOTEL_SHIFT/Services/CloudSync.swift').read_text()
a=s.index('enum CloudSyncDecision:');b=s.index('struct CloudSyncTarget:')
program='import Foundation\n'+s[a:b]+'''
precondition(CloudSyncDecision.choose(local:"A",remote:"A",baseline:nil,tag:"1",baselineTag:nil) == .equal)
precondition(CloudSyncDecision.choose(local:"A",remote:"B",baseline:nil,tag:"1",baselineTag:nil) == .conflict)
precondition(CloudSyncDecision.choose(local:"A",remote:"B",baseline:"A",tag:"2",baselineTag:"1") == .pull)
precondition(CloudSyncDecision.choose(local:"B",remote:"A",baseline:"A",tag:"1",baselineTag:"1") == .push)
precondition(CloudSyncDecision.choose(local:"B",remote:"C",baseline:"A",tag:"2",baselineTag:"1") == .conflict)
precondition(CloudSyncDecision.choose(local:"B",remote:"A",baseline:"A",tag:nil,baselineTag:nil) == .conflict)
print("Initial divergence, equal snapshots, remote-only/local-only updates, concurrent edits and missing revision guards passed")
'''
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)/'main.swift';p.write_text(program)
 subprocess.run(['swiftc','-module-cache-path',tmp+'/cache',str(p),'-o',tmp+'/test'],check=True)
 subprocess.run([tmp+'/test'],check=True)
ent=plistlib.loads((root/'HOTEL_SHIFT/HOTEL_SHIFT.entitlements').read_bytes())
assert ent['com.apple.developer.icloud-container-identifiers']==['iCloud.jp.hotelshift.app']
assert 'CloudKit' in ent['com.apple.developer.icloud-services']
assert plistlib.loads((root/'HOTEL_SHIFT/RequestInfo.plist').read_bytes())['CKSharingSupported']
assert 'savePolicy: .ifServerRecordUnchanged' in s and 'atomically: true' in s
assert 'store.pdfRevision == capturedRevision' in s
assert 'conflict.serverTag == server.recordChangeTag' in s
assert 'share.publicPermission = .none' in s
assert 'target.account' in s and 'container.sharedCloudDatabase' in s
print('Capabilities, invitation setup, atomic conditional saves, latest-local/revision/account guards and private invitations checked')
