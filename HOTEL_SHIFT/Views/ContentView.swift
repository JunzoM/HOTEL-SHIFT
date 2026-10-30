import SwiftUI
import UIKit
import CryptoKit

// Bounded decoded-image cache for the sidebar logo and dashboard hero.
// Avoids repeated Base64 conversion and UIKit image decoding on SwiftUI redraws.
private enum HotelHeaderImageCache {
    private static var recent: [(encoded: String, image: UIImage)] = []
    static func image(from base64: String) -> UIImage? {
        guard !base64.isEmpty else { return nil }
        if let cached = recent.first(where: { $0.encoded == base64 }) { return cached.image }
        guard let data = Data(base64Encoded: base64), let image = ShiftPhotoProcessing.thumbnail(data, maxPixels: 1600) else { return nil }
        recent.append((base64, image))
        if recent.count > 2 { recent.removeFirst() }
        return image
    }
}

extension Notification.Name {
    static let hotelShiftOpenSettings = Notification.Name("hotelShift.openSettings")
}

enum AppPage: String, CaseIterable, Identifiable {
    case home = "ホーム", shifts = "シフト", requests = "希望休・申請", staff = "スタッフ", labor = "人件費", output = "印刷・出力", backup = "バックアップ・復元", locations = "店舗管理", settings = "設定"
    var id: String { rawValue }
    var icon: String {
        switch self { case .home: return "square.grid.2x2.fill"; case .shifts: return "calendar"; case .requests: return "checkmark.square"; case .staff: return "person.2.fill"; case .labor: return "yensign.circle"; case .output: return "printer.fill"; case .backup: return "externaldrive.fill"; case .locations: return "building.2.crop.circle"; case .settings: return "gearshape.fill" }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: ShiftStore
    @State private var page: AppPage = .home
    @State private var requestedShiftDay: Date?
    @State private var phoneMoreLanding = false
    private enum PhoneTab: Hashable { case home, shifts, staff, output, more }
    @State private var showNewLocation = false
    @State private var newLocationName = ""
    @AppStorage("hotelShift.hotelName") private var hotelName = "ホテル名を設定"
    @AppStorage("hotelShift.logoImageBase64") private var logoImageBase64 = ""
    private let navy = Color(red: 0.055, green: 0.15, blue: 0.25)

    @State private var incomingLinkError: String?
    @State private var iPadLandscape: Bool?
    @State private var sidebarCollapsed: Bool = {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }()

    var body: some View {
        GeometryReader { geometry in
        let appearance = WorkspaceAppearance.forWindow(width: geometry.size.width, height: geometry.size.height,
                                                        isPad: UIDevice.current.userInterfaceIdiom == .pad)
        let compact = UIDevice.current.userInterfaceIdiom == .phone
        let showsHeaderDetails = !compact && geometry.size.width - (sidebarCollapsed ? 56 : 238) > 650
        HStack(spacing: 0) {
            if !compact {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: sidebarCollapsed ? 0 : 10) {
                    Group {
                        if let image = HotelHeaderImageCache.image(from: logoImageBase64) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "building.2.crop.circle.fill").resizable().scaledToFit().padding(3)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    if !sidebarCollapsed {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("HOTEL SHIFT").font(.hotelReadable(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text(hotelName.isEmpty ? "シフト管理" : hotelName).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, sidebarCollapsed ? 11 : 18)
                .padding(.top, 22).padding(.bottom, 14)

                ForEach(AppPage.allCases) { item in
                    Button {
                        page = item
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon).font(.hotelReadable(size: 17, weight: .medium)).frame(width: 22)
                            if !sidebarCollapsed {
                                Text(item.rawValue).font(.hotelReadable(size: 15, weight: page == item ? .semibold : .regular))
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: sidebarCollapsed ? .center : .leading)
                        .padding(.horizontal, sidebarCollapsed ? 0 : 14)
                        .background(page == item ? Color(red: 0.76, green: 0.57, blue: 0.25) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white.opacity(page == item ? 1 : 0.82))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, sidebarCollapsed ? 8 : 10)
                    .help(item.rawValue)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { sidebarCollapsed.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: sidebarCollapsed ? "sidebar.right" : "sidebar.left")
                            .font(.hotelReadable(size: 17, weight: .medium)).frame(width: 22)
                        if !sidebarCollapsed {
                            Text("サイドバーを閉じる").font(.hotelReadable(size: 15)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: sidebarCollapsed ? .center : .leading)
                    .padding(.horizontal, sidebarCollapsed ? 0 : 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, sidebarCollapsed ? 8 : 10)
                .padding(.bottom, 12)
                .help(sidebarCollapsed ? "サイドバーを展開" : "サイドバーを閉じる")
                .accessibilityLabel(sidebarCollapsed ? "サイドバーを展開" : "サイドバーを閉じる")
            }
            .frame(width: sidebarCollapsed ? 56 : 238)
            .frame(maxHeight: .infinity)
            .background(navy)
            }

            VStack(spacing: 0) {
                if appearance.isDesktop {
                    macWorkspaceHeader(width: geometry.size.width - (sidebarCollapsed ? 56 : 238))
                } else {
                HStack {
                    if showsHeaderDetails {
                    // Use the same top bar across every main screen.
                    TimelineView(.periodic(from: Date(), by: 60)) { context in
                    Label(context.date.formatted(date: .complete, time: .omitted), systemImage: "calendar")
                        .font(.hotelReadable(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .modifier(AppGlassSurface(shape: RoundedRectangle(cornerRadius: 9)))
                    }
                    if page == .home {
                        Label("ローカル保存", systemImage: "checkmark.shield.fill")
                            .font(.hotelReadable(size: 12, weight: .medium))
                            .foregroundStyle(navy.opacity(0.75))
                            .lineLimit(1)
                    }
                    }
                    Spacer(minLength: 4)
                    if showsHeaderDetails {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(Color(red: 0.08, green: 0.17, blue: 0.29))
                        .padding(.horizontal, 6)
                        .accessibilityLabel("お知らせ")
                    }
                    Menu {
                        ForEach(store.data.locations) { location in
                            Button(location.name) { store.selectedLocationID = location.id }
                        }
                        Divider()
                        Button("＋ 店舗を追加") { showNewLocation = true }
                    } label: {
                        Label(store.selectedLocation?.name ?? "店舗を選択", systemImage: "building.2")
                            .font(.subheadline.weight(.semibold)).lineLimit(1).padding(.horizontal, compact ? 8 : 14).frame(minHeight: 44)
                            .modifier(AppGlassSurface(shape: RoundedRectangle(cornerRadius: 10), interactive: true))
                    }.tint(.primary).frame(maxWidth: compact ? 100 : nil, alignment: .trailing)
                }.padding(.horizontal, compact ? 8 : 18).padding(.vertical, compact ? 4 : 12)
                .overlay {
                    if compact {
                        Text(page.rawValue).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 110)
                            .allowsHitTesting(false)
                    }
                }
                }
                Group {
                    if compact { phoneTabView }
                    else { pageContent(page) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: max(0, geometry.size.width - (compact ? 0 : (sidebarCollapsed ? 56 : 238))),
                   height: geometry.size.height, alignment: .topLeading)
            .background(Color(red: 0.96, green: 0.975, blue: 0.99))
        }
        .environment(\.workspaceAppearance, appearance)
        .onAppear { updateIPadSidebar(for: geometry.size) }
        .onChange(of: geometry.size) { _, size in updateIPadSidebar(for: size) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hotelShiftOpenSettings)) { _ in
            page = .settings
        }
        .onOpenURL { url in
            if let link = IncomingLeaveLink.decode(url) {
                guard store.incomingRequestLinks.count < 20 else {
                    incomingLinkError = "未確認の申請リンクが20件あります。先に取り込んでからリンクを開き直してください。"; return
                }
                if !store.incomingRequestLinks.contains(where: { $0.id == link.id }) { store.incomingRequestLinks.append(link) }
                page = .requests
            } else if ["hotelshift", "eldiashift"].contains(url.scheme?.lowercased() ?? "") {
                incomingLinkError = "申請リンクを読み取れませんでした。リンクを最後までコピーするか、申請の文章を貼り付けてください。"
            }
        }
        .alert("申請リンク", isPresented: Binding(get: { incomingLinkError != nil }, set: { if !$0 { incomingLinkError = nil } })) {
            Button("OK") { incomingLinkError = nil }
        } message: { Text(incomingLinkError ?? "") }
        .onChange(of: page) { _, selected in
            phoneMoreLanding = false
            if selected != .shifts { requestedShiftDay = nil }
        }
        .tint(Color(red: 0.08, green: 0.43, blue: 0.91))
        .alert("データ保護のお知らせ", isPresented: Binding(
            get: { store.storageWarning != nil },
            set: { _ in }
        )) {
            Button("確認", role: .cancel) { store.acknowledgeStorageWarning() }
        } message: {
            Text(store.storageWarning ?? "")
        }
        .alert("店舗を追加", isPresented: $showNewLocation) {
            TextField("店舗名", text: $newLocationName)
            Button("キャンセル", role: .cancel) { newLocationName = "" }
            Button("追加") { store.addLocation(name: newLocationName); newLocationName = "" }
        }
    }
    private func pageContent(_ target: AppPage) -> some View {
        pageBody(target).modifier(MacWorkspacePage())
    }
    @ViewBuilder private func pageBody(_ target: AppPage) -> some View {
                    switch target {
                    case .home: DashboardView(onSelect: { phoneMoreLanding = false; requestedShiftDay = nil; page = $0 }, onOpenDay: { date in
                        phoneMoreLanding = false
                        requestedShiftDay = Calendar.current.startOfDay(for: date)
                        page = .shifts
                    })
                    case .shifts: ShiftCalendarView(initialDay: requestedShiftDay)
                    case .staff: StaffView()
                    case .requests: RequestsView()
                    case .labor: LaborView()
                    case .output: OutputView()
                    case .backup: BackupRestoreView()
                    case .locations: LocationManagementView()
                    case .settings: SettingsView()
                    }
    }
    private func macWorkspaceHeader(width: CGFloat) -> some View {
        VStack(spacing: 10) {
            if width >= 720 {
                HStack(spacing: 16) {
                    TimelineView(.periodic(from: Date(), by: 60)) { context in
                        Label(context.date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.frame(width: 180, alignment: .leading)
                    Text(page.rawValue).font(.title3.bold()).lineLimit(1)
                        .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
                    macLocationMenu.frame(width: 180, alignment: .trailing)
                }
            } else {
                Text(page.rawValue).font(.title3.bold()).lineLimit(1)
                    .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
                HStack {
                    Label("選択店舗", systemImage: "building.2").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    macLocationMenu
                }
            }
        }
        .padding(16)
        .background(.white)
        .overlay(alignment: .bottom) { Divider() }
    }
    private var macLocationMenu: some View {
        Menu {
            ForEach(store.data.locations) { location in
                Button(location.name) { store.selectedLocationID = location.id }
            }
            Divider()
            Button("＋ 店舗を追加") { showNewLocation = true }
        } label: {
            Label(store.selectedLocation?.name ?? "店舗を選択", systemImage: "building.2")
                .font(.subheadline.weight(.semibold)).lineLimit(1)
        }.buttonStyle(.bordered).controlSize(.regular)
        .accessibilityLabel("店舗を切り替え")
    }
    private var phoneUsesMore: Bool { ![AppPage.home, .shifts, .staff, .output].contains(page) }
    private var phoneTabSelection: Binding<PhoneTab> {
        Binding(get: {
            switch page {
            case .home: return .home
            case .shifts: return .shifts
            case .staff: return .staff
            case .output: return .output
            default: return .more
            }
        }, set: { selection in
            if selection == .more {
                withAnimation(.easeInOut(duration: 0.22)) {
                    phoneMoreLanding.toggle()
                }
                return
            }
            phoneMoreLanding = false
            let target: AppPage
            switch selection {
            case .home: target = .home
            case .shifts: target = .shifts
            case .staff: target = .staff
            case .output: target = .output
            case .more: return
            }
            if page != target { requestedShiftDay = nil; page = target }
        })
    }
    @ViewBuilder private var phoneTabView: some View {
        if #available(iOS 26.0, *) {
            phoneTabs.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            phoneTabs
        }
    }
    private var phoneTabs: some View {
        TabView(selection: phoneTabSelection) {
            pageContent(.home)
                .tabItem { Label("ホーム", systemImage: AppPage.home.icon) }.tag(PhoneTab.home)
            pageContent(.shifts).id(requestedShiftDay?.shiftDateKey ?? "phone-shifts")
                .tabItem { Label("シフト", systemImage: AppPage.shifts.icon) }.tag(PhoneTab.shifts)
            pageContent(.staff)
                .tabItem { Label("スタッフ", systemImage: AppPage.staff.icon) }.tag(PhoneTab.staff)
            pageContent(.output)
                .tabItem { Label("印刷", systemImage: AppPage.output.icon) }.tag(PhoneTab.output)
            pageContent(phoneUsesMore ? page : .settings)
                .tabItem { Label("その他", systemImage: "ellipsis.circle") }.tag(PhoneTab.more)
        }
        .overlay(alignment: .bottomTrailing) {
            if phoneMoreLanding {
                ZStack(alignment: .bottomTrailing) {
                    Color.black.opacity(0.001).ignoresSafeArea()
                        .onTapGesture { withAnimation { phoneMoreLanding = false } }
                        .accessibilityLabel("その他を閉じる")
                        .accessibilityAddTraits(.isButton)
                    phoneMoreContent.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
    private var phoneMoreContent: some View {
        VStack(spacing: 2) {
                        ForEach([AppPage.requests, .labor, .backup, .locations, .settings]) { item in
                            Button {
                                requestedShiftDay = nil
                                page = item
                                phoneMoreLanding = false
                            } label: {
                                HStack {
                                    Label(item.rawValue, systemImage: item.icon)
                                    Spacer()
                                    if page == item { Image(systemName: "checkmark") }
                                }.padding(.horizontal, 16).frame(minHeight: 48)
                            }
                        }
        }
        .fixedSize(horizontal: false, vertical: true)
        .buttonStyle(.plain)
        .padding(8)
        .frame(maxWidth: 300)
        .modifier(AppGlassSurface(shape: RoundedRectangle(cornerRadius: 24), interactive: true))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        // Keep the menu beside the trigger, above the expanded system tab bar.
        .padding(.horizontal, 16).padding(.bottom, 80)
    }
    private func updateIPadSidebar(for size: CGSize) {
        #if !targetEnvironment(macCatalyst)
        guard UIDevice.current.userInterfaceIdiom == .pad, size.width > 0, size.height > 0 else { return }
        let landscape = size.width > size.height
        // Preserve manual toggles until the window changes orientation.
        guard iPadLandscape != landscape else { return }
        iPadLandscape = landscape
        sidebarCollapsed = !landscape
        #endif
    }

}

struct DashboardView: View {
    @Environment(\.workspaceAppearance) private var workspaceAppearance
    @EnvironmentObject private var store: ShiftStore
    @State private var renderCache = ShiftRenderCache()
    @AppStorage("hotelShift.hotelName") private var hotelName = "ホテル名を設定"
    @AppStorage("hotelShift.heroMessage") private var heroMessage = "スタッフの笑顔が、お客様の特別な時間をつくります。"
    @AppStorage("hotelShift.heroImageBase64") private var heroImageBase64 = ""
    @AppStorage("hotelShift.accentGold") private var accentGold = true
    @AppStorage("hotelShift.dashboardSelectedDate") private var dashboardSelectedDateKey = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var calendarMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedCalendarDate = Date()
    var onSelect: (AppPage) -> Void
    var onOpenDay: (Date) -> Void
    private var gold: Color { accentGold ? Color(red: 0.76, green: 0.57, blue: 0.25) : Color(red: 0.12, green: 0.43, blue: 0.78) }
    private let ink = Color(red: 0.08, green: 0.17, blue: 0.29)
    private let line = Color(red: 0.88, green: 0.91, blue: 0.95)

    private var usesMacHomeLayout: Bool { workspaceAppearance.isDesktop }
    private var usesIPadHomeLayout: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 14) {
                    heroBanner
                    if UIDevice.current.userInterfaceIdiom == .phone { panel { noticesPanel } }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: UIDevice.current.userInterfaceIdiom == .phone ? 2 : (dynamicTypeSize.isAccessibilitySize || geo.size.width < 500 ? 1 : (geo.size.width > 850 ? 4 : 2))), spacing: 12) {
                        metric(title: "本日の出勤", value: "\(todayCount) / \(activeStaffCount)名", detail: "在籍 \(activeStaffCount)名", icon: "person.2.fill", color: Color(red: 0.12, green: 0.35, blue: 0.58))
                        metric(title: "今月の人件費見込み", value: "¥\(estimatedLaborCost.formatted())", detail: "登録シフトからの概算", icon: "yensign.circle.fill", color: gold)
                        metric(title: "未承認の申請", value: "\(store.selectedRequestsUnsorted.filter { $0.status == .pending }.count) 件", detail: "選択店舗の申請中件数", icon: "doc.text.fill", color: Color(red: 0.82, green: 0.29, blue: 0.32))
                        metric(title: "今月の登録シフト", value: "\(monthCount) 件", detail: "選択施設の登録件数", icon: "calendar.badge.clock", color: ink)
                    }
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        VStack(spacing: 12) {
                            panel { todayShiftPanel }
                            panel { calendarPanel }
                            panel { quickMenu }
                        }
                    } else if usesMacHomeLayout && geo.size.width > 1000 {
                        DashboardEqualHeightRow(weights: [0.39, 0.34, 0.27]) {
                            panel(fillHeight: true) { todayShiftPanel }
                            panel(fillHeight: true) { calendarPanel }
                            VStack(spacing: 12) {
                                panel(fillHeight: true) { quickMenu }
                                panel(fillHeight: true) { noticesPanel }
                            }.frame(maxHeight: .infinity, alignment: .top)
                        }
                    } else if usesIPadHomeLayout {
                        VStack(spacing: 12) {
                            DashboardEqualHeightRow(weights: [1, 1]) {
                                panel(fillHeight: true) { todayShiftPanel }
                                panel(fillHeight: true) { calendarPanel }
                            }
                            HStack(alignment: .top, spacing: 12) {
                                panel { quickMenu }
                                panel { noticesPanel }
                            }
                        }
                    } else if geo.size.width > 1000 {
                        HStack(alignment: .top, spacing: 12) {
                            panel { todayShiftPanel }.frame(maxWidth: geo.size.width * 0.39)
                            panel { calendarPanel }.frame(maxWidth: geo.size.width * 0.34)
                            VStack(spacing: 12) { panel { quickMenu }; panel { noticesPanel } }.frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 12) {
                            panel { todayShiftPanel }
                            panel { calendarPanel }
                            if geo.size.width < 500 || dynamicTypeSize.isAccessibilitySize {
                                panel { quickMenu }
                                panel { noticesPanel }
                            } else {
                                HStack(alignment: .top, spacing: 12) {
                                    panel { quickMenu }
                                    panel { noticesPanel }
                                }
                            }
                        }
                    }
                    if usesMacHomeLayout && geo.size.width > 850 {
                        DashboardEqualHeightRow(weights: [1, 1]) {
                            panel(fillHeight: true) { monthlyChart }
                            panel(fillHeight: true) { departmentPanel }
                        }
                    } else if geo.size.width > 850 {
                        HStack(alignment: .top, spacing: 12) { panel { monthlyChart }; panel { departmentPanel } }
                    } else {
                        VStack(spacing: 12) { panel { monthlyChart }; panel { departmentPanel } }
                    }
                }
                .padding(.horizontal, workspaceAppearance.inset(14)).padding(.top, workspaceAppearance.inset(2)).padding(.bottom, workspaceAppearance.inset(18))
                .frame(minWidth: 0)
            }
        }
        .onAppear {
            if let saved = Date.keyFormatter.date(from: dashboardSelectedDateKey) {
                selectedCalendarDate = saved
                calendarMonth = Calendar.current.startOfMonth(for: saved)
            }
        }
    }

    private func panel<Content: View>(fillHeight: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(13).frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(11)))
            .overlay(RoundedRectangle(cornerRadius: workspaceAppearance.radius(11)).stroke(line, lineWidth: 0.8))
    }

    private func metric(title: String, value: String, detail: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.hotelReadable(size: workspaceAppearance.fontSize(15), weight: .semibold)).foregroundStyle(color)
                    .frame(width: 30, height: 30).background(color.opacity(0.10), in: Circle())
                Text(title).font(.hotelReadable(size: workspaceAppearance.fontSize(12), weight: .semibold)).foregroundStyle(ink).lineLimit(2)
                Spacer(minLength: 0)
            }
            Text(value).font(.hotelReadable(size: workspaceAppearance.fontSize(22), weight: .bold, design: .rounded)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.65)
            Text(detail).font(.hotelReadable(size: workspaceAppearance.fontSize(10))).foregroundStyle(.secondary).lineLimit(1)
        }.padding(12)
            .frame(height: UIDevice.current.userInterfaceIdiom == .phone ? (dynamicTypeSize.isAccessibilitySize ? 160 : 124) : nil)
            .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(11)))
            .overlay(RoundedRectangle(cornerRadius: workspaceAppearance.radius(11)).stroke(line, lineWidth: 0.8))
    }

    private var heroBanner: some View {
        ZStack(alignment: .leading) {
            if let image = HotelHeaderImageCache.image(from: heroImageBase64) {
                GeometryReader { proxy in Image(uiImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped() }
            } else {
                LinearGradient(colors: [Color(red: 0.04, green: 0.12, blue: 0.21), Color(red: 0.22, green: 0.31, blue: 0.40)], startPoint: .leading, endPoint: .trailing)
                Image(systemName: "building.2.fill").font(.hotelReadable(size: workspaceAppearance.fontSize(100))).foregroundStyle(.white.opacity(0.09)).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 35)
            }
            LinearGradient(colors: [.black.opacity(0.68), .black.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 5) {
                Text(hotelName.isEmpty ? "ホテル名を設定" : hotelName).font(.hotelReadable(size: workspaceAppearance.fontSize(25), weight: .medium, design: .serif)).foregroundStyle(.white).lineLimit(1)
                if !heroMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(heroMessage).lineLimit(2).font(.hotelReadable(size: workspaceAppearance.fontSize(12), weight: .medium)).foregroundStyle(.white.opacity(0.93))
                }
                Text("\(store.selectedLocation?.name ?? "施設を選択")  ・  シフト管理ダッシュボード").font(.hotelReadable(size: workspaceAppearance.fontSize(10), weight: .medium)).foregroundStyle(gold).padding(.top, 3)
            }.padding(.horizontal, 24)
        }.frame(height: 108).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var todayShiftPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Label("本日のシフト", systemImage: "calendar.badge.clock").font(.hotelReadable(size: workspaceAppearance.fontSize(15), weight: .bold)).foregroundStyle(ink); Spacer(); Button("すべて見る →") { onOpenDay(Date()) }.font(.hotelReadable(size: workspaceAppearance.fontSize(10), weight: .semibold)).foregroundStyle(gold) }
            Text(Date().formatted(date: .complete, time: .omitted)).font(.hotelReadable(size: workspaceAppearance.fontSize(10))).foregroundStyle(.secondary)
            HStack { Text("時間"); Text("氏名・部署"); Spacer(); Text("勤務") }.font(.hotelReadable(size: workspaceAppearance.fontSize(10), weight: .semibold)).foregroundStyle(.secondary).padding(8).background(Color(red: 0.96, green: 0.975, blue: 0.99), in: RoundedRectangle(cornerRadius: 5))
            let displayedAssignments = todayAssignments
            let staffByID = Dictionary(uniqueKeysWithValues: store.selectedStaff.map { ($0.id, $0) })
            if displayedAssignments.isEmpty {
                VStack(spacing: 6) { Image(systemName: "calendar").font(.title2).foregroundStyle(.secondary); Text("本日の勤務予定はありません").font(.hotelReadable(size: workspaceAppearance.fontSize(11))).foregroundStyle(.secondary); Button("シフトを登録") { onOpenDay(Date()) }.font(.hotelReadable(size: workspaceAppearance.fontSize(11), weight: .semibold)).foregroundStyle(gold) }.frame(maxWidth: .infinity).padding(.vertical, 22)
            } else {
                ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                ForEach(displayedAssignments) { assignment in
                    if let person = staffByID[assignment.staffID] {
                        HStack(spacing: 7) {
                            Text(DayTimelineMath.span(assignment).map { DayTimelineMath.label($0.start) + "–" + DayTimelineMath.label($0.end) } ?? "-").font(.hotelReadable(size: workspaceAppearance.fontSize(9), weight: .medium)).frame(width: 68, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) { Text(person.name).font(.hotelReadable(size: workspaceAppearance.fontSize(11), weight: .semibold)).lineLimit(1); Text(person.department).font(.hotelReadable(size: workspaceAppearance.fontSize(9))).foregroundStyle(.secondary).lineLimit(1) }
                            Spacer(minLength: 1)
                            Text(assignment.type.rawValue).font(.hotelReadable(size: workspaceAppearance.fontSize(9), weight: .semibold)).foregroundStyle(shiftColor(assignment.type)).padding(.horizontal, 6).padding(.vertical, 4).background(shiftColor(assignment.type).opacity(0.10), in: Capsule())
                        }.padding(.vertical, 5)
                        if assignment.id != displayedAssignments.last?.id { Divider().overlay(line) }
                    }
                }
                }
                }.frame(height: 260)
            }
        }
    }

    private var calendarPanel: some View {
        let cells = calendarCells
        let visibleKeys = Set(cells.compactMap { $0.date?.shiftDateKey } + [selectedCalendarDate.shiftDateKey])
        var workingCounts: [String: Int] = [:]
        for assignment in store.selectedAssignments(on: visibleKeys)
        where DayTimelineMath.span(assignment) != nil {
            workingCounts[assignment.dateKey, default: 0] += 1
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Label("月間カレンダー", systemImage: "calendar").font(.hotelReadable(size: workspaceAppearance.fontSize(14), weight: .bold)).foregroundStyle(ink); Spacer(minLength: 2); Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain); Text(calendarMonth.formatted(.dateTime.year().month())).font(.hotelReadable(size: workspaceAppearance.fontSize(10), weight: .semibold)); Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain) }
            let weekdays = ["月", "火", "水", "木", "金", "土", "日"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 3) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { i, day in Text(day).font(.hotelReadable(size: workspaceAppearance.fontSize(9), weight: .bold)).foregroundStyle(i == 5 ? .blue : (i == 6 ? .red : .secondary)).frame(maxWidth: .infinity).padding(.vertical, 3) }
                ForEach(cells) { cell in
                    if let date = cell.date {
                        Button { selectedCalendarDate = date; dashboardSelectedDateKey = date.shiftDateKey } label: {
                            VStack(spacing: 3) {
                                Text(String(Calendar.current.component(.day, from: date))).font(.hotelReadable(size: workspaceAppearance.fontSize(10), weight: Calendar.current.isDateInToday(date) ? .bold : .regular)).foregroundStyle(Calendar.current.isDateInToday(date) ? .white : calendarDayColor(date))
                                    .frame(width: 20, height: 20).background(Calendar.current.isDateInToday(date) ? gold : .clear, in: Circle())
                                let count = workingCounts[date.shiftDateKey, default: 0]
                                if count > 0 { Text("\(count)名").font(.hotelReadable(size: workspaceAppearance.fontSize(8), weight: .semibold)).foregroundStyle(gold).lineLimit(1) } else { Text(" ").font(.hotelReadable(size: workspaceAppearance.fontSize(8))) }
                            }.frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                                .background(Calendar.current.isDate(selectedCalendarDate, inSameDayAs: date) ? gold.opacity(0.13) : Color(red: 0.985, green: 0.99, blue: 0.995), in: RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Calendar.current.isDate(selectedCalendarDate, inSameDayAs: date) ? gold.opacity(0.8) : .clear, lineWidth: 1))
                        }.buttonStyle(.plain)
                    } else { Color.clear.frame(height: 44).allowsHitTesting(false) }
                }
            }
            HStack(spacing: 8) { legend(gold, "勤務あり"); legend(.blue, "土曜"); legend(.red, "日曜") }.font(.hotelReadable(size: workspaceAppearance.fontSize(9))).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.clock").foregroundStyle(gold)
                Text(selectedCalendarDate.formatted(date: .numeric, time: .omitted))
                Spacer()
                Text("\(workingCounts[selectedCalendarDate.shiftDateKey, default: 0])名の勤務予定").fontWeight(.semibold).foregroundStyle(ink)
            }.font(.hotelReadable(size: workspaceAppearance.fontSize(9))).padding(.top, 2)
            Button {
                dashboardSelectedDateKey = selectedCalendarDate.shiftDateKey
                onOpenDay(selectedCalendarDate)
            } label: {
                Label("選択日のシフトを編集", systemImage: "square.and.pencil")
                    .font(.hotelReadable(size: workspaceAppearance.fontSize(10), weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .foregroundStyle(ink)
                    .background(gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain)
        }
    }

    private func legend(_ color: Color, _ label: String) -> some View { HStack(spacing: 3) { Circle().fill(color).frame(width: 6, height: 6); Text(label) } }

    private var quickMenu: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("クイックメニュー", systemImage: "bell.badge").font(.hotelReadable(size: workspaceAppearance.fontSize(14), weight: .bold)).foregroundStyle(ink)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                quickTile("勤務編集", icon: "square.and.pencil", page: .shifts)
                quickTile("PDFプレビュー", icon: "doc.text", page: .output)
                quickTile("印刷", icon: "printer.fill", page: .output)
                quickTile("CSV出力", icon: "doc.text.fill", page: .output)
                quickTile("JSONバックアップ", icon: "externaldrive.fill", page: .output)
                quickTile("設定", icon: "gearshape.fill", page: .settings)
            }
        }
    }

    private func quickTile(_ title: String, icon: String, page target: AppPage) -> some View {
        Button { onSelect(target) } label: {
            VStack(spacing: 7) { Image(systemName: icon).font(.hotelReadable(size: workspaceAppearance.fontSize(17), weight: .semibold)).foregroundStyle(ink); Text(title).font(.hotelReadable(size: workspaceAppearance.fontSize(9), weight: .semibold)).foregroundStyle(ink).multilineTextAlignment(.center).lineLimit(2) }
                .frame(maxWidth: .infinity, minHeight: 51).padding(5).background(Color(red: 0.975, green: 0.982, blue: 0.992), in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(line, lineWidth: 0.7))
        }.buttonStyle(.plain)
    }

    private var noticesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Label("お知らせ・申請通知", systemImage: "bell.fill").font(.hotelReadable(size: workspaceAppearance.fontSize(13), weight: .bold)).foregroundStyle(ink); Spacer(); Button("確認 →") { onSelect(.requests) }.font(.hotelReadable(size: workspaceAppearance.fontSize(9), weight: .semibold)).foregroundStyle(gold) }
            Label("データは端末内に保存されています", systemImage: "checkmark.shield.fill").font(.hotelReadable(size: workspaceAppearance.fontSize(9))).foregroundStyle(.secondary)
            Label("JSONバックアップを定期的に保存してください", systemImage: "externaldrive.badge.checkmark").font(.hotelReadable(size: workspaceAppearance.fontSize(9))).foregroundStyle(.secondary)
            Label("申請中 \(store.selectedRequestsUnsorted.filter { $0.status == .pending }.count)件・希望休画面で確認できます", systemImage: "info.circle.fill").font(.hotelReadable(size: workspaceAppearance.fontSize(9))).foregroundStyle(.secondary)
        }
    }

    private var monthlyChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("月間実績", systemImage: "chart.bar.xaxis").font(.hotelReadable(size: workspaceAppearance.fontSize(14), weight: .bold)).foregroundStyle(ink)
            HStack(alignment: .firstTextBaseline, spacing: 8) { Text("¥\(estimatedLaborCost.formatted())").font(.hotelReadable(size: workspaceAppearance.fontSize(22), weight: .bold, design: .rounded)).foregroundStyle(ink); Text("概算人件費").font(.hotelReadable(size: workspaceAppearance.fontSize(10))).foregroundStyle(.secondary) }
            let monthlyCounts = yearlyWorkingShiftCounts
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(1...12, id: \.self) { month in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(month == Calendar.current.component(.month, from: Date()) ? gold : Color(red: 0.76, green: 0.84, blue: 0.91)).frame(height: CGFloat(max(10, min(68, monthlyCounts[month - 1] * 8 + 10))))
                        Text("\(month)月").font(.hotelReadable(size: workspaceAppearance.fontSize(8))).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .bottom)
                }
            }.frame(height: 88, alignment: .bottom)
            Text("棒の高さは今年各月の勤務シフト件数です。人件費は登録時給と勤務区分からの概算です。").font(.hotelReadable(size: workspaceAppearance.fontSize(9))).foregroundStyle(.secondary)
        }
    }

    private var departmentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("部署別シフト構成", systemImage: "chart.pie.fill").font(.hotelReadable(size: workspaceAppearance.fontSize(14), weight: .bold)).foregroundStyle(ink)
            let currentMonthAssignments = store.selectedAssignments(inMonth: String(Date().shiftDateKey.prefix(7))).filter { ![.off, .afterNight, .paidLeave].contains($0.type) }
            let departmentsByStaff = Dictionary(uniqueKeysWithValues: store.selectedStaff.map { ($0.id, $0.department) })
            let departments = Dictionary(grouping: currentMonthAssignments.compactMap { a in departmentsByStaff[a.staffID] }, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
            if departments.isEmpty {
                Text("シフトを登録すると部署別の構成が表示されます。").font(.hotelReadable(size: workspaceAppearance.fontSize(11))).foregroundStyle(.secondary).padding(.vertical, 14)
            } else {
                ForEach(Array(departments.prefix(5).enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 8) {
                        Circle().fill([gold, .blue, .green, .orange, .purple][index % 5]).frame(width: 8, height: 8)
                        Text(item.0).font(.hotelReadable(size: workspaceAppearance.fontSize(10))).lineLimit(1)
                        Spacer()
                        GeometryReader { proxy in ZStack(alignment: .leading) { Capsule().fill(line); Capsule().fill([gold, .blue, .green, .orange, .purple][index % 5]).frame(width: proxy.size.width * CGFloat(item.1) / CGFloat(max(currentMonthAssignments.count, 1))) } }.frame(width: 65, height: 7)
                        Text("\(item.1)件").font(.hotelReadable(size: workspaceAppearance.fontSize(10), weight: .semibold)).frame(width: 32, alignment: .trailing)
                    }
                }
            }
            Text("人件費は登録された勤務・休憩時間に基づく概算（1日8時間超・22〜5時の各25%割増を反映）。週40時間超・法定休日等は未対応。部署別はシフト件数で集計。").font(.hotelReadable(size: workspaceAppearance.fontSize(9))).foregroundStyle(.secondary)
        }
    }

    private var todayAssignments: [ShiftAssignment] {
        store.selectedAssignments(on: [Date().shiftDateKey]).sorted {
            (DayTimelineMath.span($0)?.start ?? Int.max) < (DayTimelineMath.span($1)?.start ?? Int.max)
        }
    }
    private var activeStaffCount: Int { store.selectedStaff.filter(\.isActive).count }
    private var todayCount: Int { todayAssignments.filter { DayTimelineMath.span($0) != nil }.count }
    private var monthCount: Int { store.selectedAssignments(inMonth: String(Date().shiftDateKey.prefix(7))).count }
    private var estimatedLaborCost: Int {
        let wages = Dictionary(uniqueKeysWithValues: store.selectedStaff.map { ($0.id, $0.hourlyWage) })
        let month = String(Date().shiftDateKey.prefix(7))
        return store.selectedAssignments(inMonth: month).reduce(0) { total, assignment in
            guard let wage = wages[assignment.staffID] else { return total }
            return total + ShiftLaborEstimate.cost(assignment, hourlyWage: wage)
        }
    }
    // Aggregate all 12 dashboard bars in a single pass rather than filtering
    // the entire location's shift history separately for every month.
    private var yearlyWorkingShiftCounts: [Int] {
        let year = String(Date().shiftDateKey.prefix(4))
        return renderCache.value(for: ShiftRenderKey(revision: store.pdfRevision,
                                location: store.selectedLocationID, scope: "dashboard-year|" + year)) {
            (1...12).map { month in
                let key = year + String(format: "-%02d", month)
                return store.selectedAssignments(inMonth: key).reduce(0) { count, assignment in
                    count + ([ShiftType.off, .afterNight, .paidLeave].contains(assignment.type) ? 0 : 1)
                }
            }
        }
    }
    private struct DashboardCalendarCell: Identifiable {
        let id: String
        let date: Date?
    }
    private var calendarCells: [DashboardCalendarCell] {
        let calendar = Calendar(identifier: .gregorian)
        guard let interval = calendar.dateInterval(of: .month, for: calendarMonth), let days = calendar.range(of: .day, in: .month, for: calendarMonth) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let mondayOffset = (weekday + 5) % 7
        let dates: [Date?] = Array(repeating: nil, count: mondayOffset) + days.map {
            calendar.date(byAdding: .day, value: $0 - 1, to: interval.start)
        }
        return dates.enumerated().map { offset, date in
            DashboardCalendarCell(id: "day-\(interval.start.shiftDateKey)-\(offset)", date: date)
        }
    }
    private func shiftMonth(_ amount: Int) { if let next = Calendar.current.date(byAdding: .month, value: amount, to: calendarMonth) { calendarMonth = next } }
    private func calendarDayColor(_ date: Date) -> Color {
        let weekday = Calendar.current.component(.weekday, from: date)
        if weekday == 1 { return .red }; if weekday == 7 { return .blue }; return ink
    }
    private func shiftColor(_ type: ShiftType) -> Color {
        switch type { case .early: return .blue; case .day: return .green; case .late: return .orange; case .night: return .purple; case .off: return .red; default: return .secondary }
    }
}

