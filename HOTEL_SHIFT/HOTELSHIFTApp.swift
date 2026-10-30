import SwiftUI
import UIKit

@MainActor final class ShiftAppBootstrap: ObservableObject {
    @Published private(set) var store: ShiftStore?
    private var loading = false
    private var synchronizationTask: Task<Void, Never>?
    func load() async {
        guard store == nil, !loading else { return }
        loading = true
        let prepared = await Task.detached(priority: .userInitiated) { ShiftStore.prepareInitialLoad() }.value
        store = ShiftStore(prepared: prepared)
        loading = false
    }
    // App-owned loop: reopening a window must not start another polling task.
    func startSynchronization() {
        guard synchronizationTask == nil, let store else { return }
        store.cloudSync.receivePendingInvitation()
        synchronizationTask = Task { @MainActor in
            while !Task.isCancelled {
                if UIApplication.shared.applicationState == .active {
                    await store.cloudSync.synchronize()
                }
                do { try await Task.sleep(for: .seconds(30)) }
                catch { break }
            }
        }
    }
}

@main
struct HOTELSHIFTApp: App {
    @UIApplicationDelegateAdaptor(CloudAppDelegate.self) private var appDelegate
    @StateObject private var bootstrap = ShiftAppBootstrap()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if let store = bootstrap.store {
            Group {
                #if targetEnvironment(macCatalyst)
                MacWorkspaceContainer { ContentView() }
                #else
                ContentView()
                #endif
            }
                .environmentObject(store)
                .environmentObject(store.cloudSync)
                .task { bootstrap.startSynchronization() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    store.flushPendingSave()
                }
                .onReceive(NotificationCenter.default.publisher(for: CloudInvitationInbox.notification)) { _ in store.cloudSync.receivePendingInvitation() }
                .alert("HOTEL SHIFTの共有に参加", isPresented: Binding(get: { store.cloudSync.invitation != nil }, set: { if !$0 { store.cloudSync.invitation = nil } })) {
                    Button("参加してデータを確認") { Task { await store.cloudSync.acceptInvitation() } }
                    Button("キャンセル", role: .cancel) { store.cloudSync.invitation = nil }
                } message: { Text("共有される全店舗のスタッフ・シフト・希望休を扱います。端末のデータと違う場合は、設定で使用するデータを選びます。") }
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, phase in
                    #if targetEnvironment(macCatalyst)
                    if phase != .active { store.flushPendingSave() }
                    #else
                    if phase == .background { store.flushPendingSave() }
                    #endif
                    if phase == .active { Task { await store.cloudSync.synchronize() } }
                }
            } else {
                ProgressView("データを読み込み中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { await bootstrap.load() }
            }
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1280, height: 800)
        .commands {
            ShiftMacCommands()
            MacDisplayCommands()
            CommandGroup(replacing: .appSettings) {
                Button("設定…") {
                    NotificationCenter.default.post(name: .hotelShiftOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(bootstrap.store == nil)
            }
        }
        #endif
    }
}
