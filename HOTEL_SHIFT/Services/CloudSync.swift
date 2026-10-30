import SwiftUI
import CloudKit
import CryptoKit
import UIKit

// A local edit and a remote edit must never be resolved by clock order.
enum CloudSyncDecision: Equatable {
    case equal, pull, push, conflict
    static func choose(local: String, remote: String, baseline: String?, tag: String?, baselineTag: String?) -> CloudSyncDecision {
        if local == remote { return .equal }
        if baseline == local { return .pull }
        if baseline != nil && baselineTag != nil && baselineTag == tag { return .push }
        return .conflict
    }
}
struct CloudSyncTarget: Codable {
    var zone: String
    var owner: String
    var root: String
    var shared: Bool
    var account: String
    var recordID: CKRecord.ID { CKRecord.ID(recordName: root, zoneID: CKRecordZone.ID(zoneName: zone, ownerName: owner)) }
}
struct CloudSyncConflict: Identifiable {
    let id = UUID()
    let localHash: String
    let serverTag: String?
    let modified: Date?
}
struct CloudSharePresentation: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}
@MainActor final class CloudSync: ObservableObject {
    static let containerID = "iCloud.jp.hotelshift.app"
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "hotelShift.cloud.enabled")
    @Published private(set) var status = "iCloud共有は未接続です"
    @Published private(set) var busy = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var conflict: CloudSyncConflict?
    @Published var shareSheet: CloudSharePresentation?
    @Published var invitation: CKShare.Metadata?
    private weak var store: ShiftStore?
    private lazy var container = CKContainer(identifier: CloudSync.containerID)
    private var pending: Task<Void, Never>?
    private var fingerprint: (revision: UInt64, value: String)?
    private var target: CloudSyncTarget? {
        didSet {
            if let target, let bytes = try? JSONEncoder().encode(target) { UserDefaults.standard.set(bytes, forKey: "hotelShift.cloud.target") }
            else { UserDefaults.standard.removeObject(forKey: "hotelShift.cloud.target") }
        }
    }
    private var baselineHash: String? {
        get { UserDefaults.standard.string(forKey: "hotelShift.cloud.hash") }
        set { UserDefaults.standard.set(newValue, forKey: "hotelShift.cloud.hash") }
    }
    private var baselineTag: String? {
        get { UserDefaults.standard.string(forKey: "hotelShift.cloud.tag") }
        set { UserDefaults.standard.set(newValue, forKey: "hotelShift.cloud.tag") }
    }
    init() {
        if let bytes = UserDefaults.standard.data(forKey: "hotelShift.cloud.target") { target = try? JSONDecoder().decode(CloudSyncTarget.self, from: bytes) }
        if enabled { status = "iCloudへの接続を確認します" }
    }
    func attach(_ store: ShiftStore) { self.store = store }
    func localSaved() {
        guard enabled, conflict == nil else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.synchronize()
        }
    }
    func pause() {
        enabled = false; UserDefaults.standard.set(false, forKey: "hotelShift.cloud.enabled")
        pending?.cancel(); status = "同期を停止中です。端末のデータは保持しています"
    }
    func resume() async {
        enabled = true; UserDefaults.standard.set(true, forKey: "hotelShift.cloud.enabled")
        await synchronize()
    }
    private func account() async throws -> String {
        guard try await container.accountStatus() == .available else { throw CloudSyncError.message("iPadの設定でiCloudにサインインしてください。iCloudを利用できません。") }
        return try await container.userRecordID().recordName
    }
    private func database(_ target: CloudSyncTarget) -> CKDatabase { target.shared ? container.sharedCloudDatabase : container.privateCloudDatabase }
    private func hash(_ bytes: Data) async -> String {
        await Task.detached(priority: .utility) {
            SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }.value
    }
    private func localHash(_ bytes: Data, revision: UInt64) async -> String {
        if let fingerprint, fingerprint.revision == revision { return fingerprint.value }
        let value = await hash(bytes)
        fingerprint = (revision, value)
        return value
    }
    private func payload(_ record: CKRecord) async throws -> Data {
        guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL else { throw CloudSyncError.message("共有データを読み込めませんでした。") }
        return try await Task.detached(priority: .utility) {
            let bytes = try Data(contentsOf: url)
            guard ShiftStore.validCloudSnapshot(bytes) else { throw CloudSyncError.message("共有データの形式を確認できません。端末のデータは変更していません。") }
            return bytes
        }.value
    }
    private func save(_ records: [CKRecord], database: CKDatabase) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        for value in result.saveResults.values { _ = try value.get() }
        return result.saveResults
    }
    private func withAsset(_ bytes: Data, record: CKRecord, database: CKDatabase, share: CKShare? = nil) async throws -> CKRecord {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-\(UUID().uuidString).json")
        try await Task.detached(priority: .utility) { try bytes.write(to: url, options: .atomic) }.value
        defer { try? FileManager.default.removeItem(at: url) }
        record["payload"] = CKAsset(fileURL: url)
        record["formatVersion"] = 1 as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        let results = try await save([record] + (share.map { [$0] } ?? []), database: database)
        guard let value = results[record.recordID] else { throw CloudSyncError.message("iCloudへの保存結果を確認できません。") }
        return try value.get()
    }
    private func success(_ bytes: Data, record: CKRecord, digest: String? = nil) async {
        if let digest { baselineHash = digest } else { baselineHash = await hash(bytes) }
        baselineTag = record.recordChangeTag
        lastSync = Date(); conflict = nil; status = "iCloudと同期済み"
    }
    private func stageConflict(localHash: String, record: CKRecord) {
        if let conflict, conflict.localHash == localHash, conflict.serverTag == record.recordChangeTag { return }
        conflict = CloudSyncConflict(localHash: localHash, serverTag: record.recordChangeTag, modified: record.modificationDate)
    }
    func synchronize(preferCloud: Bool? = nil, expectedConflictID: UUID? = nil) async {
        guard enabled, !busy, shareSheet == nil, let store, !store.cloudImportInProgress else { return }
        guard let target else { status = "共有を作成するか、管理者の招待リンクから参加してください"; return }
        busy = true; defer { busy = false }
        do {
            guard try await account() == target.account else { throw CloudSyncError.message("Apple Accountが変更されています。同期を停止し、使用する共有に招待リンクから接続し直してください。") }
            let capturedRevision = store.pdfRevision
            guard let local = await store.cloudSnapshot() else { throw CloudSyncError.message("端末の保存エラーを解消してから同期してください。") }
            guard store.pdfRevision == capturedRevision else { status = "編集中です。次回の同期で再確認します"; return }
            let localHash = await localHash(local, revision: capturedRevision)
            let db = database(target)
            let result = try await db.records(for: [target.recordID], desiredKeys: ["formatVersion", "updatedAt"])
            guard let metadataResult = result[target.recordID] else { throw CloudSyncError.message("同期先の状態を取得できません。") }
            let metadata = try metadataResult.get()
            guard store.pdfRevision == capturedRevision else { status = "編集中です。次回の同期で再確認します"; return }
            // Unchanged server revisions need no asset download, JSON decode or photo processing.
            if let tag = baselineTag, metadata.recordChangeTag == tag, let baselineHash {
                if localHash == baselineHash { await success(local, record: metadata, digest: localHash); return }
                let saved = try await withAsset(local, record: metadata, database: db)
                await success(local, record: saved, digest: localHash)
                return
            }
            let server = try await db.record(for: target.recordID)
            let remote = try await payload(server)
            let remoteHash = await hash(remote)
            guard store.pdfRevision == capturedRevision else { status = "編集中です。次回の同期で再確認します"; return }
            let decision = CloudSyncDecision.choose(local: localHash, remote: remoteHash, baseline: baselineHash, tag: server.recordChangeTag, baselineTag: baselineTag)
            if decision == .equal { await success(local, record: server, digest: localHash); return }
            if let preferCloud {
                guard let conflict, conflict.id == expectedConflictID, conflict.localHash == localHash, conflict.serverTag == server.recordChangeTag else {
                    stageConflict(localHash: localHash, record: server)
                    status = "データが再更新されました。内容をもう一度確認してください"; return
                }
                if preferCloud {
                    guard await store.installCloudSnapshot(remote, preservingConflict: true) else { throw CloudSyncError.message("共有データを端末へ保存できませんでした。") }
                    await success(remote, record: server, digest: remoteHash)
                } else {
                    try await store.archiveCloudSnapshot(remote)
                    guard store.pdfRevision == capturedRevision else { status = "端末が更新されました。内容を再確認してください"; return }
                    let saved = try await withAsset(local, record: server, database: db)
                    await success(local, record: saved, digest: localHash)
                }
            } else if decision == .pull {
                guard await store.installCloudSnapshot(remote) else { throw CloudSyncError.message("共有データを端末へ保存できませんでした。") }
                await success(remote, record: server, digest: remoteHash)
            } else if decision == .push {
                let saved = try await withAsset(local, record: server, database: db)
                await success(local, record: saved, digest: localHash)
            } else {
                stageConflict(localHash: localHash, record: server)
                status = "端末と共有データに違いがあります。設定から確認してください"
            }
        } catch { report(error) }
    }
    private func sharingPresentation(record: CKRecord, database: CKDatabase, canCreate: Bool) async throws -> CloudSharePresentation {
        if let id = record.share?.recordID {
            guard let share = try await database.record(for: id) as? CKShare else { throw CloudSyncError.message("招待情報を取得できませんでした。") }
            return CloudSharePresentation(share: share, container: container)
        }
        guard canCreate else { throw CloudSyncError.message("共有の管理は作成者に依頼してください。") }
        let share = CKShare(rootRecord: record)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = "HOTEL SHIFT 全店舗" as CKRecordValue
        _ = try await save([record, share], database: database)
        guard let savedShare = try await database.record(for: share.recordID) as? CKShare else { throw CloudSyncError.message("招待情報を取得できませんでした。") }
        return CloudSharePresentation(share: savedShare, container: container)
    }
    func prepareSharing() async {
        guard !busy, shareSheet == nil, let store else { return }
        busy = true
        var readyPresentation: CloudSharePresentation?
        defer {
            // Finish preparation before asking SwiftUI to present the controller.
            busy = false
            if let readyPresentation { shareSheet = readyPresentation }
        }
        do {
            let user = try await account()
            if let target {
                guard target.account == user else { throw CloudSyncError.message("Apple Accountが違います。同期先を確認してください。") }
                let db = database(target)
                let record = try await db.record(for: target.recordID)
                readyPresentation = try await sharingPresentation(record: record, database: db, canCreate: !target.shared)
            } else {
                guard let bytes = await store.cloudSnapshot() else { throw CloudSyncError.message("端末データを保存できません。保存状態を確認してください。") }
                let zoneID = CKRecordZone.ID(zoneName: "HotelShiftWorkspace", ownerName: CKCurrentUserDefaultName)
                let db = container.privateCloudDatabase
                _ = try await db.save(CKRecordZone(zoneID: zoneID))
                let id = CKRecord.ID(recordName: "workspace", zoneID: zoneID)
                var existing: CKRecord?
                do { existing = try await db.record(for: id) }
                catch let error as CKError where error.code == .unknownItem { }
                if let existing {
                    // Reconnect and open the existing share in the same tap, preserving its payload.
                    target = CloudSyncTarget(zone: zoneID.zoneName, owner: zoneID.ownerName, root: id.recordName, shared: false, account: user)
                    baselineHash = nil; baselineTag = nil
                    enabled = true; UserDefaults.standard.set(true, forKey: "hotelShift.cloud.enabled")
                    status = "既存の共有に接続しました。データの違いは同期時に確認します"
                    readyPresentation = try await sharingPresentation(record: existing, database: db, canCreate: true)
                } else {
                    let record = CKRecord(recordType: "HotelShiftWorkspace", recordID: id)
                    let share = CKShare(rootRecord: record)
                    share.publicPermission = .none
                    share[CKShare.SystemFieldKey.title] = "HOTEL SHIFT 全店舗" as CKRecordValue
                    let saved = try await withAsset(bytes, record: record, database: db, share: share)
                    target = CloudSyncTarget(zone: zoneID.zoneName, owner: zoneID.ownerName, root: id.recordName, shared: false, account: user)
                    enabled = true; UserDefaults.standard.set(true, forKey: "hotelShift.cloud.enabled")
                    await success(bytes, record: saved)
                    guard let savedShare = try await db.record(for: share.recordID) as? CKShare else { throw CloudSyncError.message("招待情報を取得できませんでした。") }
                    readyPresentation = CloudSharePresentation(share: savedShare, container: container)
                }
            }
        } catch { report(error) }
    }
    func acceptInvitation() async {
        guard !busy, let metadata = invitation else { return }
        busy = true
        do {
            guard metadata.containerIdentifier == Self.containerID else { throw CloudSyncError.message("このアプリの招待リンクではありません。") }
            let user = try await account()
            let oldTarget = target
            _ = try await container.accept(metadata)
            guard let id = metadata.hierarchicalRootRecordID else { throw CloudSyncError.message("共有の参照先を確認できません。招待リンクを作成し直してください。") }
            if oldTarget?.recordID != id { baselineHash = nil; baselineTag = nil }
            target = CloudSyncTarget(zone: id.zoneID.zoneName, owner: id.zoneID.ownerName, root: id.recordName, shared: metadata.participantRole != .owner, account: user)
            enabled = true; UserDefaults.standard.set(true, forKey: "hotelShift.cloud.enabled")
            invitation = nil
            status = "招待を受け付けました。端末データとの違いを確認します"
            busy = false
            await synchronize()
        } catch { busy = false; report(error) }
    }
    func receivePendingInvitation() {
        if let metadata = CloudInvitationInbox.shared.pending {
            invitation = metadata; CloudInvitationInbox.shared.pending = nil
        }
    }
    func report(_ error: Error) {
        status = "同期できません：\(error.localizedDescription)"
        if let error = error as? CKError, error.code == .serverRecordChanged { status = "他の端末が更新しました。「今すぐ同期」で再確認してください" }
    }
}
enum CloudSyncError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
@MainActor final class CloudInvitationInbox {
    static let shared = CloudInvitationInbox()
    static let notification = Notification.Name("HotelShiftCloudInvitation")
    var pending: CKShare.Metadata?
    func enqueue(_ metadata: CKShare.Metadata) { pending = metadata; NotificationCenter.default.post(name: Self.notification, object: nil) }
}
final class CloudSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in CloudInvitationInbox.shared.enqueue(metadata) }
    }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata { Task { @MainActor in CloudInvitationInbox.shared.enqueue(metadata) } }
    }
}
final class CloudAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = CloudSceneDelegate.self
        return configuration
    }
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in CloudInvitationInbox.shared.enqueue(metadata) }
    }
}
struct CloudSharingView: UIViewControllerRepresentable {
    let presentation: CloudSharePresentation
    @ObservedObject var sync: CloudSync
    func makeCoordinator() -> Coordinator { Coordinator(sync) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: presentation.share, container: presentation.container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) { }
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let sync: CloudSync
        init(_ sync: CloudSync) { self.sync = sync }
        func itemTitle(for csc: UICloudSharingController) -> String? { "HOTEL SHIFT 全店舗" }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) { Task { @MainActor in sync.report(error) } }
    }
}
struct CloudSyncSettings: View {
    @EnvironmentObject private var sync: CloudSync
    @State private var resolution: Bool?
    @State private var resolutionConflictID: UUID?
    var body: some View {
        Section {
            Toggle("iCloud同期", isOn: Binding(
                get: { sync.enabled },
                set: { enabled in
                    if enabled { Task { await sync.resume() } }
                    else { sync.pause() }
                }
            )).disabled(sync.busy)
            Label(sync.status, systemImage: sync.enabled ? "icloud" : "icloud.slash").foregroundStyle(sync.conflict == nil ? Color.primary : Color.orange)
            if let date = sync.lastSync { LabeledContent("最終同期", value: date.formatted(date: .abbreviated, time: .shortened)) }
            Text("招待したApple Account間で全店舗のスタッフ・シフト・希望休・パターンを共有します。参加者は共有データを編集できます。ホーム写真・ロゴ・部署候補など端末の設定は共有しません。")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("共有を作成・招待／参加者管理") { Task { await sync.prepareSharing() } }
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 12)
                Button { Task { await sync.prepareSharing() } } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 36, height: 36)
                        .background(Color.blue, in: Circle())
                }.accessibilityLabel("共有の作成・スタッフを招待")
            }.buttonStyle(.borderless).disabled(!sync.enabled || sync.busy)
            HStack {
                Button { Task { await sync.synchronize() } } label: {
                    Label("今すぐ同期", systemImage: "arrow.triangle.2.circlepath")
                }
                Spacer()
                if sync.busy { ProgressView() }
            }.buttonStyle(.borderless).disabled(!sync.enabled || sync.busy)
            if sync.enabled, let conflict = sync.conflict {
                if let date = conflict.modified { LabeledContent("共有データの更新", value: date.formatted(date: .abbreviated, time: .shortened)) }
                Text("端末とiCloudの両方に変更があります。選ばれなかったデータは端末内の復元用ファイルに保管します。自動結合は行いません。")
                    .font(.caption).foregroundStyle(.orange)
                HStack {
                    Button("iCloudのデータを使う") { resolutionConflictID = conflict.id; resolution = true }
                    Button("この端末のデータを共有する") { resolutionConflictID = conflict.id; resolution = false }
                }.buttonStyle(.borderless).disabled(sync.busy)
            }
        } header: {
            #if targetEnvironment(macCatalyst)
            Label("iCloud同期・スタッフと共有", systemImage: "icloud")
            #else
            Text("iCloud同期・スタッフと共有")
            #endif
        }

        .confirmationDialog("共有データの変更を確認", isPresented: Binding(get: { resolution != nil }, set: { if !$0 { resolution = nil } }), titleVisibility: .visible) {
            Button(resolution == true ? "iCloudのデータで端末を更新" : "端末のデータで共有全体を更新", role: .destructive) {
                let choice = resolution, expected = resolutionConflictID; resolution = nil
                Task { await sync.synchronize(preferCloud: choice, expectedConflictID: expected) }
            }
            Button("キャンセル", role: .cancel) { resolution = nil }
        } message: { Text("店舗・スタッフ・シフト・希望休を一式更新します。参加している他の端末にも反映されます。") }
    }
}