struct MetricCard: View {
    let title: String; let value: String; let subtitle: String; let icon: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text(title).font(.subheadline).foregroundStyle(.secondary); Spacer(); Image(systemName: icon).foregroundStyle(color).padding(9).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 9)) }
            Text(value).font(.hotelReadable(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Color(red: 0.08, green: 0.17, blue: 0.28))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}
struct SectionHeading: View {
    let title: String; let subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) } }
}
struct QuickAction: View {
    let title: String; let icon: String; let color: Color; let action: () -> Void
    var body: some View { Button(action: action) { VStack(alignment: .leading, spacing: 14) { Image(systemName: icon).font(.title2).foregroundStyle(color); Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary); HStack { Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, minHeight: 82, alignment: .leading).padding(14).background(Color(red: 0.97, green: 0.98, blue: 1), in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain) }
}

#if targetEnvironment(macCatalyst)
// Resize the layout proposal before scaling, keeping hit targets and scrolling aligned.
struct MacWorkspaceContainer<Content: View>: View {
    @AppStorage("hotelShift.macDisplayScale") private var storedScale = 1.2
    @ViewBuilder let content: () -> Content
    private var scale: CGFloat {
        CGFloat(storedScale.isFinite ? min(1.6, max(1.0, storedScale)) : 1.2)
    }
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / scale
            let height = geometry.size.height / scale
            content()
                .environment(\.horizontalSizeClass, width < 700 ? .compact : .regular)
                .frame(width: width, height: height)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .background(MacWindowConfigurator().frame(width: 0, height: 0))
    }
}

// Apply to the actual attached window after SwiftUI creates it, rather than
// depending on a custom scene delegate being chosen by WindowGroup.
private struct MacWindowConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> WindowConfigurationView { WindowConfigurationView() }
    func updateUIView(_ view: WindowConfigurationView, context: Context) { view.configureWindow() }

    final class WindowConfigurationView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            configureWindow()
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            configureWindow()
        }
        func configureWindow() {
            guard let scene = window?.windowScene else { return }
            scene.title = "HOTEL SHIFT — FIXED560 / Mac Catalyst"
            guard let restrictions = scene.sizeRestrictions else { return }
            let minimum = CGSize(width: 640, height: 480)
            let maximum = CGSize(width: 16384, height: 16384)
            if restrictions.minimumSize != minimum { restrictions.minimumSize = minimum }
            if restrictions.maximumSize != maximum { restrictions.maximumSize = maximum }
        }
    }
}

struct MacDisplayCommands: Commands {
    @AppStorage("hotelShift.macDisplayScale") private var storedScale = 1.2
    private var scale: Double {
        storedScale.isFinite ? min(1.6, max(1.0, storedScale)) : 1.2
    }
    var body: some Commands {
        CommandMenu("表示") {
            Text("FIXED560 · Mac Catalyst")
            Button("ウィンドウ情報をコピー") { copyWindowDiagnostics() }
            Divider()
            Button("拡大") { storedScale = (min(1.6, scale + 0.1) * 100).rounded() / 100 }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(scale >= 1.6)
            Button("縮小") { storedScale = (max(1.0, scale - 0.1) * 100).rounded() / 100 }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(scale <= 1.0)
            Button("標準サイズ（120%）") { storedScale = 1.2 }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Picker("表示倍率", selection: $storedScale) {
                Text("100%").tag(1.0)
                Text("110%").tag(1.1)
                Text("120%").tag(1.2)
                Text("130%").tag(1.3)
                Text("140%").tag(1.4)
                Text("150%").tag(1.5)
                Text("160%").tag(1.6)
            }
        }
    }
    @MainActor private func copyWindowDiagnostics() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let details = scenes.map { scene in
            let minimum = scene.sizeRestrictions.map { String(describing: $0.minimumSize) } ?? "unavailable"
            let maximum = scene.sizeRestrictions.map { String(describing: $0.maximumSize) } ?? "unavailable"
            return "title: \(scene.title ?? "")\nstate: \(scene.activationState.rawValue)\nsize: \(scene.coordinateSpace.bounds.size)\nminimum: \(minimum)\nmaximum: \(maximum)"
        }.joined(separator: "\n\n")
        UIPasteboard.general.string = "HOTEL SHIFT FIXED560 / Mac Catalyst\nOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nDisplay scale: \(scale)\n" + details
    }

}
#endif

private extension Font {
    static func hotelReadable(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        #if targetEnvironment(macCatalyst)
        return .system(size: max(12, size), weight: weight, design: design)
        #else
        return .system(size: size, weight: weight, design: design)
        #endif
    }
}


// Measure each column at its assigned width, then place all at the tallest height.
struct DashboardEqualHeightRow: Layout {
    var weights: [CGFloat]
    var spacing: CGFloat = 12
    private func columnWidths(_ width: CGFloat, count: Int) -> [CGFloat] {
        let values = (0..<count).map { $0 < weights.count ? max(0.01, weights[$0]) : 1 }
        let total = values.reduce(0, +)
        let available = max(0, width - spacing * CGFloat(max(0, count - 1)))
        return values.map { available * $0 / total }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 1000
        let widths = columnWidths(width, count: subviews.count)
        let height = subviews.indices.map {
            subviews[$0].sizeThatFits(ProposedViewSize(width: widths[$0], height: nil)).height
        }.max() ?? 0
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = columnWidths(bounds.width, count: subviews.count)
        var x = bounds.minX
        for index in subviews.indices {
            subviews[index].place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                                  proposal: ProposedViewSize(width: widths[index], height: bounds.height))
            x += widths[index] + spacing
        }
    }
}

// Scoped to each window, so iPad rotation and multitasking do not affect other windows.
struct WorkspaceAppearance {
    var isDesktop: Bool
    static var platformDefault: WorkspaceAppearance {
        #if targetEnvironment(macCatalyst)
        return WorkspaceAppearance(isDesktop: true)
        #else
        return WorkspaceAppearance(isDesktop: false)
        #endif
    }
    static func forWindow(width: CGFloat, height: CGFloat, isPad: Bool) -> WorkspaceAppearance {
        #if targetEnvironment(macCatalyst)
        return WorkspaceAppearance(isDesktop: true)
        #else
        return WorkspaceAppearance(isDesktop: isPad && width > height)
        #endif
    }
    var contentWidth: CGFloat? { isDesktop ? nil : 1200 }
    func fontSize(_ original: CGFloat) -> CGFloat { isDesktop ? max(12, original) : original }
    let canvas = Color(red: 0.96, green: 0.975, blue: 0.99)
    func inset(_ mobile: CGFloat) -> CGFloat { isDesktop ? 0 : mobile }
    func radius(_ mobile: CGFloat) -> CGFloat { isDesktop ? 14 : mobile }
    func background(_ mobile: Color) -> Color { isDesktop ? canvas : mobile }
}
private struct WorkspaceAppearanceKey: EnvironmentKey {
    static let defaultValue = WorkspaceAppearance.platformDefault
}
extension EnvironmentValues {
    var workspaceAppearance: WorkspaceAppearance {
        get { self[WorkspaceAppearanceKey.self] }
        set { self[WorkspaceAppearanceKey.self] = newValue }
    }
}
struct MacWorkspacePage: ViewModifier {
    @Environment(\.workspaceAppearance) private var workspaceAppearance
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.controlSize) private var inheritedControlSize
    // Keep the same view hierarchy on rotation so tab/filter/editor state survives.
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .environment(\.horizontalSizeClass, workspaceAppearance.isDesktop
                             ? (geometry.size.width < 700 ? .compact : .regular) : horizontalSizeClass)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(workspaceAppearance.isDesktop ? 16 : 0)
        .background(workspaceAppearance.isDesktop ? workspaceAppearance.canvas : Color.clear)
        .tint(workspaceAppearance.isDesktop
              ? Color(red: 0.12, green: 0.43, blue: 0.91)
              : Color(red: 0.08, green: 0.43, blue: 0.91))
        .controlSize(workspaceAppearance.isDesktop ? .regular : inheritedControlSize)
    }
}
