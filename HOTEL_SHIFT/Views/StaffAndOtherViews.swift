import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import PDFKit
import CoreImage
import Vision
import ImageIO
import CoreImage.CIFilterBuiltins

// Small views share downsampled images; original bytes remain backward compatible.
private enum StaffPhotoDecodeCache {
    static func image(from data: Data) -> UIImage? { ShiftPhotoCache.image(data) }
}

struct StaffView: View {
    @Environment(\.workspaceAppearance) private var workspaceAppearance
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var usesCards: Bool {
        UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }
    @State private var search = ""
    @State private var phoneStaffTab = "登録スタッフ"
    @State private var selectedDepartment = "すべて"
    @State private var staffStatusFilter = "勤務可能"
    @State private var showAdd = false
    @State private var editingStaff: StaffMember?
    @State private var deletingStaff: StaffMember?
    @State private var changingStatusStaff: StaffMember?
    @State private var showDepartmentManager = false
    @State private var customDepartments: [String] = UserDefaults.standard.stringArray(forKey: "hotelShift.customDepartments") ?? []
    @State private var departmentToDelete: String?
    @State private var departmentToEdit: String?
    @State private var editedDepartmentName = ""
    @State private var detailStaff: StaffMember?
    @State private var selectedStaffID: UUID?
    @State private var inlineEditing: StaffMember?
    @State private var inlineDirty = false
    @State private var editorSession = UUID()
    private enum StaffAction { case select(UUID), edit(StaffMember) }
    @State private var pendingStaffAction: StaffAction?
    private var usesInlineStaffLayout: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }
    @State private var newDepartment = ""
    @State private var wagePrefecture = UserDefaults.standard.string(forKey: "hotelShift.wagePrefecture") ?? "兵庫県"
    private let minimumWages: [String: Int] = [
        "北海道":1131,"青森県":1029,"岩手県":1031,"宮城県":1098,"秋田県":1090,"山形県":1032,"福島県":1094,
        "茨城県":1136,"栃木県":1125,"群馬県":1120,"埼玉県":1196,"千葉県":1195,"東京都":1280,"神奈川県":1279,
        "新潟県":1108,"富山県":1119,"石川県":1113,"福井県":1112,"山梨県":1052,"長野県":1117,"岐阜県":1121,"静岡県":1154,"愛知県":1195,
        "三重県":1143,"滋賀県":1136,"京都府":1122,"大阪府":1231,"兵庫県":1172,"奈良県":1107,"和歌山県":1101,
        "鳥取県":1090,"島根県":1033,"岡山県":1104,"広島県":1085,"山口県":1043,"徳島県":1046,"香川県":1092,"愛媛県":1033,"高知県":1023,
        "福岡県":1114,"佐賀県":1030,"長崎県":1031,"熊本県":1034,"大分県":1035,"宮崎県":1023,"鹿児島県":1026,"沖縄県":1023
    ]
    private var currentMinimumWage: Int { minimumWages[wagePrefecture] ?? 1172 }
    private let prefectures = ["北海道","青森県","岩手県","宮城県","秋田県","山形県","福島県","茨城県","栃木県","群馬県","埼玉県","千葉県","東京都","神奈川県","新潟県","富山県","石川県","福井県","山梨県","長野県","岐阜県","静岡県","愛知県","三重県","滋賀県","京都府","大阪府","兵庫県","奈良県","和歌山県","鳥取県","島根県","岡山県","広島県","山口県","徳島県","香川県","愛媛県","高知県","福岡県","佐賀県","長崎県","熊本県","大分県","宮崎県","鹿児島県","沖縄県"]

    @State private var builtInDepartments: [String] = UserDefaults.standard.stringArray(forKey: "hotelShift.standardDepartments") ?? ["フロント", "キッチン", "ルームメイク"]
    private var allDepartments: [String] {
        Array(Set(builtInDepartments + customDepartments + store.selectedStaff.map(\.department))).sorted()
    }
    private var departments: [String] { ["すべて"] + allDepartments }
    private let staffStatusOptions = ["勤務可能", "休止中", "すべて"]
    private var filtered: [StaffMember] {
        // Normalize the query once, rather than once for every staff member.
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let allDepartmentsSelected = selectedDepartment == "すべて"
        return store.selectedStaff.filter { staff in
            (staffStatusFilter == "すべて" || (staffStatusFilter == "勤務可能" ? staff.isActive : !staff.isActive)) &&
            (allDepartmentsSelected || staff.department == selectedDepartment) &&
            (query.isEmpty ||
             staff.name.localizedCaseInsensitiveContains(query) ||
             staff.department.localizedCaseInsensitiveContains(query) ||
             staff.employment.localizedCaseInsensitiveContains(query))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private let navy = Color(red: 0.055, green: 0.15, blue: 0.27)
    private let blue = Color(red: 0.12, green: 0.46, blue: 0.91)

    var body: some View {
        // Reuse one filtered snapshot for the count, empty state and rows.
        let visibleStaff = filtered
        return Group {
            if usesInlineStaffLayout {
                inlineStaffWorkspace(visibleStaff)
            } else if UIDevice.current.userInterfaceIdiom == .phone {
                phoneStaffWorkspace(visibleStaff)
            } else if usesCards {
                mobileStaffList(visibleStaff)
            } else {
            VStack(spacing: 0) {
            // Header mirrors the reference screen: search and a prominent add action.
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.selectedLocation?.name ?? "選択施設")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("スタッフ名で検索", text: $search)
                        .textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).frame(width: 260, height: 42)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08)))
                Button { showDepartmentManager = true } label: {
                    Label("部署管理", systemImage: "building.2")
                        .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 13).frame(height: 42)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.10))).foregroundStyle(navy)
                }.buttonStyle(.plain)
                Button { showAdd = true } label: {
                    Label("新規登録", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16).frame(height: 42)
                        .background(blue, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.white)
                }.buttonStyle(.plain)
            }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 16)

            // Department filter chips.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(departments, id: \.self) { department in
                        Button { selectedDepartment = department } label: {
                            Text(department).font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(selectedDepartment == department ? blue : Color.white,
                                            in: Capsule())
                                .foregroundStyle(selectedDepartment == department ? .white : Color.primary)
                                .overlay(Capsule().stroke(selectedDepartment == department ? blue : Color.black.opacity(0.08)))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 22).padding(.bottom, 14)
            }

            // FIXED226: Keep inactive staff available without mixing them into the default roster.
            HStack(spacing: 10) {
                Picker("勤務状態", selection: $staffStatusFilter) {
                    ForEach(staffStatusOptions, id: \.self) { option in Text(option).tag(option) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                Spacer(minLength: 0)
                Text("勤務可能 \(store.selectedStaff.filter(\.isActive).count)名 / 休止中 \(store.selectedStaff.filter { !$0.isActive }.count)名")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 22).padding(.bottom, 12)

            HStack {
                Label("スタッフ一覧", systemImage: "person.2.fill")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(navy)
                Text("\(visibleStaff.count)名").font(.system(size: workspaceAppearance.fontSize(11), weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(blue.opacity(0.10), in: Capsule()).foregroundStyle(blue)
                Spacer()
                Text("勤務地").font(.system(size: workspaceAppearance.fontSize(11), weight: .medium)).foregroundStyle(.secondary)
                Picker("勤務地の都道府県", selection: $wagePrefecture) {
                    ForEach(prefectures, id: \.self) { Text($0).tag($0) }
                }.frame(width: 125).onChange(of: wagePrefecture) { _, value in UserDefaults.standard.set(value, forKey: "hotelShift.wagePrefecture") }
                Text("最低時給 ¥\(currentMinimumWage)").font(.system(size: workspaceAppearance.fontSize(11), weight: .semibold)).foregroundStyle(blue)
            }.padding(.horizontal, 22).padding(.vertical, 12)

            // Table header, similar to the supplied staff-management screenshot.
            HStack(spacing: 12) {
                Text("氏名").frame(maxWidth: .infinity, alignment: .leading)
                Text("所属部署").frame(width: 145, alignment: .leading)
                Text("雇用形態").frame(width: 115, alignment: .leading)
                Text("時給").frame(width: 90, alignment: .trailing)
                Text("ステータス").frame(width: 92, alignment: .center)
            }.font(.system(size: workspaceAppearance.fontSize(11), weight: .bold)).foregroundStyle(Color.secondary)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Color(red: 0.96, green: 0.97, blue: 0.99))

            if visibleStaff.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("スタッフが見つかりません").font(.system(size: 15, weight: .semibold))
                    Text("検索条件を変更するか、「新規登録」からスタッフを追加してください。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleStaff) { staff in
                            HStack(spacing: 12) {
                                HStack(spacing: 10) {
                                    Group {
                                        if let data = staff.photoData {
                                            AsyncStaffPortrait(data: data).frame(width: 36, height: 36).clipShape(Circle())
                                        } else {
                                            Circle().fill(avatarColor(for: staff.department).gradient).frame(width: 36, height: 36)
                                                .overlay(Text(String(staff.name.prefix(1))).font(.system(size: 15, weight: .bold)).foregroundStyle(.white))
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(staff.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(navy)
                                        Text(staff.isActive ? "登録済みスタッフ" : "休止中")
                                            .font(.system(size: workspaceAppearance.fontSize(10))).foregroundStyle(.secondary)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Text(staff.department).font(.system(size: 12)).foregroundStyle(.secondary)
                                    .frame(width: 145, alignment: .leading)
                                Text(staff.employment).font(.system(size: 12)).foregroundStyle(.secondary)
                                    .frame(width: 115, alignment: .leading)
                                Text("¥\(staff.hourlyWage.formatted())").font(.system(size: 12, weight: .semibold))
                                    .frame(width: 90, alignment: .trailing)
                                Text(staff.isActive ? "勤務可能" : "休止中")
                                    .font(.system(size: workspaceAppearance.fontSize(10), weight: .semibold))
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background((staff.isActive ? Color.green : Color.gray).opacity(0.12), in: Capsule())
                                    .foregroundStyle(staff.isActive ? Color.green : Color.gray)
                                    .frame(width: 92, alignment: .center)
                            }
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .onTapGesture { openStaffDetail(staff) }
                            .contextMenu {
                                Button { changingStatusStaff = staff } label: {
                                    Label(staff.isActive ? "休止中に変更" : "勤務可能に戻す", systemImage: staff.isActive ? "pause.circle" : "play.circle")
                                }
                                Button(role: .destructive) { deletingStaff = staff } label: {
                                    Label("スタッフを削除", systemImage: "trash")
                                }
                            }
                            .background(Color.white)
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.055)).frame(height: 1) }
                        }
                    }
                }
            }
        }
            }
        }
        .background(UIDevice.current.userInterfaceIdiom == .phone ? Color.clear : workspaceAppearance.background(Color(red: 0.985, green: 0.99, blue: 1)), in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(16)))
        .overlay(RoundedRectangle(cornerRadius: workspaceAppearance.radius(16)).stroke(Color.black.opacity(UIDevice.current.userInterfaceIdiom == .phone ? 0 : 0.05)))
        .padding(.horizontal, workspaceAppearance.inset(usesCards ? 8 : 24)).padding(.bottom, workspaceAppearance.inset(usesCards ? 8 : 24))
        .sheet(isPresented: $showAdd) {
            StaffFormSheet(title: "スタッフを新規登録", availableDepartments: allDepartments, minimumWage: currentMinimumWage) { name, dept, employment, wage, photoData in
                store.addStaff(name: name, department: dept, employment: employment, wage: wage)
                if let index = store.data.staff.lastIndex(where: { $0.name == name && $0.locationID == store.selectedLocationID }) { store.data.staff[index].photoData = photoData }
            }
        }
        .sheet(item: $editingStaff) { staff in
            StaffFormSheet(title: "スタッフ情報を編集", initial: staff, availableDepartments: allDepartments, minimumWage: currentMinimumWage) { name, dept, employment, wage, photoData in
                store.updateStaff(id: staff.id, expectedLocationID: staff.locationID, name: name, department: dept, employment: employment, wage: wage, photoData: photoData)
            }
        }
        .sheet(item: $detailStaff) { staff in
            StaffDetailSheet(staff: currentStaff(staff)) {
                editingStaff = currentStaff(staff)
                detailStaff = nil
            } onChangeStatus: { selected in
                detailStaff = nil
                changingStatusStaff = selected
            }
        }
        .sheet(isPresented: $showDepartmentManager) { departmentManagerContent }
        .alert("勤務状態を変更しますか？", isPresented: Binding(
            get: { changingStatusStaff != nil }, set: { if !$0 { changingStatusStaff = nil } }
        ), presenting: changingStatusStaff) { staff in
            Button(staff.isActive ? "休止中にする" : "勤務可能に戻す") {
                if let current = store.data.staff.first(where: { $0.id == staff.id && $0.locationID == staff.locationID }) {
                    _ = store.setStaffActive(id: current.id, expectedLocationID: current.locationID, active: !current.isActive)
                }
                changingStatusStaff = nil
            }
            Button("キャンセル", role: .cancel) { changingStatusStaff = nil }
        } message: { staff in
            Text(staff.isActive ? "「\(staff.name)」を休止中にします。過去のシフト・希望休・勤務パターンは残り、新規の自動割当対象から外れます。" : "「\(staff.name)」を勤務可能に戻します。保存済みの勤務データはそのまま保持されます。")
        }
        .alert("スタッフを削除しますか？", isPresented: Binding(
            get: { deletingStaff != nil }, set: { if !$0 { deletingStaff = nil } }
        ), presenting: deletingStaff) { staff in
            Button("削除する", role: .destructive) { store.deleteStaff(staff); deletingStaff = nil }
                .disabled({
                    guard let impact = store.staffDeletionImpact(staff) else { return true }
                    return impact.assignments + impact.requests + impact.patterns + impact.personalWorkTimes > 0
                }())
            Button("キャンセル", role: .cancel) { deletingStaff = nil }
        } message: { staff in
            if let impact = store.staffDeletionImpact(staff) {
                Text("「\(staff.name)」の関連データ：\nシフト：\(impact.assignments)件\n希望休：\(impact.requests)件\n勤務パターン：\(impact.patterns)件\n個人の時間：\(impact.personalWorkTimes)件\n関連データがある場合は削除できません。長押しメニューから『休止中に変更』してください。関連データがない場合のみ削除できます。")
            } else {
                Text("対象スタッフが現在のホテルに存在しません。削除は実行されません。")
            }
        }
    }

    private var departmentManagerList: some View {
                List {
                    Section("部署を追加") {
                        if UIDevice.current.userInterfaceIdiom == .phone {
                            HStack(spacing: 8) {
                                TextField("新しい部署名", text: $newDepartment)
                                    .textFieldStyle(.plain).padding(.horizontal, 12).frame(minHeight: 44)
                                    .modifier(AppGlassSurface(shape: RoundedRectangle(cornerRadius: 10), interactive: true))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.25)))
                                    .submitLabel(.done)
                                    .onSubmit {
                                        let value = newDepartment.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !value.isEmpty && !allDepartments.contains(value) { addDepartment() }
                                    }
                                Button { addDepartment() } label: {
                                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                                        .frame(width: 30, height: 30)
                                        .modifier(AppGlassSurface(shape: Circle(), interactive: true))
                                        .frame(width: 44, height: 44).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("部署を追加")
                                    .disabled(newDepartment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || allDepartments.contains(newDepartment.trimmingCharacters(in: .whitespacesAndNewlines)))
                            }
                        } else {
                        HStack {
                            TextField("新しい部署名", text: $newDepartment)
                            Button("追加") { addDepartment() }
                                .disabled(newDepartment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || allDepartments.contains(newDepartment.trimmingCharacters(in: .whitespacesAndNewlines)))
                        }
                        }
                    }
                    Section("登録済み部署") {
                        ForEach(allDepartments, id: \.self) { department in
                            HStack {
                                Text(department)
                                Spacer()
                                if builtInDepartments.contains(department) {
                                    Text("標準").font(.caption).foregroundStyle(.secondary)
                                }
                                Button {
                                    departmentToEdit = department
                                    editedDepartmentName = department
                                } label: { Image(systemName: "pencil").frame(width: 32, height: 32) }
                                    .buttonStyle(.borderless).accessibilityLabel("\(department)の名称を変更")
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !builtInDepartments.contains(department) {
                                    Button(role: .destructive) { departmentToDelete = department } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    departmentToEdit = department
                                    editedDepartmentName = department
                                } label: { Label("編集", systemImage: "pencil") }
                                .tint(.blue)
                            }
                        }
                    }
                    Section { Text("部署を左へスワイプすると削除、右へスワイプすると名称変更できます。部署名の変更は所属スタッフにも反映されます。標準部署も鉛筆ボタンまたは右スワイプで名称変更できます。標準部署の削除はできません。").font(.footnote).foregroundStyle(.secondary) }
                }
    }
    private var departmentManagerContent: some View {
            NavigationStack {
                Group {
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        departmentManagerList.listStyle(.plain).scrollContentBackground(.hidden)
                    } else { departmentManagerList }
                }
                .navigationTitle("部署管理").navigationBarTitleDisplayMode(.inline)
                .toolbar(UIDevice.current.userInterfaceIdiom == .phone ? .hidden : .automatic, for: .navigationBar)
                .toolbar {
                    if UIDevice.current.userInterfaceIdiom != .phone {
                        ToolbarItem(placement: .confirmationAction) { Button("閉じる") { showDepartmentManager = false } }
                    }
                }
                .alert("部署を削除しますか？", isPresented: Binding(get: { departmentToDelete != nil }, set: { if !$0 { departmentToDelete = nil } })) {
                    Button("削除する", role: .destructive) {
                        if let department = departmentToDelete {
                            customDepartments.removeAll { $0 == department }
                            UserDefaults.standard.set(customDepartments, forKey: "hotelShift.customDepartments")
                            for index in store.data.staff.indices where store.data.staff[index].department == department {
                                store.data.staff[index].department = "未設定"
                            }
                            if selectedDepartment == department { selectedDepartment = "すべて" }
                        }
                        departmentToDelete = nil
                    }
                    Button("キャンセル", role: .cancel) { departmentToDelete = nil }
                } message: { Text("部署名「\(departmentToDelete ?? "")」を削除します。所属スタッフの部署名は「未設定」に変更されます。") }
                .alert("部署名を編集", isPresented: Binding(get: { departmentToEdit != nil }, set: { if !$0 { departmentToEdit = nil } })) {
                    TextField("部署名", text: $editedDepartmentName)
                    Button("保存") { renameDepartment() }
                        .disabled(editedDepartmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (allDepartments.contains(editedDepartmentName.trimmingCharacters(in: .whitespacesAndNewlines)) && editedDepartmentName.trimmingCharacters(in: .whitespacesAndNewlines) != departmentToEdit))
                    Button("キャンセル", role: .cancel) { departmentToEdit = nil }
                } message: { Text("変更した部署名は所属スタッフにも反映されます。") }
            }.presentationDetents([.medium, .large])    }
    private func phoneStaffWorkspace(_ people: [StaffMember]) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("スタッフ名・部署で検索", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 32, height: 32) }
                        .accessibilityLabel("検索をクリア")
                }
            }.padding(.horizontal, 14).frame(minHeight: 44)
                .modifier(AppGlassSurface(shape: Capsule(), interactive: true))
            Picker("スタッフ画面", selection: $phoneStaffTab) {
                ForEach(["登録スタッフ", "部署管理", "設定"], id: \.self) { Text($0).tag($0) }
            }.modifier(PhoneTabStyle())
            if phoneStaffTab == "部署管理" {
                departmentManagerContent
            } else if phoneStaffTab == "設定" {
                Form {
                    Section("最低時給") {
                        Picker("勤務地の都道府県", selection: $wagePrefecture) {
                            ForEach(prefectures, id: \.self) { Text($0).tag($0) }
                        }
                        .onChange(of: wagePrefecture) { _, value in UserDefaults.standard.set(value, forKey: "hotelShift.wagePrefecture") }
                        LabeledContent("選択地域の最低時給", value: "¥\(currentMinimumWage.formatted())")
                    }
                }.scrollContentBackground(.hidden)
            } else {
                HStack {
                    Picker("勤務状態", selection: $staffStatusFilter) {
                        ForEach(staffStatusOptions, id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.menu)
                    Picker("部署", selection: $selectedDepartment) {
                        ForEach(departments, id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.menu)
                    Spacer(minLength: 0)
                    Button { showAdd = true } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                        .modifier(AppActionStyle()).buttonBorderShape(.circle).accessibilityLabel("スタッフを新規登録")
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if people.isEmpty { ContentUnavailableView.search(text: search) }
                        ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                            phoneStaffRow(person)
                            if index < people.count - 1 { Divider().padding(.horizontal, 12) }
                        }
                    }
                }.scrollDismissesKeyboard(.interactively)
            }
        }.padding(.top, 8)
    }
    private func phoneStaffRow(_ person: StaffMember) -> some View {
        Button { openStaffDetail(person) } label: {
            Grid(alignment: .leading, horizontalSpacing: 12) {
              GridRow {
                VStack(spacing: 8) {
                    if let data = person.photoData {
                        AsyncStaffPortrait(data: data).frame(width: 60, height: 60).clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 52)).foregroundStyle(.secondary)
                    }
                    Text(person.name).font(.subheadline.bold()).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    Text(person.department).font(.subheadline.bold())
                    Text(person.employment).font(.subheadline).foregroundStyle(.secondary)
                    Text("時給 ¥\(person.hourlyWage.formatted())").font(.subheadline).monospacedDigit()
                    Label(person.isActive ? "勤務可" : "勤務不可・休止中", systemImage: person.isActive ? "checkmark.circle" : "pause.circle")
                        .font(.caption).foregroundStyle(person.isActive ? .green : .secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).gridCellColumns(2)
              }
              GridRow {
                  Color.clear.frame(height: 0)
                  Color.clear.frame(height: 0)
                  Color.clear.frame(height: 0)
              }.hidden()
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityHint("スタッフ詳細を開きます")
    }
    private func openStaffDetail(_ staff: StaffMember) {
        if usesInlineStaffLayout { requestStaffAction(.select(staff.id)) }
        else { detailStaff = staff }
    }
    private func requestStaffEdit(_ staff: StaffMember) {
        if usesInlineStaffLayout { requestStaffAction(.edit(currentStaff(staff))) }
        else { editingStaff = staff }
    }
    private func requestStaffAction(_ action: StaffAction) {
        if inlineDirty { pendingStaffAction = action }
        else { applyStaffAction(action) }
    }
    private func applyStaffAction(_ action: StaffAction) {
        inlineEditing = nil; inlineDirty = false; editorSession = UUID()
        switch action {
        case .select(let id): selectedStaffID = id
        case .edit(let person): selectedStaffID = person.id; inlineEditing = person
        }
    }
    private func finishInlineEditing() {
        inlineEditing = nil; inlineDirty = false
        reconcileStaffSelection(filtered.map(\.id))
    }
    private func inlineStaffWorkspace(_ people: [StaffMember]) -> some View {
        GeometryReader { geometry in
            let horizontal = workspaceAppearance.isDesktop
                ? geometry.size.width >= 650
                : geometry.size.width > geometry.size.height
            let layout = horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                Group {
                    if horizontal { mobileStaffList(people) }
                    else { portraitStaffSelector(people) }
                }
                .frame(width: horizontal ? min(340, max(180, geometry.size.width * 0.34)) : nil,
                       height: horizontal ? nil : 210)
                Rectangle().fill(Color.gray.opacity(0.2))
                    .frame(width: horizontal ? 1 : nil, height: horizontal ? nil : 1)
                inlineStaffDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { reconcileStaffSelection(people.map(\.id)) }
        .onChange(of: people.map(\.id)) { _, ids in reconcileStaffSelection(ids) }
        .confirmationDialog("未保存のスタッフ情報があります", isPresented: Binding(
            get: { pendingStaffAction != nil },
            set: { if !$0 { pendingStaffAction = nil } }
        ), titleVisibility: .visible) {
            Button("変更を破棄して切り替える", role: .destructive) {
                guard let action = pendingStaffAction else { return }
                pendingStaffAction = nil; applyStaffAction(action)
            }
            Button("編集を続ける", role: .cancel) { pendingStaffAction = nil }
        } message: { Text("保存していない氏名・時給・写真などの変更があります。") }
    }
    @ViewBuilder private var inlineStaffDetail: some View {
        if let person = inlineEditing {
            StaffFormSheet(title: "スタッフ情報を編集", initial: person, availableDepartments: allDepartments,
                           minimumWage: currentMinimumWage, embedded: true,
                           onClose: { finishInlineEditing() },
                           onDirtyChange: { inlineDirty = $0 },
                           contextWarning: person.locationID != store.selectedLocationID ? "店舗が変わりました。元の店舗へ戻るか、編集をキャンセルしてください。" : nil,
                           onCommit: { name, department, employment, wage, photo in
                               store.saveStaffProfile(expected: person, name: name, department: department,
                                                      employment: employment, wage: wage, photoData: photo)
                           }, onSave: { _, _, _, _, _ in })
                .id(editorSession)
        } else if let person = store.selectedStaff.first(where: { $0.id == selectedStaffID }) {
            StaffDetailSheet(staff: person, embedded: true,
                             onEdit: { requestStaffEdit(person) },
                             onChangeStatus: { changingStatusStaff = $0 })
                .id(person.id)
        } else {
            ContentUnavailableView("スタッフを選択", systemImage: "person.crop.rectangle", description: Text("一覧からスタッフを選んでください。"))
        }
    }
    private func portraitStaffSelector(_ people: [StaffMember]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("スタッフを検索", text: $search).textFieldStyle(.roundedBorder)
                Button("新規登録") { showAdd = true }.modifier(AppActionStyle())
                Button("部署管理") { showDepartmentManager = true }.modifier(AppActionStyle())
            }
            HStack {
                Picker("部署", selection: $selectedDepartment) {
                    ForEach(departments, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
                Picker("勤務状態", selection: $staffStatusFilter) {
                    ForEach(staffStatusOptions, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
            }
            Picker("スタッフ", selection: Binding<UUID?>(
                get: { selectedStaffID },
                set: { if let id = $0 { requestStaffAction(.select(id)) } }
            )) {
                Text("スタッフを選択").tag(nil as UUID?)
                if let editing = inlineEditing, !people.contains(where: { $0.id == editing.id }) {
                    Text(editing.name + "（編集中）").tag(Optional(editing.id))
                }
                ForEach(people) { person in Text(person.name + "・" + person.department).tag(Optional(person.id)) }
            }.pickerStyle(.menu)
            if let person = inlineEditing ?? store.selectedStaff.first(where: { $0.id == selectedStaffID }) {
                HStack(spacing: 10) {
                    if let data = person.photoData {
                        AsyncStaffPortrait(data: data).frame(width: 40, height: 40).clipShape(Circle())
                    }
                    Text(person.name + "・" + person.department).font(.headline).lineLimit(1)
                }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func reconcileStaffSelection(_ ids: [UUID]) {
        guard inlineEditing == nil else { return }
        if let selectedStaffID, ids.contains(selectedStaffID) { return }
        selectedStaffID = ids.first
    }
    private func staffSelectionColor(_ staff: StaffMember) -> Color {
        usesInlineStaffLayout && selectedStaffID == staff.id ? .accentColor : Color.gray.opacity(0.15)
    }

    private func mobileStaffList(_ people: [StaffMember]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("スタッフ名・部署・雇用形態で検索", text: $search)
                        .textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                        }.accessibilityLabel("検索をクリア")
                    }
                }.frame(minHeight: 44)
                HStack {
                    Button { showAdd = true } label: { Label("新規登録", systemImage: "plus") }
                        .modifier(AppActionStyle(prominent: true))
                    Spacer(minLength: 0)
                    Button("部署管理") { showDepartmentManager = true }.modifier(AppActionStyle())
                }
                (workspaceAppearance.isDesktop ? AnyLayout(HStackLayout(alignment: .top, spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))) {
                Picker("勤務状態", selection: $staffStatusFilter) {
                    ForEach(staffStatusOptions, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
                Picker("所属部署", selection: $selectedDepartment) {
                    ForEach(departments, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
                }
                DisclosureGroup(workspaceAppearance.isDesktop ? "勤務地・最低時給の設定" : "勤務地・最低時給") {
                    Picker("勤務地の都道府県", selection: $wagePrefecture) {
                        ForEach(prefectures, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: wagePrefecture) { _, value in
                        UserDefaults.standard.set(value, forKey: "hotelShift.wagePrefecture")
                    }
                    Text("最低時給 ¥\(currentMinimumWage)").font(.subheadline)
                }
                Text("スタッフ \(people.count)名").font(.headline)
                if people.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
                ForEach(people) { staff in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { openStaffDetail(staff) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                if let data = staff.photoData {
                                    AsyncStaffPortrait(data: data).frame(width: 44, height: 44).clipShape(Circle())
                                } else {
                                    Image(systemName: "person.crop.circle.fill").font(.largeTitle)
                                        .foregroundStyle(avatarColor(for: staff.department))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(staff.name).font(.headline)
                                    Text(staff.department + "・" + staff.employment).font(.subheadline).foregroundStyle(.secondary)
                                    Text("時給 ¥\(staff.hourlyWage.formatted())").font(.subheadline)
                                    Text(staff.isActive ? "勤務可能" : "休止中").font(.caption)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }.padding(.trailing, workspaceAppearance.isDesktop ? 40 : 0)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityHint("スタッフ詳細を開きます")
                        if !workspaceAppearance.isDesktop {
                        Menu {
                            Button("情報を編集") { requestStaffEdit(staff) }
                            Button(staff.isActive ? "休止中に変更" : "勤務可能に戻す") { changingStatusStaff = staff }
                            Button("スタッフを削除", role: .destructive) { deletingStaff = staff }
                        } label: { Label("操作", systemImage: "ellipsis").frame(minHeight: 44) }
                        }
                    }
                    .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(staffSelectionColor(staff), lineWidth: selectedStaffID == staff.id ? 2 : 1))
                    .overlay(alignment: .bottomTrailing) {
                        if workspaceAppearance.isDesktop {
                            Button(role: .destructive) { deletingStaff = staff } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .medium))
                                    .frame(width: 32, height: 32)
                                    .foregroundStyle(.red)
                                    .background(Circle().strokeBorder(Color.red, lineWidth: 1))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(staff.name)を削除")
                            .help("スタッフを削除")
                            .padding(12)
                        }
                    }
                }
            }.padding(12)
        }.scrollDismissesKeyboard(.interactively)
    }

    private func currentStaff(_ staff: StaffMember) -> StaffMember {
        store.data.staff.first(where: { $0.id == staff.id }) ?? staff
    }

    private func renameDepartment() {
        guard let oldName = departmentToEdit else { return }
        let newName = editedDepartmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, !allDepartments.contains(newName) || newName == oldName else { return }
        if let index = builtInDepartments.firstIndex(of: oldName) {
            builtInDepartments[index] = newName
            UserDefaults.standard.set(builtInDepartments, forKey: "hotelShift.standardDepartments")
        }
        if let index = customDepartments.firstIndex(of: oldName) { customDepartments[index] = newName }
        if !builtInDepartments.contains(newName) && !customDepartments.contains(newName) { customDepartments.append(newName) }
        customDepartments.sort()
        UserDefaults.standard.set(customDepartments, forKey: "hotelShift.customDepartments")
        var updated = store.data
        for index in updated.staff.indices where updated.staff[index].department == oldName { updated.staff[index].department = newName }
        store.data = updated
        if selectedDepartment == oldName { selectedDepartment = newName }
        departmentToEdit = nil
    }

    private func addDepartment() {
        let name = newDepartment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !allDepartments.contains(name) else { return }
        customDepartments.append(name); customDepartments.sort()
        UserDefaults.standard.set(customDepartments, forKey: "hotelShift.customDepartments")
        newDepartment = ""
    }

    private func avatarColor(for department: String) -> Color {
        switch department {
        case "フロント": return Color(red: 0.24, green: 0.52, blue: 0.87)
        case "レストラン", "調理": return Color(red: 0.20, green: 0.66, blue: 0.48)
        case "清掃", "ハウスキーピング": return Color(red: 0.92, green: 0.62, blue: 0.25)
        default: return Color(red: 0.57, green: 0.48, blue: 0.82)
        }
    }
}

struct StaffDetailSheet: View {
    @Environment(\.workspaceAppearance) private var workspaceAppearance
    @EnvironmentObject private var store: ShiftStore
    private let initialStaff: StaffMember
    private var staff: StaffMember { latestStaff ?? initialStaff }
    var referenceDate: Date = Date()
    let embedded: Bool
    let onEdit: () -> Void
    let onChangeStatus: (StaffMember) -> Void
    @Environment(\.dismiss) private var dismiss
    private struct PendingPersonalTime {
        let item: PersonalWorkTime
        let date: Date
        let staff: StaffMember
        let assignment: ShiftAssignment?
        let hasLeave: Bool
    }
    @State private var personalApplyDate = Date()
    @State private var applyDateInitialized = false
    @State private var pendingPersonalTime: PendingPersonalTime?
    @State private var editingDates: StaffMember?
    @State private var applyingPattern: ShiftPattern?
    @State private var pendingPatternEdit: ShiftPattern?
    @State private var applicationError: String?
    @State private var selectedTab: DetailTab = .basic
    @State private var editingTime: PersonalWorkTime?
    @State private var deletingTime: PersonalWorkTime?
    @State private var deletingTimeLocationID: UUID?
    @State private var timeDeleteError: String?
    @State private var editingWeekly: ShiftPattern?
    @State private var deletingWeekly: ShiftPattern?
    @State private var editingLimited: ShiftPattern?
    @State private var deletingLimited: ShiftPattern?
    private let navy = Color(red: 0.055, green: 0.15, blue: 0.27)
    private var latestStaff: StaffMember? {
        store.data.staff.first { $0.id == initialStaff.id && $0.locationID == initialStaff.locationID && $0.locationID == store.selectedLocationID }
    }

    init(staff: StaffMember, referenceDate: Date = Date(), embedded: Bool = false, onEdit: @escaping () -> Void,
         onChangeStatus: @escaping (StaffMember) -> Void) {
        self.initialStaff = staff; self.referenceDate = referenceDate; self.embedded = embedded
        self.onEdit = onEdit; self.onChangeStatus = onChangeStatus
    }

    private enum DetailTab: String, CaseIterable, Identifiable {
        case basic = "基本情報"
        case personal = "個人の時間"
        case weekly = "週間パターン"
        case limited = "期間限定パターン"
        var id: String { rawValue }
        var phoneTitle: String {
            switch self {
            case .basic: return "基本情報"
            case .personal: return "個人時間"
            case .weekly: return "週間"
            case .limited: return "期間限定"
            }
        }
        var symbol: String {
            switch self {
            case .basic: return "person.text.rectangle"
            case .personal: return "clock"
            case .weekly: return "calendar"
            case .limited: return "calendar.badge.clock"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        Group {
                            if let data = staff.photoData, let image = StaffPhotoDecodeCache.image(from: data) {
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: 76, height: 76).clipShape(Circle())
                            } else {
                                Circle().fill(Color.blue.opacity(0.12)).frame(width: 76, height: 76)
                                    .overlay(Text(String(staff.name.prefix(1)))
                                        .font(.system(size: 28, weight: .bold)).foregroundStyle(.blue))
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(staff.name).font(.title2.bold()).foregroundStyle(navy)
                            Text(staff.department).foregroundStyle(.secondary)
                            Text(staff.isActive ? "勤務可能" : "休止中")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background((staff.isActive ? Color.green : Color.gray).opacity(0.12), in: Capsule())
                        }
                        Spacer(minLength: 0)
                    }
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        Picker("スタッフ詳細", selection: $selectedTab) {
                            ForEach(DetailTab.allCases) { tab in
                                Text(tab.phoneTitle).tag(tab).accessibilityLabel(tab.rawValue)
                            }
                        }.modifier(PhoneTabStyle())
                    } else {
                    // A two-column tab grid keeps labels legible on narrow iPad windows.
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(DetailTab.allCases) { tab in
                            Button { selectedTab = tab } label: {
                                Label(tab.rawValue, systemImage: tab.symbol)
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(2).minimumScaleFactor(0.9)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .padding(.horizontal, 6)
                                    .background(selectedTab == tab ? Color.blue.opacity(0.14) : Color(.secondarySystemGroupedBackground),
                                                in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(selectedTab == tab ? Color.blue : Color.primary)
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                        }
                    }
                    }
                    Group {
                        switch selectedTab {
                        case .basic:
                            VStack(spacing: 0) {
                                detailRow("氏名", staff.name)
                                Divider()
                                detailRow("所属部署", staff.department)
                                Divider()
                                detailRow("雇用形態", staff.employment)
                                Divider()
                                detailRow("時給", "¥\(staff.hourlyWage.formatted())")
                                Divider()
                                detailRow("勤務状態", staff.isActive ? "勤務可能" : "休止中")
                                Divider()
                                detailRow("入社日", staff.joinDate ?? "未設定")
                                Divider()
                                detailRow("退職日", staff.leaveDate ?? "未設定")
                                if !store.wageHistory(for: staff.id).isEmpty {
                                    Divider()
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("時給変更履歴").font(.headline)
                                        ForEach(store.wageHistory(for: staff.id)) { change in
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(change.changedAt.formatted(date: .abbreviated, time: .shortened))
                                                    .font(.caption).foregroundStyle(.secondary)
                                                Text("¥\(change.previousHourlyWage.formatted()) → ¥\(change.newHourlyWage.formatted())")
                                                    .font(.subheadline.monospacedDigit())
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        Text("履歴導入以前の時給変更は表示されません。")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }.padding(.top, 8)
                                }
                            }
                            .padding(16)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                            (workspaceAppearance.isDesktop ? AnyLayout(HStackLayout(alignment: .center, spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))) {
                            Button { editingDates = latestStaff } label: {
                                Label("入社日・退職日を編集", systemImage: "calendar")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }.modifier(AppActionStyle())
                            Button(action: onEdit) {
                                Label("スタッフ情報を編集", systemImage: "pencil")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .padding(workspaceAppearance.isDesktop ? 0 : 16)
                            }.modifier(AppActionStyle(prominent: true))
                            if let current = latestStaff {
                                Button {
                                    onChangeStatus(current)
                                } label: {
                                    Label(current.isActive ? "休止中に変更" : "勤務可能に戻す",
                                          systemImage: current.isActive ? "pause.circle" : "play.circle")
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .modifier(AppActionStyle())
                            }
                            }
                            if latestStaff != nil {
                                Text("勤務状態の変更では、過去のシフト・希望休・勤務パターンは削除されません。")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        case .personal:
                            personalTimePanel
                        case .weekly:
                            weeklyPatternPanel
                        case .limited:
                            limitedPatternPanel
                        }
                    }
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("スタッフ詳細").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } }
                }
            }
            .sheet(item: $editingDates) { person in
                StaffEmploymentDatesEditor(original: person).environmentObject(store)
            }
            .sheet(item: $applyingPattern, onDismiss: {
                if let pattern = pendingPatternEdit { pendingPatternEdit = nil; editingLimited = pattern }
            }) { pattern in
                ShiftPatternApply(pattern: pattern, month: Calendar.current.startOfMonth(for: referenceDate), initialRange: nil,
                    editConflictingPattern: { id, _ in
                        guard let target = store.selectedPatterns.first(where: { $0.id == id && $0.staffID == staff.id && $0.scope == .seasonal }) else {
                            applicationError = "このスタッフ以外の競合は、シフト画面のパターン管理で確認してください。"; return
                        }
                        pendingPatternEdit = target; applyingPattern = nil
                    }, apply: { from, until in store.applyPatternWithReport(pattern, from: from, through: until) })
                    .environmentObject(store)
            }
            .alert("パターンを確認してください", isPresented: Binding(get: { applicationError != nil }, set: { if !$0 { applicationError = nil } })) {
                Button("OK") { applicationError = nil }
            } message: { Text(applicationError ?? "") }
            .onAppear { if !applyDateInitialized { personalApplyDate = referenceDate; applyDateInitialized = true } }
            .confirmationDialog("個人の勤務時間を適用しますか？", isPresented: Binding(get: { pendingPersonalTime != nil }, set: { if !$0 { pendingPersonalTime = nil } }), titleVisibility: .visible) {
                Button("確認した勤務時間を適用", role: pendingPersonalTime?.hasLeave == true ? .destructive : nil) {
                    defer { pendingPersonalTime = nil }
                    guard let pending = pendingPersonalTime else { return }
                    do {
                        try store.applyStaffPersonalTime(pending.item, date: pending.date, expectedStaff: pending.staff,
                                                         expectedAssignment: pending.assignment, allowLeave: pending.hasLeave)
                    } catch { applicationError = error.localizedDescription }
                }
                Button("キャンセル", role: .cancel) { pendingPersonalTime = nil }
            } message: {
                if let pending = pendingPersonalTime {
                    Text("\(staff.name)・\(ScheduleGridSupport.dateLabel(pending.date))の勤務を\(timeLabel(pending.item.startMinutes))〜\(timeLabel(pending.item.endMinutes))、休憩\(pending.item.breakMinutes)分にします。" + (pending.assignment == nil ? "" : "既存の勤務を変更します。") + (pending.hasLeave ? "承認済みの希望休と重複します。" : ""))
                }
            }
            .onChange(of: store.selectedLocationID) { _, _ in if !embedded { dismiss() } }
            .sheet(item: $editingTime) { item in
                PersonalWorkTimeEditor(item: item).environmentObject(store)
            }
            .sheet(item: $editingWeekly) { pattern in
                ShiftPatternEditor(pattern: pattern, lockedStaffID: staff.id).environmentObject(store)
            }
            .sheet(item: $editingLimited) { pattern in
                ShiftPatternEditor(pattern: pattern, lockedStaffID: staff.id).environmentObject(store)
            }
            .alert("期間限定パターンを削除しますか？", isPresented: Binding(
                get: { deletingLimited != nil }, set: { if !$0 { deletingLimited = nil } })) {
                Button("キャンセル", role: .cancel) { deletingLimited = nil }
                Button("削除", role: .destructive) {
                    if let pattern = deletingLimited { _ = store.deletePatternSafely(pattern) }
                    deletingLimited = nil
                }
            } message: { Text("保存済みの期間限定パターンだけを削除します。既存のシフトは変更されません。") }
            .alert("週間パターンを削除しますか？", isPresented: Binding(
                get: { deletingWeekly != nil }, set: { if !$0 { deletingWeekly = nil } })) {
                Button("キャンセル", role: .cancel) { deletingWeekly = nil }
                Button("削除", role: .destructive) {
                    if let pattern = deletingWeekly { _ = store.deletePatternSafely(pattern) }
                    deletingWeekly = nil
                }
            } message: { Text("保存済みの週間パターンだけを削除します。既存のシフトは変更されません。") }

            .alert("この勤務時間を削除しますか？", isPresented: Binding(
                get: { deletingTime != nil }, set: { if !$0 { deletingTime = nil } })) {
                Button("キャンセル", role: .cancel) { deletingTime = nil }
                Button("削除", role: .destructive) {
                    if let item = deletingTime {
                        guard deletingTimeLocationID == store.selectedLocationID,
                              store.deletePersonalWorkTimeSafely(item) else {
                            deletingTime = nil
                            deletingTimeLocationID = nil
                            timeDeleteError = "勤務時間またはホテルの情報が変更されました。削除せずに一覧を確認してください。"
                            return
                        }
                    }
                    deletingTime = nil
                    deletingTimeLocationID = nil
                }
            } message: { Text("登録した時間設定を削除します。既存のシフトは変更されません。") }
            .alert("勤務時間を削除できませんでした", isPresented: Binding(
                get: { timeDeleteError != nil }, set: { if !$0 { timeDeleteError = nil } })) {
                Button("OK") { timeDeleteError = nil }
            } message: { Text(timeDeleteError ?? "一覧を確認してください。") }
        }
    }

    // FIXED208: Reuse the existing pattern model and editor so these entries
    // are included in local persistence and JSON backups without a migration.
    private var weeklyPatternPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("週間パターン").font(.headline)
            Text("曜日ごとの勤務をスタッフごとに保存します。保存だけではシフト表へ自動反映されません。適用はシフト画面の「パターン」から行えます。")
                .font(.caption).foregroundStyle(.secondary)
            let patterns = store.selectedPatterns.filter {
                $0.scope == .individual && $0.staffID == staff.id
            }
            if patterns.isEmpty {
                Text("登録された週間パターンはありません。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(patterns) { pattern in
                VStack(alignment: .leading, spacing: 10) {
                    Text(pattern.name).font(.headline)
                    SchedulePatternTimes(pattern: pattern)
                    patternActionButtons(onEdit: { editingWeekly = pattern },
                                         onDelete: { deletingWeekly = pattern })
                    applyPatternButton(pattern)
                }
                Divider()
            }
            Button {
                editingWeekly = ShiftPattern(name: "新しい週間パターン", scope: .individual,
                                             locationID: store.selectedLocationID, staffID: staff.id)
            } label: {
                Label("週間パターンを作成", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity).padding(8)
            }.modifier(AppActionStyle(prominent: true))
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // FIXED209: Seasonal patterns use the same persisted ShiftPattern model.
    // Keep them separate from ordinary weekly patterns for each staff member.
    private var limitedPatternPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("期間限定パターン").font(.headline)
            Text("GW・年末年始など、開始日と終了日を指定して勤務を登録します。通常の週間パターンより優先されますが、保存しただけではシフト表に反映されません。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            let patterns = store.selectedPatterns.filter {
                $0.scope == .seasonal && $0.staffID == staff.id
            }
            if patterns.isEmpty {
                Text("登録された期間限定パターンはありません。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(patterns) { pattern in
                VStack(alignment: .leading, spacing: 10) {
                    Text(pattern.name).font(.headline)
                    if let start = pattern.validFrom, let end = pattern.validUntil {
                        Text("適用期間：\(start.formatted(date: .abbreviated, time: .omitted)) 〜 \(end.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("適用期間が未設定です。編集して日付を指定してください。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    SchedulePatternTimes(pattern: pattern)
                    patternActionButtons(onEdit: { editingLimited = pattern },
                                         onDelete: { deletingLimited = pattern })
                    applyPatternButton(pattern)
                }
                Divider()
            }
            Button {
                let today = Calendar.current.startOfDay(for: Date())
                editingLimited = ShiftPattern(name: "新しい期間限定パターン", scope: .seasonal,
                    locationID: store.selectedLocationID, staffID: staff.id,
                    validFrom: today, validUntil: today)
            } label: {
                Label("期間限定パターンを作成", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity).padding(8)
            }.modifier(AppActionStyle(prominent: true))
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var personalTimePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("個人の時間").font(.headline)
            Text("このスタッフ専用の勤務時間を登録できます。適用日を選び、内容を確認してシフトへ反映します。")
                .font(.caption).foregroundStyle(.secondary)
            DatePicker("適用日", selection: $personalApplyDate, displayedComponents: .date)
            ForEach(store.selectedPersonalWorkTimes.filter { $0.staffID == staff.id }) { item in
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.name).fontWeight(.semibold)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(timeLabel(item.startMinutes))〜\(timeLabel(item.endMinutes)) ・ 休憩\(item.breakMinutes)分")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    patternActionButtons(onEdit: { editingTime = item },
                                         onDelete: { deletingTime = item; deletingTimeLocationID = store.selectedLocationID })
                    Button {
                        guard let person = latestStaff else { return }
                        let hasLeave = store.selectedRequestsUnsorted.contains { $0.staffID == person.id && $0.dateKey == personalApplyDate.shiftDateKey && $0.status == .approved }
                        pendingPersonalTime = PendingPersonalTime(item: item, date: personalApplyDate, staff: person,
                            assignment: store.assignment(staffID: person.id, date: personalApplyDate), hasLeave: hasLeave)
                    } label: {
                        Label("\(ScheduleGridSupport.dateLabel(personalApplyDate))のシフトへ適用", systemImage: "calendar.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.modifier(AppActionStyle(prominent: true)).disabled(!staff.isActive)
                }
                Divider()
            }
            Button {
                editingTime = PersonalWorkTime(staffID: staff.id, locationID: store.selectedLocationID, name: "新しい勤務時間")
            } label: {
                Label("勤務時間を追加", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity).padding(8)
            }.modifier(AppActionStyle(prominent: true))
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // FIXED217: Keep edit/delete actions on their own row in narrow iPad layouts.
    private func patternActionButtons(onEdit: @escaping () -> Void,
                                      onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                Label("編集", systemImage: "pencil")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .modifier(AppActionStyle())
            Button(role: .destructive, action: onDelete) {
                Label("削除", systemImage: "trash")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .modifier(AppActionStyle())
        }
        .labelStyle(.titleAndIcon)
    }

    private func applyPatternButton(_ pattern: ShiftPattern) -> some View {
        Button { applyingPattern = store.selectedPatterns.first { $0.id == pattern.id } } label: {
            Label("シフトへ適用（確認してから登録）", systemImage: "calendar.badge.plus")
                .frame(maxWidth: .infinity, minHeight: 44)
        }.modifier(AppActionStyle(prominent: true)).disabled(!staff.isActive)
    }

    private func timeLabel(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
            + (minutes >= 1440 ? "（翌日）" : "")
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).fontWeight(.semibold) }
            .padding(.vertical, 12)
    }

    private func unavailablePanel(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct PersonalWorkTimeEditor: View {
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.dismiss) private var dismiss
    @State var item: PersonalWorkTime
    @State private var originalItem: PersonalWorkTime?
    @State private var showDiscardConfirmation = false
    @State private var saveError: String? = nil
    @State private var openedLocationID: UUID? = nil

    private var hasUnsavedChanges: Bool { originalItem.map { $0 != item } ?? false }
    private var storedOriginal: PersonalWorkTime? {
        store.selectedPersonalWorkTimes.first(where: { $0.id == item.id })
    }
    private var consistencyError: String? {
        guard openedLocationID == nil || openedLocationID == store.selectedLocationID else {
            return "編集中にホテルが切り替わりました。画面を閉じて開き直してください。"
        }
        guard item.locationID == store.selectedLocationID else { return "別ホテルの勤務時間は保存できません。" }
        guard let member = store.selectedStaff.first(where: { $0.id == item.staffID }) else {
            return "スタッフの所属が変更されたため保存できません。"
        }
        if let original = originalItem, let current = storedOriginal {
            guard original == current else { return "勤務時間が別の操作で更新されました。画面を開き直してください。" }
        } else if originalItem != nil && storedOriginal != nil {
            return "勤務時間が別の操作で追加されました。画面を開き直してください。"
        } else if originalItem != nil && !isNewEntryAtOpen && storedOriginal == nil {
            return "勤務時間が削除されました。画面を開き直してください。"
        }
        if !member.isActive && isNewEntryAtOpen { return "休止中スタッフに勤務時間を新規登録できません。" }
        return nil
    }
    @State private var isNewEntryAtOpen = false
    private var duration: Int { item.endMinutes - item.startMinutes }
    private var validationMessage: String? {
        if item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "勤務時間の名称を入力してください。" }
        if !(0...1439).contains(item.startMinutes) || !(1...2879).contains(item.endMinutes) || duration < 15 {
            return "終了時刻は開始時刻より15分以上後に設定してください。"
        }
        if !(0...180).contains(item.breakMinutes) || item.breakMinutes > duration {
            return "休憩時間は勤務時間以内（最大180分）にしてください。"
        }
        if let consistencyError { return consistencyError }
        return nil
    }
    private func cancelEditing() {
        if hasUnsavedChanges { showDiscardConfirmation = true } else { dismiss() }
    }
    private func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
            + (minutes >= 1440 ? "（翌日）" : "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("勤務時間") {
                    TextField("名称", text: $item.name)
                    VStack(alignment: .leading, spacing: 12) {
                        Stepper("開始：\(clock(item.startMinutes))", value: $item.startMinutes, in: 0...1439, step: 15)
                        Stepper("終了：\(clock(item.endMinutes))", value: $item.endMinutes, in: 15...2879, step: 15)
                        Stepper("休憩：\(item.breakMinutes)分", value: $item.breakMinutes, in: 0...180, step: 15)
                    }
                    .controlSize(.large)
                    Text("終了時刻は翌日まで設定できます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let validationMessage {
                    Section { Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                }
            }
            .navigationTitle("個人の時間")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { cancelEditing() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let validationMessage {
                            saveError = validationMessage
                            return
                        }
                        guard store.savePersonalWorkTimeSafely(item, expectedOriginal: isNewEntryAtOpen ? nil : originalItem) else {
                            saveError = "勤務時間の保存に失敗しました。別の操作による変更がないか確認してください。"
                            return
                        }
                        dismiss()
                    }.disabled(validationMessage != nil)
                }
            }
            .onAppear {
                if originalItem == nil {
                    originalItem = item
                    openedLocationID = store.selectedLocationID
                    isNewEntryAtOpen = storedOriginal == nil
                }
            }
            .alert("保存できませんでした", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) { Button("OK") { saveError = nil } } message: {
                Text(saveError ?? "勤務時間を確認してください。")
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .confirmationDialog("未保存の変更があります", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button("変更を破棄", role: .destructive) { dismiss() }
                Button("編集を続ける", role: .cancel) { }
            } message: { Text("保存していない勤務時間の変更は失われます。") }
        }
    }
}

struct StaffFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var initial: StaffMember? = nil
    var availableDepartments: [String] = ["フロント", "キッチン", "ルームメイク"]
    var minimumWage: Int = 1172
    var showsMinimumWageReference = true
    var embedded = false
    var onClose: (() -> Void)? = nil
    var onDirtyChange: ((Bool) -> Void)? = nil
    var contextWarning: String? = nil
    var onCommit: ((String, String, String, Int, Data?) -> Bool)? = nil
    @State private var commitFailed = false
    var onSave: (String, String, String, Int, Data?) -> Void
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var showImageImporter = false
    @State private var showAvatarCreator = false
    @State private var copiedPhoto = false
    @State private var avatarDraft = StaffAvatarConfiguration()
    @State private var photoError: String?
    @State private var isLoadingPhoto = false
    @State private var photoTask: Task<Void, Never>?
    @State private var photoRequest = UUID()
    @State private var showDeletePhotoConfirm = false
    @State private var showDiscardConfirmation = false
    private struct FormSnapshot: Equatable { let fields: [String]; let photo: Data? }
    @State private var originalSnapshot: FormSnapshot?
    @State private var name = ""
    @State private var department = "フロント"
    @State private var employment = "正社員"
    @State private var wage = "1172"
    @State private var roundUpOnes = false
    private let employments = ["正社員", "アルバイト", "パート", "契約社員", "派遣"]

    private var snapshot: FormSnapshot {
        FormSnapshot(fields: [name, department, employment, wage, String(roundUpOnes)], photo: photoData)
    }
    private var hasUnsavedChanges: Bool { snapshot != originalSnapshot }
    private var wageValue: Int? {
        guard let value = Int(wage), value >= minimumWage, value >= 0, value <= 1_000_000 else { return nil }
        return value
    }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !department.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && wageValue != nil
    }
    private func completeEditing() {
        if embedded { onClose?() } else { dismiss() }
    }
    private func cancelEditing() {
        if hasUnsavedChanges { showDiscardConfirmation = true } else { completeEditing() }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let contextWarning { Section { Text(contextWarning).foregroundStyle(.orange) } }
                Section("スタッフ写真") {
                    if let photoData, let image = StaffPhotoDecodeCache.image(from: photoData) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 84, height: 84).clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().frame(width: 84, height: 84).foregroundStyle(.secondary.opacity(0.6))
                    }
                    PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                        Label(photoData == nil ? "写真を登録" : "写真を変更", systemImage: "photo")
                    }
                    Button { photoError = nil; showAvatarCreator = true } label: {
                        Label("アバターを作成", systemImage: "face.smiling")
                    }
                    Button { pasteStaffImage() } label: {
                        Label("ミー文字・画像を貼り付け", systemImage: "doc.on.clipboard")
                    }
                    Button { photoError = nil; showImageImporter = true } label: {
                        Label("画像ファイルから選択", systemImage: "folder")
                    }
                    if isLoadingPhoto { ProgressView("画像を読み込み中…") }
                    Button {
                        guard let data = photoData, let image = UIImage(data: data), let png = image.pngData() else {
                            photoError = "画像をコピーできませんでした。写真を選び直してください。"; return
                        }
                        UIPasteboard.general.setData(StaffAvatarDrawing.restored(from: data) != nil ? data : png, forPasteboardType: UTType.png.identifier)
                        copiedPhoto = true
                    } label: {
                        Label(copiedPhoto ? "画像をコピーしました" : "画像をコピー", systemImage: "doc.on.doc")
                    }.disabled(photoData == nil || isLoadingPhoto)
                    Button("写真を削除", role: .destructive) { showDeletePhotoConfirm = true }.disabled(photoData == nil)
                    Text("ミー文字はメッセージなどでコピーして貼り付けるか、写真・画像ファイルから選べます。透明な背景も保存されます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                Section("基本情報") {
                    TextField("氏名", text: $name)
                    Picker("部署", selection: $department) { ForEach(Array(Set(availableDepartments + [department])).sorted(), id: \.self) { Text($0) } }
                    Picker("雇用形態", selection: $employment) {
                        ForEach(employments + (employments.contains(employment) ? [] : [employment]), id: \.self) { Text($0) }
                    }
                    if showsMinimumWageReference {
                        HStack { Text("都道府県の最低時給"); Spacer(); Text("¥\(minimumWage.formatted())").fontWeight(.semibold).foregroundStyle(.secondary) }
                    }
                    TextField("時給（円）", text: $wage).keyboardType(.numberPad)
                    if wageValue == nil {
                        Text(showsMinimumWageReference ? "時給は最低時給以上、100万円以下の整数で入力してください。" : "時給は0〜100万円の整数で入力してください。")
                            .font(.caption).foregroundStyle(.red)
                    }
                    Toggle("1円単位を切り上げ（10円単位）", isOn: $roundUpOnes)
                    if roundUpOnes {
                        Text("保存時に10円単位へ切り上げます（例：1,201円 → 1,210円）")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                beginPhotoLoad {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw StaffImageImportError.unreadable
                    }
                    return data
                }
            }.alert("スタッフ写真を削除しますか？", isPresented: $showDeletePhotoConfirm) {
                Button("キャンセル", role: .cancel) { }
                Button("削除", role: .destructive) {
                    cancelPhotoLoad(); photoData = nil; selectedPhoto = nil
                }
            } message: { Text("保存すると、このスタッフの写真が削除されます。") }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { cancelEditing() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard canSave, let entered = wageValue else { return }
                        let finalWage = roundUpOnes ? ((entered + 9) / 10) * 10 : entered
                        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanDepartment = department.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let onCommit {
                            guard onCommit(cleanName, cleanDepartment, employment, finalWage, photoData) else { commitFailed = true; return }
                        } else { onSave(cleanName, cleanDepartment, employment, finalWage, photoData) }
                        completeEditing()
                    }.disabled(!canSave || isLoadingPhoto)
                }
            }.onAppear { guard originalSnapshot == nil else { return }; if let initial { name = initial.name; department = initial.department; employment = initial.employment; wage = String(max(initial.hourlyWage, minimumWage)); photoData = initial.photoData } else { wage = String(minimumWage) }; originalSnapshot = snapshot }
        }
        .sheet(isPresented: Binding(
            get: { showAvatarCreator && UIDevice.current.userInterfaceIdiom == .phone },
            set: { showAvatarCreator = $0 }
        )) { avatarEditor }
        .fullScreenCover(isPresented: Binding(
            get: { showAvatarCreator && UIDevice.current.userInterfaceIdiom != .phone },
            set: { showAvatarCreator = $0 }
        )) { avatarEditor }
        .onChange(of: hasUnsavedChanges) { _, changed in onDirtyChange?(changed) }
        .onChange(of: photoData) { _, _ in copiedPhoto = false }
        .onDisappear { cancelPhotoLoad() }
        .fileImporter(isPresented: $showImageImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                beginPhotoLoad {
                    try await Task.detached(priority: .userInitiated) {
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        return try Data(contentsOf: url, options: .mappedIfSafe)
                    }.value
                }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { photoError = "画像ファイルを開けませんでした。" }
            }
        }
        .alert(commitFailed ? "スタッフ情報を保存できません" : "画像を登録できません", isPresented: Binding(
            get: { photoError != nil || commitFailed },
            set: { if !$0 { photoError = nil; commitFailed = false } }
        )) {
            Button("OK") { photoError = nil; commitFailed = false }
        } message: { Text(commitFailed ? "店舗やスタッフ情報が変更されたか、保存が制限されています。変更内容は保持しています。キャンセルして最新情報を確認してください。" : (photoError ?? "")) }
        .interactiveDismissDisabled(hasUnsavedChanges)
        .confirmationDialog("未保存の変更があります", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("変更を破棄", role: .destructive) { completeEditing() }
            Button("編集を続ける", role: .cancel) { }
        } message: { Text("保存していないスタッフ情報や写真の変更は失われます。") }
        .presentationDetents(UIDevice.current.userInterfaceIdiom == .phone ? [.large] : [.medium, .large])
    }
    private var avatarEditor: some View {
        StaffAvatarCreator(initial: avatarDraft, sourcePhoto: photoData) { configuration, imageData in
            cancelPhotoLoad(); selectedPhoto = nil
            avatarDraft = configuration; photoData = imageData
        }
    }
    private enum StaffImageImportError: Error { case unreadable }
    private func cancelPhotoLoad() {
        photoRequest = UUID()
        photoTask?.cancel(); photoTask = nil; isLoadingPhoto = false
    }
    @MainActor private func pasteStaffImage() {
        // Read the clipboard only following the user's explicit paste action.
        let pasteboard = UIPasteboard.general
        let imageTypes: [UTType] = [.png, .jpeg, .heic, .tiff, .gif, .webP]
        let encoded = imageTypes.lazy.compactMap { pasteboard.data(forPasteboardType: $0.identifier) }.first
        if let data = encoded ?? pasteboard.image?.pngData() {
            beginPhotoLoad { data }
        } else {
            photoError = "コピーされた画像が見つかりません。メッセージなどでミー文字を画像としてコピーするか、写真・画像ファイルから選んでください。"
        }
    }
    @MainActor private func beginPhotoLoad(_ load: @escaping () async throws -> Data) {
        cancelPhotoLoad()
        let request = UUID(); photoRequest = request; isLoadingPhoto = true
        photoTask = Task { @MainActor in
            defer {
                if photoRequest == request { isLoadingPhoto = false; selectedPhoto = nil; photoTask = nil }
            }
            do {
                let raw = try await load()
                guard !Task.isCancelled, photoRequest == request else { return }
                let portrait = await Task.detached(priority: .userInitiated) {
                    if let restored = StaffAvatarDrawing.restored(from: raw) { return StaffAvatarDrawing.png(restored) }
                    return ShiftPhotoProcessing.staffPortrait(raw)
                }.value
                guard !Task.isCancelled, photoRequest == request else { return }
                guard let portrait else { throw StaffImageImportError.unreadable }
                photoData = portrait
            } catch {
                if !Task.isCancelled, photoRequest == request {
                    photoError = "画像を読み込めませんでした。別の画像を選ぶか、ミー文字を画像としてコピーし直してください。"
                }
            }
        }
    }

}

struct RequestsView: View {
    @Environment(\.workspaceAppearance) private var workspaceAppearance
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var usesCards: Bool {
        UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }
    @State private var renderCache = ShiftRenderCache()
    @State private var month = Calendar.current.startOfMonth(for: Date())
    @State private var allMonths = false
    @State private var showPhoneFilters = false
    @State private var status: ShiftRequestStatus?
    @State private var department = "すべて"
    @State private var query = ""
    @State private var selected = Set<UUID>()
    @State private var alsoOff = false
    @State private var sortByName = false
    @State private var showingQR = false
    @State private var activeIncoming: IncomingLeaveLink?
    @State private var showingReceive = false
    @State private var showingAdd = false
    @State private var showingImporter = false
    @State private var transferItem: OutputFileItem?
    @State private var reply: RequestReplyDraft?
    @State private var notice: String?
    @State private var error: String?
    @State private var pending: Decision?
    @State private var lastDecisionIDs = Set<UUID>()
    @State private var deletion: ShiftRequest?
    private let navy = Color(red: 0.08, green: 0.17, blue: 0.28)
    private struct Decision {
        var rows: [ShiftRequest]
        var staff: [StaffMember]
        var shifts: [ShiftAssignment]
        var location: UUID
        var status: ShiftRequestStatus
        var alsoOff: Bool
    }
    private func openNextIncoming() {
        guard !showingQR, !showingReceive, !showingAdd, !showingImporter, reply == nil, transferItem == nil,
              pending == nil, deletion == nil, let first = store.incomingRequestLinks.first else { return }
        activeIncoming = first
        showingReceive = true
        store.incomingRequestLinks.removeFirst()
    }
    private var departments: [String] { Array(Set(store.selectedStaff.map(\.department))).sorted() }
    private func person(_ row: ShiftRequest) -> StaffMember? { store.staffMember(id: row.staffID) }
    private struct RequestRenderScope: Hashable {
        let section: String; let month: String; let allMonths: Bool; let department: String
        let query: String; let sortByName: Bool; let status: String?
    }
    private func cachedRows(_ section: String, make: () -> [ShiftRequest]) -> [ShiftRequest] {
        let scope = RequestRenderScope(section: section, month: month.shiftDateKey, allMonths: allMonths,
                                       department: department, query: query, sortByName: sortByName, status: status?.rawValue)
        return renderCache.value(for: ShiftRenderKey(revision: store.pdfRevision, location: store.selectedLocationID, scope: scope), make: make)
    }
    private var scope: [ShiftRequest] {
        cachedRows("scope") {
            let prefix = String(month.shiftDateKey.prefix(7))
            let text = query.trimmingCharacters(in: .whitespaces)
            return store.selectedRequestsUnsorted.filter { row in
                (allMonths || row.dateKey.hasPrefix(prefix)) &&
                (department == "すべて" || person(row)?.department == department) &&
                (text.isEmpty || (person(row)?.name ?? "削除済みスタッフ").localizedStandardContains(text))
            }
        }
    }
    private var rows: [ShiftRequest] {
        cachedRows("rows") {
            scope.filter { status == nil || $0.status == status }.sorted {
                if sortByName {
                    let a = person($0)?.name ?? "", b = person($1)?.name ?? ""
                    if a != b { return a < b }
                }
                if $0.dateKey != $1.dateKey { return $0.dateKey < $1.dateKey }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
    }
    private var chosen: [ShiftRequest] { rows.filter { selected.contains($0.id) } }
    private func shift(_ row: ShiftRequest) -> ShiftAssignment? {
        store.assignment(staffID: row.staffID, dateKey: row.dateKey)
    }
    private func prepare(_ items: [ShiftRequest], status: ShiftRequestStatus) {
        guard !items.isEmpty else { return }
        pending = Decision(rows: items, staff: store.selectedStaff, shifts: store.selectedAssignments, location: store.selectedLocationID, status: status, alsoOff: status == .approved && alsoOff)
    }
    private func decide() {
        guard let action = pending else { return }; pending = nil
        do {
            try store.decideRequestBatch(expected: action.rows, staffSnapshot: action.staff, assignmentSnapshot: action.shifts, locationID: action.location, status: action.status, alsoOff: action.alsoOff)
            selected = []
            lastDecisionIDs = Set(action.rows.map(\.id))
            notice = "\(action.rows.count)件を「\(action.status.rawValue)」に変更しました。" + (action.alsoOff ? "勤務を休みに変更しました。有給・休み・明けは保持します。" : "")
        } catch { self.error = error.localizedDescription }
    }
    private func move(_ offset: Int) { month = Calendar.current.date(byAdding: .month, value: offset, to: month) ?? month; allMonths = false }
    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .phone {
                phoneInbox
            } else {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 14) {
                toolbar
                if !store.incomingRequestLinks.isEmpty {
                    HStack { Text("未確認の申請リンク：\(store.incomingRequestLinks.count)件").font(.footnote); Button("内容を確認") { openNextIncoming() }; Spacer() }
                }
                filters
                (usesCards ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))) {
                    Button { alsoOff.toggle() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: alsoOff ? "checkmark.square.fill" : "square").font(.title3)
                            Text("承認時にシフトも休みにする").font(.system(size: 14, weight: .semibold))
                        }
                    }.buttonStyle(.plain).foregroundStyle(navy)
                    Text("勤務がある日は確認して変更").font(.caption).foregroundStyle(.secondary)
                    if !usesCards { Spacer(minLength: 0) }
                }
                if let notice {
                    HStack { Label(notice, systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(.green); Spacer(); if !lastDecisionIDs.isEmpty { Button("結果の返事") { makeReply(store.selectedRequests.filter { lastDecisionIDs.contains($0.id) }) }.disabled(!store.selectedRequests.contains { lastDecisionIDs.contains($0.id) && $0.status != .pending }) }; Button { self.notice = nil } label: { Image(systemName: "xmark.circle") } }
                }
                table
            }
            .padding(usesCards ? 8 : 16).background(.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(12)))
            .overlay(RoundedRectangle(cornerRadius: workspaceAppearance.radius(12)).stroke(Color.gray.opacity(0.12)))
        }
            }
        }
        .padding(.horizontal, workspaceAppearance.inset(usesCards ? 8 : 18)).padding(.bottom, workspaceAppearance.inset(8))
        .background(workspaceAppearance.background(Color(red: 0.95, green: 0.96, blue: 0.98)))
        .safeAreaInset(edge: .bottom, spacing: 0) { if !chosen.isEmpty { bulkBar } }
        .sheet(isPresented: $showingQR, onDismiss: openNextIncoming) { RequestQRSheet() }
        .sheet(isPresented: $showingReceive, onDismiss: { activeIncoming = nil; openNextIncoming() }) {
            RequestTextImportSheet(initialMonth: month, initialLink: activeIncoming) { target, date in
                store.selectedLocationID = target
                month = Calendar.current.startOfMonth(for: date); allMonths = false; status = .pending
            }
        }
        .sheet(isPresented: $showingAdd, onDismiss: openNextIncoming) {
            let people = store.selectedStaff.filter(\.isActive)
            RequestFormSheet(staff: people) { id, dates, reason in
                guard let person = people.first(where: { $0.id == id }) else { return }
                do { let result = try store.receiveRequestText(expectedStaff: person, dateKeys: dates.map(\.shiftDateKey), reason: reason); notice = "\(result.added)件登録しました。重複\(result.skipped)件は追加していません。" }
                catch { self.error = error.localizedDescription }
            }
        }
        .sheet(item: $reply, onDismiss: openNextIncoming) { RequestReplySheet(draft: $0) }
        .sheet(item: $transferItem, onDismiss: openNextIncoming) { ShareSheet(items: [$0.url]) }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first, let outcome = store.importRequestTransfer(from: url) { notice = "取り込み\(outcome.imported)件、スキップ\(outcome.skipped)件" }
                else { error = "HOTEL SHIFTの申請JSONを選択してください。" }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .alert("確認してください", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .alert("申請の変更を確認", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("キャンセル", role: .cancel) { pending = nil }
            Button("確定") { decide() }
        } message: {
            if let action = pending {
                let working = action.rows.filter { row in action.shifts.contains { $0.staffID == row.staffID && $0.dateKey == row.dateKey && ![.off, .paidLeave, .afterNight].contains($0.type) } }.count
                Text("\(action.rows.count)件を「\(action.status.rawValue)」に変更します。\n" + action.rows.prefix(6).map { "\(person($0)?.name ?? "スタッフ") \($0.dateKey)" }.joined(separator: "\n") + (action.rows.count > 6 ? "\nほか\(action.rows.count - 6)件" : "") + (action.alsoOff ? "\n勤務あり：\(working)件。該当勤務を休みに変更し、時刻を解除します。有給・休み・明けは保持します。" : "\nシフトは変更しません。") + (action.status == .pending ? "\n以前変更した休みのシフトは自動で元に戻りません。" : ""))
            }
        }
        .alert("申請を削除", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
            Button("キャンセル", role: .cancel) { deletion = nil }
            Button("削除", role: .destructive) {
                guard let item = deletion else { return }; deletion = nil
                do { try store.deleteRequestSafely(item); notice = "申請を削除しました。シフトは変更していません。" } catch { self.error = error.localizedDescription }
            }
        } message: { Text("\(deletion.map { (person($0)?.name ?? "スタッフ") + " " + $0.dateKey } ?? "") の申請を削除します。取り消せません。") }
        .onAppear { openNextIncoming() }
        .onReceive(store.$incomingRequestLinks) { links in
            if !links.isEmpty { DispatchQueue.main.async { openNextIncoming() } }
        }
        .onChange(of: rows) { _, newRows in selected.formIntersection(Set(newRows.map(\.id))) }
        .onChange(of: store.selectedLocationID) { _, _ in
            selected = []; lastDecisionIDs = []; pending = nil; deletion = nil; showingReceive = false; showingAdd = false; reply = nil; notice = nil; department = "すべて"; query = ""
        }
    }
    private var phoneInbox: some View {
        VStack(spacing: 0) {
            phoneRequestHeader
            Divider()
            ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                DisclosureGroup("検索・絞り込み", isExpanded: $showPhoneFilters) { filters }
                    .padding(12).background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                Toggle("承認時にシフトも休みにする", isOn: $alsoOff).font(.subheadline)
                if !store.incomingRequestLinks.isEmpty {
                    Button("未確認の申請リンクを確認（\(store.incomingRequestLinks.count)件）") { openNextIncoming() }
                        .frame(minHeight: 44)
                }
                if let notice {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(notice, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        if !lastDecisionIDs.isEmpty {
                            Button("結果の返事") { makeReply(store.selectedRequests.filter { lastDecisionIDs.contains($0.id) }) }
                                .disabled(!store.selectedRequests.contains { lastDecisionIDs.contains($0.id) && $0.status != .pending })
                        }
                        Button("通知を閉じる") { self.notice = nil }
                    }.font(.subheadline)
                }
                HStack {
                    Text("申請 \(rows.count)件").font(.headline)
                    Spacer(minLength: 0)
                    Button(!rows.isEmpty && selected.count == rows.count ? "選択を解除" : "全選択") {
                        if selected.count == rows.count { selected = [] } else { selected = Set(rows.map(\.id)) }
                    }.frame(minHeight: 44).disabled(rows.isEmpty)
                }
                if rows.isEmpty { ContentUnavailableView("申請はありません", systemImage: "tray", description: Text("対象月・絞り込み条件を確認してください。")) }
                ForEach(rows) { row in mobileRequestCard(row) }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }.scrollDismissesKeyboard(.interactively)
        }
    }
    private var phoneRequestHeader: some View {
        HStack(spacing: 4) {
            Menu {
                Button("希望休を登録") { showingAdd = true }
                Button("申請を受け取る") { showingReceive = true }
                Button("申請用QRコード") { showingQR = true }
            } label: {
                Image(systemName: "plus").font(.headline).frame(width: 44, height: 44)
                    .modifier(AppGlassSurface(shape: Circle(), interactive: true))
            }.accessibilityLabel("申請を登録・受け取る")
            Spacer(minLength: 0)
            Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 44) }.accessibilityLabel("前月")
            Text(allMonths ? "全期間" : month.japaneseMonth).font(.headline).lineLimit(1).minimumScaleFactor(0.85)
            Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 44) }.accessibilityLabel("翌月")
            Spacer(minLength: 0)
            Menu {
                Toggle("全期間を表示", isOn: $allMonths)
                Toggle("スタッフ名順", isOn: $sortByName)
                Button("今月へ戻る") { month = Calendar.current.startOfMonth(for: Date()); allMonths = false }
                Divider()
                Button("申請を書き出す") { transferItem = store.exportRequestTransfer().map { OutputFileItem(url: $0) } }
                Button("申請JSONを読み込む") { showingImporter = true }
            } label: {
                Image(systemName: "ellipsis").font(.headline).frame(width: 44, height: 44)
                    .modifier(AppGlassSurface(shape: Circle(), interactive: true))
            }.accessibilityLabel("申請の表示・出力設定")
        }.padding(.horizontal, 8).padding(.vertical, 6).modifier(AppGlassSurface(shape: RoundedRectangle(cornerRadius: 0)))
    }
    private var toolbar: some View {
        VStack(spacing: 10) {
            monthControls.frame(maxWidth: .infinity, alignment: .center)
            if usesCards {
                HStack {
                    Menu("申請の登録・受取", systemImage: "plus.circle") {
                        Button("申請用QRコード") { showingQR = true }
                        Button("申請を受け取る") { showingReceive = true }
                        Button("希望休を登録") { showingAdd = true }
                    }.frame(minHeight: 44)
                    Spacer(minLength: 0)
                    requestOptionsMenu.frame(minHeight: 44)
                }
            } else {
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Color.clear.frame(width: 56, height: 1)
                        entryButtons
                        requestOptionsMenu
                    }.frame(minWidth: geometry.size.width, alignment: .center)
                }
            }.frame(height: 44)
            }
        }
    }
    private var requestOptionsMenu: some View {
                Menu {
                    Toggle("全期間を表示", isOn: $allMonths)
                    Toggle("スタッフ名順", isOn: $sortByName)
                    Button("今月へ戻る") { month = Calendar.current.startOfMonth(for: Date()); allMonths = false }
                    Divider()
                    Button("申請を書き出す") { transferItem = store.exportRequestTransfer().map { OutputFileItem(url: $0) } }
                    Button("申請JSONを読み込む") { showingImporter = true }
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 20) }
                .buttonStyle(RequestActionStyle(color: .blue))
                .accessibilityLabel("表示・申請データ")
    }
    private var monthControls: some View {
        HStack(spacing: 18) {
            Button { move(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("前月")
            Text(allMonths ? "全期間" : month.japaneseMonth).font(.system(size: 21, weight: .bold)).foregroundStyle(navy).fixedSize()
            Button { move(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("翌月")
        }.buttonStyle(.plain).font(.system(size: 20, weight: .medium)).frame(minHeight: 42)
    }
    private var entryButtons: some View {
        HStack(spacing: 10) {
            Button { showingQR = true } label: { Label("申請用QRコード", systemImage: "qrcode").frame(height: 20) }.buttonStyle(RequestActionStyle(color: .blue))
            Button { showingReceive = true } label: { Text("申請を受け取る").frame(height: 20) }.buttonStyle(RequestActionStyle(color: .blue))
            Button { showingAdd = true } label: { Label("希望休を登録", systemImage: "plus").frame(height: 20) }.buttonStyle(RequestActionStyle(color: .blue, filled: true))
        }.font(.system(size: 14, weight: .semibold)).controlSize(.large)
    }
    @ViewBuilder private var filters: some View {
        if usesCards {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("スタッフ名で検索", text: $query).textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                        .accessibilityLabel("検索をクリア")
                }
            }.frame(minHeight: 44)
            HStack {
                Picker("状態", selection: $status) {
                    Text("すべて").tag(nil as ShiftRequestStatus?)
                    ForEach(ShiftRequestStatus.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }.pickerStyle(.menu)
                Spacer(minLength: 0)
                Menu {
                    Button("すべて") { department = "すべて" }
                    ForEach(departments, id: \.self) { value in Button(value) { department = value } }
                } label: { Label(department, systemImage: "line.3.horizontal.decrease").lineLimit(1) }
            }.frame(minHeight: 44)
        } else { wideFilters }
    }
    private var wideFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                filterButton(nil)
                ForEach(ShiftRequestStatus.allCases) { filterButton($0) }
                Divider().frame(height: 28).padding(.horizontal, 6)
                Menu { Button("すべて") { department = "すべて" }; ForEach(departments, id: \.self) { value in Button(value) { department = value } } } label: {
                    HStack { Text("部署：\(department)"); Spacer(); Image(systemName: "chevron.down") }.frame(width: 155).padding(10).background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                }.foregroundStyle(navy)
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("スタッフ名で検索", text: $query).textInputAutocapitalization(.never); if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") } } }.padding(10).frame(width: 225).background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
            }.font(.system(size: 14))
        }
    }
    private func filterButton(_ value: ShiftRequestStatus?) -> some View {
        Button { status = value } label: {
            Text("\(value?.rawValue ?? "すべて")  \(scope.filter { value == nil || $0.status == value }.count)")
                .font(.system(size: 14, weight: .semibold)).frame(minWidth: 95).padding(.vertical, 11)
                .background(status == value ? Color.blue : Color(red: 0.95, green: 0.97, blue: 0.99), in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(status == value ? .white : navy)
        }.buttonStyle(.plain)
    }
    @ViewBuilder private var table: some View {
        if usesCards {
            VStack(spacing: 4) {
                HStack {
                    Text("申請 \(rows.count)件").font(.headline)
                    Spacer()
                    Button(!rows.isEmpty && selected.count == rows.count ? "選択を解除" : "全選択") {
                        if selected.count == rows.count { selected = [] } else { selected = Set(rows.map(\.id)) }
                    }.frame(minHeight: 44).disabled(rows.isEmpty)
                }
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if rows.isEmpty {
                            ContentUnavailableView("申請はありません", systemImage: "tray", description: Text("対象月・状態・部署・名前を確認してください。"))
                        }
                        ForEach(rows) { row in mobileRequestCard(row) }
                    }
                }.scrollDismissesKeyboard(.interactively)
            }.frame(minHeight: 200, maxHeight: .infinity)
        } else { wideTable }
    }
    @ViewBuilder private func mobileRequestCard(_ row: ShiftRequest) -> some View {
        if UIDevice.current.userInterfaceIdiom == .phone { phoneRequestCard(row) }
        else { stackedRequestCard(row) }
    }
    private func stackedRequestCard(_ row: ShiftRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Button {
                    if !selected.insert(row.id).inserted { selected.remove(row.id) }
                } label: {
                    Image(systemName: selected.contains(row.id) ? "checkmark.square.fill" : "square")
                        .font(.title3).frame(width: 44, height: 44)
                }.accessibilityLabel("\(person(row)?.name ?? "スタッフ") \(row.dateKey)を選択")
                    .accessibilityValue(selected.contains(row.id) ? "選択済み" : "未選択")
                VStack(alignment: .leading, spacing: 4) {
                    Text(person(row)?.name ?? "削除済みスタッフ").font(.headline)
                    Text(person(row)?.department ?? "").font(.subheadline).foregroundStyle(.secondary)
                    Text(row.dateKey).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            Text(row.reason.isEmpty ? "理由の記載なし" : row.reason).font(.body)
            Text(row.status.rawValue).font(.subheadline.bold()).foregroundStyle(statusColor(row.status))
            shiftBadge(row)
            ViewThatFits(in: .horizontal) {
                HStack { requestActions(row) }
                VStack(alignment: .leading) { requestActions(row) }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(selected.contains(row.id) ? Color.blue.opacity(0.04) : .white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.18)))
    }
    private func phoneRequestCard(_ row: ShiftRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                HStack(alignment: .top, spacing: 4) {
                    Button { if !selected.insert(row.id).inserted { selected.remove(row.id) } } label: {
                        Image(systemName: selected.contains(row.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3).frame(width: 36, height: 44)
                    }.accessibilityLabel("\(person(row)?.name ?? "スタッフ")の申請を選択")
                        .accessibilityValue(selected.contains(row.id) ? "選択済み" : "未選択")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(person(row)?.name ?? "削除済みスタッフ").font(.subheadline.bold())
                        Text(person(row)?.department ?? "").font(.caption).foregroundStyle(.secondary)
                        Text(row.dateKey).font(.caption).monospacedDigit()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    Text(row.reason.isEmpty ? "理由の記載なし" : row.reason).font(.subheadline)
                    Text(row.status.rawValue).font(.caption.bold()).foregroundStyle(statusColor(row.status))
                    shiftBadge(row)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { phoneRequestPills(row) }
                VStack(alignment: .leading, spacing: 8) { phoneRequestPills(row) }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected.contains(row.id) ? Color.blue.opacity(0.04) : .white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15)))
    }
    @ViewBuilder private func phoneRequestPills(_ row: ShiftRequest) -> some View {
        if row.status == .pending {
            Button("承認") { prepare([row], status: .approved) }.tint(.green)
                .modifier(AppActionStyle()).buttonBorderShape(.capsule).frame(minHeight: 44)
            Button("却下") { prepare([row], status: .rejected) }.tint(.red)
                .modifier(AppActionStyle()).buttonBorderShape(.capsule).frame(minHeight: 44)
        } else {
            Button("申請中に戻す") { prepare([row], status: .pending) }
                .modifier(AppActionStyle()).buttonBorderShape(.capsule).frame(minHeight: 44)
            Button("結果の返事") { makeReply([row]) }
                .modifier(AppActionStyle()).buttonBorderShape(.capsule).frame(minHeight: 44)
        }
        Button("削除", role: .destructive) { deletion = row }
            .modifier(AppActionStyle()).buttonBorderShape(.capsule).frame(minHeight: 44)
    }
    @ViewBuilder private func requestActions(_ row: ShiftRequest) -> some View {
        if row.status == .pending {
            Button("却下") { prepare([row], status: .rejected) }.frame(minHeight: 44).modifier(AppActionStyle()).tint(.red)
            Button("承認") { prepare([row], status: .approved) }.frame(minHeight: 44).modifier(AppActionStyle()).tint(.green)
        }
        Menu {
            if row.status != .pending {
                Button("申請中に戻す") { prepare([row], status: .pending) }
                Button("結果の返事") { makeReply([row]) }
            }
            Button("申請を削除", role: .destructive) { deletion = row }
        } label: { Label("その他", systemImage: "ellipsis").frame(minHeight: 44) }
    }
    private var wideTable: some View {
        GeometryReader { geo in
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    tableHeader
                    Divider()
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            if rows.isEmpty {
                                ContentUnavailableView("申請はありません", systemImage: "tray", description: Text("対象月・状態・部署・名前を確認するか、申請を登録してください。" )).frame(minHeight: 220)
                            }
                            ForEach(rows) { row in requestRow(row); Divider().overlay(Color.gray.opacity(0.1)) }
                        }
                    }
                }.frame(width: max(geo.size.width, 950))
            }
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.gray.opacity(0.15)))
        .frame(minHeight: 200, maxHeight: .infinity)
    }
    private var tableHeader: some View {
        HStack(spacing: 0) {
            Button { if selected.count == rows.count { selected = [] } else { selected = Set(rows.map(\.id)) } } label: { Image(systemName: !rows.isEmpty && selected.count == rows.count ? "checkmark.square.fill" : "square") }.frame(width: 46).accessibilityLabel("表示中の申請を全選択・解除")
            Text("スタッフ").frame(width: 155, alignment: .leading)
            Text("希望日").frame(width: 125, alignment: .leading)
            Text("理由").frame(maxWidth: .infinity, alignment: .leading)
            Text("シフト").frame(width: 150)
            Text("状態").frame(width: 100)
            Text("操作").frame(width: 185)
        }.font(.system(size: 14, weight: .semibold)).foregroundStyle(navy).frame(height: 46).background(Color(red: 0.96, green: 0.98, blue: 0.99))
    }
    private func requestRow(_ row: ShiftRequest) -> some View {
        HStack(spacing: 0) {
            Button { if !selected.insert(row.id).inserted { selected.remove(row.id) } } label: { Image(systemName: selected.contains(row.id) ? "checkmark.square.fill" : "square").font(.title3) }.frame(width: 46).accessibilityLabel("\(person(row)?.name ?? "スタッフ") \(row.dateKey)を選択")
            VStack(alignment: .leading, spacing: 3) { Text(person(row)?.name ?? "削除済みスタッフ").fontWeight(.medium); Text(person(row)?.department ?? "").font(.caption).foregroundStyle(.secondary) }.frame(width: 155, alignment: .leading)
            Text(allMonths ? row.dateKey : RequestUIFormat.day(row.dateKey)).monospacedDigit().frame(width: 125, alignment: .leading)
            Text(row.reason).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 8)
            shiftBadge(row).frame(width: 150)
            Text(row.status.rawValue).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 8).background(statusColor(row.status).opacity(0.13), in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(statusColor(row.status)).frame(width: 100)
            HStack(spacing: 6) {
                if row.status == .pending {
                    Button("却下") { prepare([row], status: .rejected) }.buttonStyle(RequestActionStyle(color: .red, compact: true))
                    Button("承認") { prepare([row], status: .approved) }.buttonStyle(RequestActionStyle(color: .green, compact: true))
                }
                Menu {
                    if row.status != .pending { Button("申請中に戻す") { prepare([row], status: .pending) }; Button("結果の返事") { makeReply([row]) } }
                    Button("申請を削除", role: .destructive) { deletion = row }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("申請のその他の操作")
            }.buttonStyle(.plain).font(.system(size: 13)).frame(width: 185)
        }.font(.system(size: 14)).foregroundStyle(navy).padding(.vertical, 13).frame(minHeight: 70).background(selected.contains(row.id) ? Color.blue.opacity(0.025) : .white)
    }
    private func shiftBadge(_ row: ShiftRequest) -> some View {
        VStack(spacing: 4) {
            if let s = shift(row) {
                let working = ![ShiftType.off, .paidLeave, .afterNight].contains(s.type)
                Text(working ? "勤務あり" : s.type.rawValue).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 5).background(working ? Color.red.opacity(0.12) : Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 5)).foregroundStyle(working ? .red : navy)
                if working { Text(RequestUIFormat.time(s)).font(.system(size: 12)).monospacedDigit() }
            } else { Text("未登録").font(.caption).foregroundStyle(.secondary).padding(6).background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 5)) }
        }
    }
    private func statusColor(_ status: ShiftRequestStatus) -> Color { switch status { case .pending: return .orange; case .approved: return .green; case .rejected: return .red } }
    @ViewBuilder private var bulkBar: some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            VStack(spacing: 8) {
                HStack { Text("\(chosen.count)件選択").font(.headline); Spacer(); Button("選択を解除") { selected = [] } }
                HStack {
                    Button("まとめて却下") { prepare(chosen, status: .rejected) }.modifier(AppActionStyle()).tint(.red)
                    Button("まとめて承認") { prepare(chosen, status: .approved) }.modifier(AppActionStyle(prominent: true)).tint(.green)
                }
                Button("結果の返事") { makeReply(chosen) }.disabled(!chosen.contains { $0.status != .pending })
            }.padding(12).frame(maxWidth: .infinity).modifier(AppGlassSurface(shape: RoundedRectangle(cornerRadius: 0)))
        } else { wideBulkBar }
    }
    private var wideBulkBar: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                HStack(spacing: 16.8) {
                    Text("\(chosen.count)件選択").fontWeight(.semibold).fixedSize()
                    Divider().frame(height: 30.8)
                    Button("選択を解除") { selected = [] }
                    Button("まとめて却下") { prepare(chosen, status: .rejected) }
                        .buttonStyle(RequestBulkActionStyle(color: .red))
                    Button("まとめて承認") { prepare(chosen, status: .approved) }
                        .buttonStyle(RequestBulkActionStyle(color: .green))
                    Button("結果の返事") { makeReply(chosen) }
                        .disabled(!chosen.contains { $0.status != .pending })
                }
                .font(.system(size: 16.8))
                .buttonStyle(ScheduleToolbarButtonStyle(scale: 1.4))
                .frame(minWidth: max(0, geometry.size.width - 22.4), alignment: .center)
                .padding(11.2)
            }.scrollIndicators(.visible)
        }
        .frame(height: 64.4)
        .background(Color.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(14)))
        .overlay(RoundedRectangle(cornerRadius: 16.8).stroke(Color.gray.opacity(0.2)))
        .frame(maxWidth: 1064).padding(.horizontal, 14).padding(.bottom, 5.6)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    private func makeReply(_ items: [ShiftRequest]) {
        let decided = items.filter { $0.status != .pending }
        guard !decided.isEmpty else { return }
        reply = RequestReplyDraft(text: RequestInboxTools.reply(staff: store.selectedStaff, requests: decided))
    }
}

private struct RequestBulkActionStyle: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16.8, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14).frame(minHeight: 42)
            .modifier(AppGlassSurface(shape: RoundedRectangle(cornerRadius: 8.4), interactive: true, tint: color))
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
    }
}
private struct RequestActionStyle: ButtonStyle {
    var color: Color
    var filled = false
    var compact = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, compact ? 12 : 16).padding(.vertical, compact ? 8 : 11)
            .foregroundStyle(filled ? Color.white : color)
            .modifier(AppGlassSurface(shape: RoundedRectangle(cornerRadius: 6), interactive: true, tint: filled ? color : nil))
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
    }
}
private enum RequestUIFormat {
    static func day(_ key: String) -> String {
        guard let date = Date.keyFormatter.date(from: key) else { return key }
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "M/d(E)"; return f.string(from: date)
    }
    static func time(_ shift: ShiftAssignment) -> String {
        func clock(_ minutes: Int) -> String { (minutes >= 1440 ? "翌" : "") + String(format: "%d:%02d", (minutes % 1440) / 60, minutes % 60) }
        let starts: [ShiftType: Int] = [.early: 360, .day: 540, .late: 780, .night: 1260]
        let ends: [ShiftType: Int] = [.early: 900, .day: 1080, .late: 1320, .night: 1980]
        return clock(shift.customStartMinutes ?? starts[shift.type] ?? 0) + " – " + clock(shift.customEndMinutes ?? ends[shift.type] ?? 0)
    }
}
private struct RequestReplyDraft: Identifiable { var id = UUID(); var text: String }
private struct RequestReplySheet: View {
    let draft: RequestReplyDraft
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var copied = false
    var body: some View {
        NavigationStack {
            Form {
                Section { TextEditor(text: $text).frame(minHeight: 240) } header: { Text("送る前に文章を編集できます") }
                Section {
                    Button { UIPasteboard.general.string = text; copied = true } label: { Label(copied ? "コピーしました" : "コピー", systemImage: "doc.on.doc") }
                    ShareLink(item: text) { Label("共有", systemImage: "square.and.arrow.up") }
                }
                Text("複数のスタッフを選んだ場合は、宛名ごとに分けた文章になります。送信先に合わせて編集してください。").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("結果の返事").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
                .onAppear { text = draft.text }
        }
    }
}

private struct RequestTextImportSheet: View {
    let initialMonth: Date
    var initialLink: IncomingLeaveLink? = nil
    var onSaved: (UUID, Date) -> Void = { _, _ in }
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.dismiss) private var dismiss
    private enum Mode: String, CaseIterable { case link = "取り込みリンク", text = "文章" }
    @State private var mode: Mode = .link
    @State private var input = ""
    @State private var month = Date()
    @State private var locationID: UUID?
    @State private var staffID: UUID?
    @State private var staffPicked = false
    @State private var locationPicked = false
    @State private var mismatchConfirmed = false
    @State private var excluded = Set<String>()
    @State private var error: String?
    @State private var result: String?
    @State private var savedTarget: (UUID, Date)?
    @State private var discard = false
    @State private var showingRawLink = false
    private var incoming: IncomingLeaveLink? { IncomingLeaveLink.fromText(input) }
    private var fields: RequestInboxTools.Fields? { RequestInboxTools.fields(input) }
    private var sourceStore: String { incoming?.storeName ?? IncomingLeaveLink.storeField(input) }
    private var people: [StaffMember] { store.data.staff.filter { $0.locationID == locationID && $0.isActive } }
    private var parsed: [String] {
        if let incoming { return incoming.dateKeys }
        guard mode == .text else { return [] }
        if let fields { return RequestInboxTools.dates(fields.dates, month: month) }
        guard !input.contains("://") else { return [] }
        return RequestInboxTools.dates(input, month: month)
    }
    private var chosen: [String] { parsed.filter { !excluded.contains($0) } }
    private var wrongStore: Bool {
        guard !sourceStore.isEmpty, let locationID else { return false }
        return !IncomingLeaveLink.matchingLocations(sourceStore, locations: store.data.locations).contains { $0.id == locationID }
    }
    private var canSave: Bool { people.contains(where: { $0.id == staffID }) && !chosen.isEmpty && chosen.count <= 62 && (!wrongStore || mismatchConfirmed) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("受け取り方法", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    if mode == .link && incoming != nil && !showingRawLink {
                        HStack {
                            Label("申請リンクを読み取りました", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                            Button("変更") { showingRawLink = true }
                        }.font(.subheadline)
                    } else {
                        TextField(mode == .link ? "LINEで届いた取り込みリンクを貼り付け" : "名前：山田 太郎\n休みたい日：11/3、11/10〜12\n理由：通院", text: $input, axis: .vertical)
                            .lineLimit(2...4).textInputAutocapitalization(.never).autocorrectionDisabled()
                        if mode == .link && incoming != nil {
                            Button("読み取り結果を表示") { showingRawLink = false }
                        }
                    }
                    PasteButton(payloadType: String.self) { values in Task { @MainActor in input = values.first ?? "" } }
                    if mode == .link && !input.isEmpty && incoming == nil { Text("対応する申請リンクを読み取れません。リンク全体、または申請文を「文章」へ貼り付けてください。").font(.footnote).foregroundStyle(.orange) }
                } header: { Text(mode == .link ? "LINEで届いたリンク" : "届いた文章") } footer: {
                    Text("指定のスマホ申請フォームから届いたリンク・文章に対応します。貼り付けただけでは登録しません。")
                }
                Section {
                    if !sourceStore.isEmpty { LabeledContent("申請の店舗", value: sourceStore) }
                    if let name = incoming?.name ?? fields?.name { LabeledContent("申請者", value: name) }
                    Picker("受け取り店舗", selection: Binding(get: { locationID }, set: { locationID = $0; locationPicked = true; staffID = nil; staffPicked = false; mismatchConfirmed = false; detectStaff() })) {
                        Text("店舗を選んでください").tag(nil as UUID?)
                        ForEach(store.data.locations) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("スタッフ", selection: Binding(get: { staffID }, set: { staffID = $0; staffPicked = true })) {
                        Text("選んでください").tag(nil as UUID?)
                        ForEach(people) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if staffID == nil && !input.isEmpty { Text("対象スタッフを確認して選んでください。同姓同名の場合は自動で選びません。").font(.footnote).foregroundStyle(.orange) }
                    if sourceStore.isEmpty { Text("店舗の指定がありません。受け取り店舗を確認してください。").font(.footnote).foregroundStyle(.secondary) }
                    if wrongStore {
                        Text("申請に書かれた店舗と受け取り先が異なります。").font(.footnote).foregroundStyle(.orange)
                        Toggle("この店舗で受け取ることを確認しました", isOn: $mismatchConfirmed)
                    }
                    if let link = incoming { LabeledContent("理由", value: link.reason.isEmpty ? "記入なし" : link.reason) }
                    else if let fields { LabeledContent("理由", value: fields.reason.isEmpty ? "記入なし" : fields.reason) }
                } header: { Text("読み取った申請・登録先の確認") }
                Section {
                    if incoming == nil { DatePicker("月が省略された日付の対象月", selection: $month, displayedComponents: .date) }
                    if parsed.isEmpty { Text("読み取った希望日をここに表示します。").foregroundStyle(.secondary) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 10) {
                        ForEach(parsed, id: \.self) { dateChip($0) }
                    }
                    Text("日付を押すと対象から外せます。選択中：\(chosen.count)日").font(.footnote).foregroundStyle(.secondary)
                    Text(chosen.joined(separator: "、")).font(.caption).foregroundStyle(.secondary)
                } header: { Text("希望日") }
                Section {
                    Button("確認して承認待ちにする") { save() }.disabled(!canSave)
                } footer: { Text("スタッフ・日付を確認してから登録してください。すでに申請中・承認済みの日は追加しません。") }
            }.navigationTitle("申請を受け取る").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { if input.isEmpty || result != nil { dismiss() } else { discard = true } } } }
                .onAppear {
                    month = initialMonth; locationID = store.selectedLocationID
                    if let initialLink { mode = .link; input = "eldiashift://request#" + initialLink.id; month = initialLink.firstMonth }
                    resolveInput()
                }
                .onChange(of: input) { _, _ in excluded = []; mismatchConfirmed = false; resolveInput() }
                .onChange(of: mode) { _, _ in excluded = []; resolveInput() }
                .onChange(of: month) { _, _ in excluded = [] }
                .onChange(of: store.selectedLocationID) { _, _ in dismiss() }
                .alert("受け取りました", isPresented: Binding(get: { result != nil }, set: { if !$0 { finish() } })) { Button("OK") { finish() } } message: { Text(result ?? "") }
                .alert("確認してください", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }.interactiveDismissDisabled(!input.isEmpty && result == nil)
            .confirmationDialog("入力を破棄して閉じますか？", isPresented: $discard, titleVisibility: .visible) {
                Button("破棄して閉じる", role: .destructive) { dismiss() }
                Button("入力を続ける", role: .cancel) {}
            }
    }
    private func resolveInput() {
        if !locationPicked {
            let matches = IncomingLeaveLink.matchingLocations(sourceStore, locations: store.data.locations)
            locationID = sourceStore.isEmpty ? store.selectedLocationID : (matches.count == 1 ? matches[0].id : nil)
        }
        if !staffPicked { detectStaff() }
    }
    private func detectStaff() {
        staffID = RequestInboxTools.detect(incoming?.name ?? fields?.name ?? input, staff: people)
    }
    private func dateChip(_ key: String) -> some View {
        let off = excluded.contains(key)
        return Button { if off { excluded.remove(key) } else { excluded.insert(key) } } label: {
            Text(RequestUIFormat.day(key)).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(9)
                .background(off ? Color.gray.opacity(0.1) : Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(off ? Color.secondary : Color.blue)
        }.buttonStyle(.plain)
    }
    private func save() {
        guard canSave, let locationID, let person = people.first(where: { $0.id == staffID }) else { return }
        do {
            let outcome = try store.receiveRequestAtLocation(expectedStaff: person, locationID: locationID, dateKeys: chosen, reason: incoming?.reason ?? fields?.reason ?? input)
            savedTarget = (locationID, Date.keyFormatter.date(from: chosen[0]) ?? month)
            result = "\(person.name)さんの\(outcome.added)日を承認待ちにしました。\n申請中・承認済みと重複する\(outcome.skipped)日は追加していません。"
        } catch { self.error = error.localizedDescription }
    }
    private func finish() {
        result = nil; dismiss()
        if let target = savedTarget { savedTarget = nil; onSaved(target.0, target.1) }
    }
}

private struct RequestFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    let staff: [StaffMember]
    let onSave: (UUID, [Date], String) -> Void
    @State private var staffID: UUID?
    @State private var visibleMonth = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDateKeys: Set<String> = [Date().shiftDateKey]
    @State private var reason = "希望休"
    private let reasons = ["希望休", "有給休暇", "勤務変更", "その他"]
    private let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    private var monthDays: [Date?] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: visibleMonth),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth)) else { return [] }
        let offset = calendar.component(.weekday, from: first) - 1
        return Array(repeating: nil, count: offset) + range.compactMap { day in calendar.date(byAdding: .day, value: day - 1, to: first) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("申請内容") {
                    Picker("スタッフ", selection: $staffID) {
                        ForEach(staff) { person in Text(person.name).tag(Optional(person.id)) }
                    }
                    Picker("申請種別", selection: $reason) { ForEach(reasons, id: \.self) { Text($0) } }
                }
                Section("希望日（複数選択可）") {
                    HStack {
                        Button { visibleMonth = Calendar.current.date(byAdding: .month, value: -1, to: visibleMonth) ?? visibleMonth } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Text(visibleMonth.japaneseMonth).font(.headline)
                        Spacer()
                        Button { visibleMonth = Calendar.current.date(byAdding: .month, value: 1, to: visibleMonth) ?? visibleMonth } label: { Image(systemName: "chevron.right") }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                        ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                            Text(day).font(.caption.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        }
                        ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                            if let day {
                                let key = day.shiftDateKey
                                let selected = selectedDateKeys.contains(key)
                                Button {
                                    if selected { selectedDateKeys.remove(key) } else { selectedDateKeys.insert(key) }
                                } label: {
                                    Text(Calendar.current.component(.day, from: day).description)
                                        .font(.system(size: 14, weight: selected ? .bold : .regular))
                                        .frame(maxWidth: .infinity, minHeight: 34)
                                        .background(selected ? Color(red: 0.08, green: 0.17, blue: 0.28) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                        .foregroundStyle(selected ? Color.white : Color.primary)
                                }.buttonStyle(.plain)
                            } else { Color.clear.frame(height: 34) }
                        }
                    }
                    Text("選択中：\(selectedDateKeys.count)日").font(.footnote).foregroundStyle(.secondary)
                }
                Section { Text("登録した申請は「申請中」として保存されます。承認・却下は一覧のメニューから変更できます。複数日を選ぶと、日付ごとに申請が作成されます。").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("申請を登録").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("登録") {
                        if let staffID {
                            let dates = selectedDateKeys.sorted().compactMap { Date.keyFormatter.date(from: $0) }
                            onSave(staffID, dates, reason)
                            dismiss()
                        }
                    }.disabled(staffID == nil || selectedDateKeys.isEmpty)
                }
            }
            .onAppear { if staffID == nil { staffID = staff.first?.id } }
        }.presentationDetents([.medium, .large])
    }
}

struct LaborView: View {
    @Environment(\.workspaceAppearance) private var workspaceAppearance
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var usesCompactLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone ||
        (workspaceAppearance.isDesktop && horizontalSizeClass == .compact)
    }
    @State private var renderCache = ShiftRenderCache()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hotelShift.hotelName") private var hotelName = "ホテル名を設定"
    @AppStorage("hotelShift.hours.early") private var earlyHours = 8
    @AppStorage("hotelShift.hours.day") private var dayHours = 8
    @AppStorage("hotelShift.hours.late") private var lateHours = 8
    @AppStorage("hotelShift.hours.night") private var nightHours = 11
    @State private var selectedMonth = Calendar.current.startOfMonth(for: Date())
    @State private var laborExportItem: OutputFileItem?
    @State private var laborExportError: String?
    @State private var laborExportInProgress = false
    @State private var laborSharedTemporaryURL: URL?
    @State private var laborActiveShareID: UUID?
    @State private var laborShareStatus: String?
    @State private var laborShareWasBackgrounded = false
    @State private var laborTab = "月次"
    @State private var showBudgetEditor = false
    @State private var budgetDraft = ""
    @State private var budgetLocationID: UUID?
    @State private var staffSearchText = ""
    @State private var laborDetailStaffID: UUID? = nil
    @State private var laborDetailLimit = 60
    @State private var laborDetailSearchText = ""
    @State private var showFilteredCSVConfirmation = false
    @State private var pendingFilteredCSV: FilteredCSVRequest?
    @AppStorage("hotelShift.labor.monthlyBudget") private var legacyMonthlyBudget = 2600000
    @AppStorage("hotelShift.labor.monthlyBudgetsByLocation") private var monthlyBudgetsData = Data()
    private var monthlyBudget: Int {
        get { LaborBudgetSettings.value(for: store.selectedLocationID, data: monthlyBudgetsData, legacy: legacyMonthlyBudget) }
        nonmutating set {
            let currentData = UserDefaults.standard.data(forKey: "hotelShift.labor.monthlyBudgetsByLocation") ?? monthlyBudgetsData
            if let data = LaborBudgetSettings.updating(newValue, for: store.selectedLocationID, data: currentData) {
                monthlyBudgetsData = data
            }
        }
    }

    // FIXED250: Treat preparing, presenting and dismissing a share as one busy state.
    // Disable export entry points before building large CSV row arrays.
    private var laborCSVShareIsBusy: Bool {
        laborExportInProgress || laborExportItem != nil ||
            laborSharedTemporaryURL != nil || laborActiveShareID != nil
    }

    // FIXED239: Freeze the export scope when confirmation opens.
    private struct FilteredCSVRequest {
        let locationID: UUID?
        let month: String
        let staffID: UUID?
        let query: String
        let hotelName: String
        let staffName: String
        let rows: [(assignment: ShiftAssignment, staff: StaffMember)]
        let contentSignature: [String]
    }
    // FIXED240: Compare every exported value and stable record identity before sharing.
    // This also detects edits that keep the same number of matching rows.
    private func filteredCSVContentSignature(_ rows: [(assignment: ShiftAssignment, staff: StaffMember)]) -> [String] {
        rows.map { item in
            let assignment = item.assignment
            let staff = item.staff
            let fields = [assignment.id.uuidString, staff.id.uuidString, assignment.dateKey,
                staff.name, staff.department, assignment.type.rawValue,
                String(format: "%.2f", ShiftLaborEstimate.paidHours(assignment)),
                String(assignment.hourlyWageSnapshot ?? staff.hourlyWage),
                assignment.hourlyWageSnapshot == nil ? "legacy" : "snapshot",
                String(ShiftLaborEstimate.cost(assignment, hourlyWage: staff.hourlyWage))]
            return fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        }
    }
    private func prepareFilteredCSV() {
        guard !laborCSVShareIsBusy else {
            laborExportError = "CSVの共有画面を閉じてから、もう一度出力してください。"
            return
        }
        let rows = searchedLaborDetails
        guard !rows.isEmpty else { return }
        pendingFilteredCSV = FilteredCSVRequest(locationID: store.selectedLocationID,
            month: monthPrefix, staffID: laborDetailStaffID,
            query: laborDetailSearchText.trimmingCharacters(in: .whitespacesAndNewlines),
            hotelName: exportHotelName, staffName: filteredCSVStaffName, rows: rows,
            contentSignature: filteredCSVContentSignature(rows))
        showFilteredCSVConfirmation = true
    }
    private var filteredCSVScopeIsCurrent: Bool {
        guard let request = pendingFilteredCSV else { return false }
        return request.locationID == store.selectedLocationID && request.month == monthPrefix &&
            request.staffID == laborDetailStaffID &&
            request.query == laborDetailSearchText.trimmingCharacters(in: .whitespacesAndNewlines) &&
            request.hotelName == exportHotelName &&
            request.contentSignature == filteredCSVContentSignature(searchedLaborDetails)
    }
    private var monthPrefix: String {
        String(selectedMonth.shiftDateKey.prefix(7))
    }
    private func hours(for type: ShiftType) -> Int {
        switch type { case .early: return max(0, earlyHours); case .day: return max(0, dayHours); case .late: return max(0, lateHours); case .night: return max(0, nightHours); default: return 0 }
    }
    private func cost(for assignment: ShiftAssignment) -> Int {
        guard let staff = store.staffMember(id: assignment.staffID) else { return 0 }
        return ShiftLaborEstimate.cost(assignment, hourlyWage: staff.hourlyWage)
    }
    private var monthAssignments: [ShiftAssignment] { store.selectedAssignments(inMonth: monthPrefix) }
    // Build the wage lookup once per summary instead of scanning staff for every shift.
    private func estimate(_ assignments: [ShiftAssignment]) -> Int {
        let wages = Dictionary(uniqueKeysWithValues: store.selectedStaff.map { ($0.id, $0.hourlyWage) })
        return assignments.reduce(0) { total, assignment in
            guard let wage = wages[assignment.staffID] else { return total }
            return total + ShiftLaborEstimate.cost(assignment, hourlyWage: wage)
        }
    }
    // Legacy records without a snapshot use today's wage; the original rate is unknowable.
    private var legacyWageShiftCount: Int {
        monthAssignments.filter { assignment in
            assignment.hourlyWageSnapshot == nil && store.staffMember(id: assignment.staffID) != nil
        }.count
    }
    private var monthEstimate: Int {
        return renderCache.value(for: ShiftRenderKey(revision: store.pdfRevision, location: store.selectedLocationID, scope: "labor|monthEstimate|" + monthPrefix)) {
 estimate(monthAssignments) 
        }
    }
    // FIXED232: Read-only daily detail, including inactive staff and legacy-rate warnings.
    private var laborDailyDetails: [(assignment: ShiftAssignment, staff: StaffMember)] {
        return renderCache.value(for: ShiftRenderKey(revision: store.pdfRevision, location: store.selectedLocationID, scope: "labor|laborDailyDetails|" + monthPrefix)) {

        let staffByID = Dictionary(uniqueKeysWithValues: store.selectedStaff.map { ($0.id, $0) })
        return monthAssignments.compactMap { assignment in
            guard let staff = staffByID[assignment.staffID] else { return nil }
            return (assignment: assignment, staff: staff)
        }.sorted {
            if $0.assignment.dateKey != $1.assignment.dateKey { return $0.assignment.dateKey < $1.assignment.dateKey }
            return $0.staff.name < $1.staff.name
        }
    
        }
    }

    // FIXED233: Detail selection is independent from the summary search.
    private var visibleLaborDetails: [(assignment: ShiftAssignment, staff: StaffMember)] {
        guard let id = laborDetailStaffID else { return laborDailyDetails }
        return laborDailyDetails.filter { $0.staff.id == id }
    }
    // FIXED235: Search only affects on-screen details, never exports or monthly totals.
    private var searchedLaborDetails: [(assignment: ShiftAssignment, staff: StaffMember)] {
        let query = laborDetailSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return visibleLaborDetails }
        return visibleLaborDetails.filter { item in
            item.staff.name.localizedCaseInsensitiveContains(query) ||
            item.staff.department.localizedCaseInsensitiveContains(query) ||
            item.assignment.dateKey.localizedCaseInsensitiveContains(query) ||
            item.assignment.type.rawValue.localizedCaseInsensitiveContains(query)
        }
    }
    // FIXED234: Render detail rows in bounded batches to avoid building hundreds of views at once.
    private var displayedLaborDetails: [(assignment: ShiftAssignment, staff: StaffMember)] {
        Array(searchedLaborDetails.prefix(laborDetailLimit))
    }
    private var visibleLaborDetailCost: Int {
        visibleLaborDetails.reduce(0) { total, item in
            total + ShiftLaborEstimate.cost(item.assignment, hourlyWage: item.staff.hourlyWage)
        }
    }
    private var visibleLaborDetailRecordedCount: Int {
        visibleLaborDetails.filter { $0.assignment.hourlyWageSnapshot != nil }.count
    }
    // FIXED236: Search-only subtotal; do not alter monthly totals or CSV export.
    private var searchedLaborDetailCost: Int {
        searchedLaborDetails.reduce(0) { total, item in
            total + ShiftLaborEstimate.cost(item.assignment, hourlyWage: item.staff.hourlyWage)
        }
    }
    private var searchedLaborDetailRecordedCount: Int {
        searchedLaborDetails.filter { $0.assignment.hourlyWageSnapshot != nil }.count
    }
    private var laborDetailSearchIsActive: Bool {
        !laborDetailSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    @ViewBuilder
    private var laborDetailSearchSummary: some View {
        if laborDetailSearchIsActive {
            VStack(alignment: .leading, spacing: 5) {
                Text("検索結果の小計（画面表示のみ）")
                    .font(.subheadline.weight(.semibold))
                Text("\(searchedLaborDetails.count)件 · 概算 ¥\(searchedLaborDetailCost.formatted())")
                    .font(.subheadline.weight(.semibold))
                Text("時給記録 \(searchedLaborDetailRecordedCount)件 · 旧形式 \(searchedLaborDetails.count - searchedLaborDetailRecordedCount)件")
                    .font(.caption).foregroundStyle(.secondary)
                Text("月間集計・CSV出力には検索条件を適用しません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        }
    }
    @ViewBuilder
    private func laborDetailMetadata(_ assignment: ShiftAssignment, staff: StaffMember, compact: Bool = false) -> some View {
        if compact {
            Text("\(assignment.type.rawValue) · \(String(format: "%.2f時間", ShiftLaborEstimate.paidHours(assignment)))")
            Text("時給 ¥\((assignment.hourlyWageSnapshot ?? staff.hourlyWage).formatted()) · \(assignment.hourlyWageSnapshot == nil ? "旧形式・推定" : "記録済み")")
        } else {
            HStack(spacing: 8) {
                Text(assignment.type.rawValue)
                Text(String(format: "%.2f時間", ShiftLaborEstimate.paidHours(assignment)))
                Text("時給 ¥\((assignment.hourlyWageSnapshot ?? staff.hourlyWage).formatted())")
                Text(assignment.hourlyWageSnapshot == nil ? "旧形式・推定" : "記録済み")
            }
        }
    }
    private var laborDetailSummary: some View {
        HStack(spacing: 12) {
            Text("対象 \(visibleLaborDetails.count)件")
            Text("概算 ¥\(visibleLaborDetailCost.formatted())")
            Text("時給記録 \(visibleLaborDetailRecordedCount)件")
            Text("旧形式 \(visibleLaborDetails.count - visibleLaborDetailRecordedCount)件")
        }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
    private var laborDetailSummaryCompact: some View {
        Group {
            Text("対象 \(visibleLaborDetails.count)件・概算 ¥\(visibleLaborDetailCost.formatted())")
            Text("時給記録 \(visibleLaborDetailRecordedCount)件・旧形式 \(visibleLaborDetails.count - visibleLaborDetailRecordedCount)件")
        }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
    // Weekly threshold alert only; this does not determine statutory overtime pay.
    private var weeklyHourAlerts: [(name: String, week: String, hours: Double)] {
        renderCache.value(for: ShiftRenderKey(revision: store.pdfRevision, location: store.selectedLocationID,
                                             scope: "labor|weeklyHourAlerts|" + monthPrefix)) {
            let weeks = WeeklyLaborSummary.weeks(overlapping: selectedMonth)
            let rows = store.selectedAssignments(on: Set(weeks.keys))
            return WeeklyLaborSummary.alerts(assignments: rows, staff: store.selectedStaff, weeks: weeks)
                .map { (name: $0.name, week: $0.week, hours: $0.hours) }
        }
    }
    private var previousMonthEstimate: Int {
        return renderCache.value(for: ShiftRenderKey(revision: store.pdfRevision, location: store.selectedLocationID, scope: "labor|previousMonthEstimate|" + monthPrefix)) {

        let previous = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM"
        let prefix = f.string(from: previous)
        return estimate(store.selectedAssignments(inMonth: prefix))
    
        }
    }
    private var departmentCosts: [(name: String, cost: Int, shifts: Int)] {
        return renderCache.value(for: ShiftRenderKey(revision: store.pdfRevision, location: store.selectedLocationID, scope: "labor|departmentCosts|" + monthPrefix)) {

        let departmentsByStaff = Dictionary(uniqueKeysWithValues: store.selectedStaff.map { ($0.id, $0.department) })
        let grouped = Dictionary(grouping: monthAssignments) { assignment in
            departmentsByStaff[assignment.staffID] ?? "未分類"
        }
        let wages = Dictionary(uniqueKeysWithValues: store.selectedStaff.map { ($0.id, $0.hourlyWage) })
        return grouped.map { name, assignments in
            let total = assignments.reduce(0) { sum, assignment in
                guard let wage = wages[assignment.staffID] else { return sum }
                return sum + ShiftLaborEstimate.cost(assignment, hourlyWage: wage)
            }
            return (name: name, cost: total, shifts: assignments.count)
        }.sorted { $0.cost > $1.cost }
    
        }
    }
    private var staffMonthlyStats: [(staff: StaffMember, shifts: Int, hours: Double, cost: Int)] {
        return renderCache.value(for: ShiftRenderKey(revision: store.pdfRevision, location: store.selectedLocationID, scope: "labor|staffMonthlyStats|" + monthPrefix)) {

        // FIXED190: Keep zero-paid-hour assignments in the staff breakdown.
        // The department and month views count all registered shifts, so filtering
        // these out made the CSV detail shift counts disagree with the summaries.
        let assignmentsByStaff = Dictionary(grouping: monthAssignments, by: \.staffID)
        // FIXED189: Include inactive staff with historical shifts so detail and CSV totals match the monthly estimate.
        return store.selectedStaff.map { staff in
            let assignments = assignmentsByStaff[staff.id] ?? []
            let totalHours = assignments.reduce(0.0) { $0 + ShiftLaborEstimate.paidHours($1) }
            return (staff: staff, shifts: assignments.count, hours: totalHours, cost: assignments.reduce(0) { $0 + ShiftLaborEstimate.cost($1, hourlyWage: staff.hourlyWage) })
        }.filter { $0.shifts > 0 }.sorted { lhs, rhs in
            if lhs.cost == rhs.cost { return lhs.staff.name < rhs.staff.name }
            return lhs.cost > rhs.cost
        }
    
        }
    }
    private var filteredStaffMonthlyStats: [(staff: StaffMember, shifts: Int, hours: Double, cost: Int)] {
        let query = staffSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return staffMonthlyStats }
        return staffMonthlyStats.filter {
            $0.staff.name.localizedCaseInsensitiveContains(query) ||
            $0.staff.department.localizedCaseInsensitiveContains(query) ||
            $0.staff.employment.localizedCaseInsensitiveContains(query)
        }
    }
    private var yearlyMonthlyCosts: [(month: Int, cost: Int)] {
        return renderCache.value(for: ShiftRenderKey(revision: store.pdfRevision, location: store.selectedLocationID, scope: "labor|yearlyMonthlyCosts|" + monthPrefix)) {

        let year = Calendar.current.component(.year, from: selectedMonth)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM"
        return (1...12).map { month in
            let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? selectedMonth
            let prefix = f.string(from: date)
            let total = store.selectedAssignments(inMonth: prefix).reduce(0) { $0 + cost(for: $1) }
            return (month: month, cost: total)
        }
    
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if usesCompactLayout { phoneLaborHeader } else {
                (usesCompactLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))) {
                    Button { selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth } label: { Image(systemName: "chevron.left").padding(10) }.modifier(AppActionStyle())
                    Text(selectedMonth.japaneseMonth).font(.title3.bold())
                    Button { selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth } label: { Image(systemName: "chevron.right").padding(10) }.modifier(AppActionStyle())
                    if !usesCompactLayout { Spacer() }
                    Text("登録シフトから算出").font(.caption).foregroundStyle(.secondary)
                    Button { budgetLocationID = store.selectedLocationID; budgetDraft = String(max(0, monthlyBudget)); showBudgetEditor = true } label: { Label("予算設定", systemImage: "slider.horizontal.3") }
                        .modifier(AppActionStyle())
                }
                }
                (usesCompactLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))) {
                    laborSummaryCard(title: "予算人件費", value: "¥\(max(0, monthlyBudget).formatted())", caption: "月間予算", icon: "target", tint: .blue)
                    laborSummaryCard(title: "予定", value: "¥\(monthEstimate.formatted())", caption: "登録シフトから算出", icon: "yensign.circle.fill", tint: .green)
                    let balance = monthlyBudget - monthEstimate
                    laborSummaryCard(title: "差額", value: (balance < 0 ? "−" : "") + "¥\(abs(balance).formatted())", caption: balance < 0 ? "予算超過" : "予算残り", icon: balance < 0 ? "arrow.up.right" : "checkmark.circle", tint: balance < 0 ? .red : .orange)
                }
                // Informational note only; no change to existing estimates or controls.
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("人件費は参考目安です")
                            .font(.subheadline.bold())
                        Text("記録済みのシフト時給を優先し、記録のない旧シフトには現在の時給を使用します。実際の給与・人件費とは異なる場合があります。正確な勤怠集計や給与計算が必要な場合は、専門の労務・勤怠管理ソフトをご利用ください。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                if !weeklyHourAlerts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("週40時間を超える予定があります（確認用）", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold()).foregroundStyle(.orange)
                        ForEach(Array(weeklyHourAlerts.enumerated()), id: \.offset) { _, item in
                            Text("\(item.name)　\(item.week)　\(item.hours.formatted(.number.precision(.fractionLength(1))))時間")
                                .font(.caption)
                        }
                        Text("週の区切り・変形労働時間制・休日区分等により法定時間外の判定は異なります。上記は警告表示のみで、追加割増は人件費に加算していません。")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("月間予算の使用率").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(monthlyBudget > 0 ? "\(Int((Double(monthEstimate) / Double(monthlyBudget) * 100).rounded()))%" : "予算未設定")
                            .font(.subheadline.weight(.bold)).monospacedDigit()
                            .foregroundStyle(monthEstimate > monthlyBudget ? .red : .primary)
                    }
                    // The bar stops at 100%; the label above still shows budget overruns.
                    // An unset budget has no meaningful usage ratio.
                    ProgressView(value: monthlyBudget > 0
                                 ? min(1, max(0, Double(monthEstimate) / Double(monthlyBudget)))
                                 : 0, total: 1)
                        .tint(monthEstimate > monthlyBudget ? .red : (monthEstimate >= Int(Double(monthlyBudget) * 0.9) ? .orange : .blue))
                    HStack {
                        Text("\(selectedMonth.japaneseMonth) の予定人件費")
                        Spacer()
                        Text("\(max(0, monthlyBudget - monthEstimate).formatted())円 残り")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(14)))
                if usesCompactLayout {
                    Picker("人件費の表示", selection: $laborTab) {
                        ForEach(["月次", "部門別", "スタッフ別"], id: \.self) { Text($0).tag($0) }
                    }.modifier(PhoneTabStyle())
                } else {
                HStack(spacing: 6) {
                    ForEach(["月次", "部門別", "スタッフ別"], id: \.self) { tab in
                        Button { laborTab = tab } label: {
                            Text(tab).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(laborTab == tab ? Color.blue : Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                                .foregroundStyle(laborTab == tab ? .white : .secondary)
                        }.buttonStyle(.plain)
                    }
                }.padding(5).background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
                if laborTab == "月次" {
                    (usesCompactLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))) {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeading(title: "部署別 人件費比率", subtitle: "\(selectedMonth.japaneseMonth) の予定人件費")
                            if departmentCosts.isEmpty {
                                Text("シフトを登録すると部署別の内訳を表示します").font(.caption).foregroundStyle(.secondary).padding(.vertical, 18)
                            } else {
                                if usesCompactLayout {
                                    VStack(alignment: .leading, spacing: 14) {
                                        ForEach(Array(departmentCosts.enumerated()), id: \.element.name) { index, item in
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack {
                                                    Text(item.name).font(.subheadline)
                                                    Spacer(minLength: 0)
                                                    Text("\(departmentShare(item.cost))%・¥\(shortYen(item.cost))").font(.caption)
                                                }
                                                ProgressView(value: Double(max(0, item.cost)), total: Double(max(1, monthEstimate))).tint(departmentColor(index))
                                            }
                                        }
                                    }
                                } else {
                                (usesCompactLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18)) : AnyLayout(HStackLayout(spacing: 18))) {
                                    ZStack {
                                        Circle().stroke(Color.gray.opacity(0.12), lineWidth: 18)
                                        ForEach(Array(departmentCosts.enumerated()), id: \.element.name) { index, item in
                                            Circle().trim(from: donutStart(index), to: min(0.999, donutStart(index) + donutFraction(item.cost))).stroke(departmentColor(index), style: StrokeStyle(lineWidth: 18, lineCap: .butt)).rotationEffect(.degrees(-90))
                                        }
                                        VStack(spacing: 3) { Text("人件費").font(.caption).foregroundStyle(.secondary); Text(monthEstimate == 0 ? "0%" : "100%").font(.title3.bold()) }
                                    }.frame(width: 126, height: 126)
                                    VStack(alignment: .leading, spacing: 9) {
                                        ForEach(Array(departmentCosts.prefix(5).enumerated()), id: \.element.name) { index, item in
                                            HStack(spacing: 7) { Circle().fill(departmentColor(index)).frame(width: 8, height: 8); Text(item.name).font(.caption).lineLimit(1); Spacer(minLength: 4); Text("\(departmentShare(item.cost))%").font(.caption.weight(.semibold)); Text("¥\(shortYen(item.cost))").font(.caption).foregroundStyle(.secondary) }
                                        }
                                    }
                                }
                                }
                            }
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(16)))
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeading(title: "月別人件費推移", subtitle: "年間の予定額")
                            let values = yearlyMonthlyCosts
                            let maxCost = max(values.map(\.cost).max() ?? 0, 1)
                            HStack(alignment: .bottom, spacing: 5) {
                                ForEach(values, id: \.month) { item in
                                    VStack(spacing: 5) {
                                        RoundedRectangle(cornerRadius: 3).fill(item.month == Calendar.current.component(.month, from: selectedMonth) ? Color(red: 0.10, green: 0.42, blue: 0.91) : Color.blue.opacity(0.35)).frame(height: max(4, CGFloat(item.cost) / CGFloat(maxCost) * 100))
                                        Text("\(item.month)月").font(.system(size: workspaceAppearance.fontSize(9))).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, minHeight: 118, alignment: .bottom)
                                }
                            }
                            Text("前月比：\(deltaText)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(16)))
                    }
                } else if laborTab == "部門別" {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: "部署別人件費", subtitle: "選択月の予定額・勤務人数・勤務回数・構成比")
                        if departmentCosts.isEmpty {
                            Text("対象月のシフトがありません。シフトを登録すると、部署ごとの人件費と勤務状況が表示されます。")
                                .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                        } else {
                            HStack(spacing: 8) {
                                laborMiniMetric(title: "対象部署", value: "\(departmentCosts.count)", suffix: "部署", icon: "building.2")
                                laborMiniMetric(title: "勤務回数", value: "\(monthAssignments.count)", suffix: "回", icon: "calendar")
                                laborMiniMetric(title: "勤務人数", value: "\(Set(monthAssignments.map(\.staffID)).count)", suffix: "名", icon: "person.2")
                            }
                            if usesCompactLayout {
                                ForEach(Array(departmentCosts.enumerated()), id: \.element.name) { index, item in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(item.name).font(.headline)
                                        Text("勤務回数 \(item.shifts)回・構成比 \(departmentShare(item.cost))%")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                        Text("予定人件費 ¥\(item.cost.formatted())").font(.headline).monospacedDigit()
                                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(departmentColor(index).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                }
                                Text("合計 ¥\(monthEstimate.formatted())").font(.headline)
                            } else {
                            HStack {
                                Text("部署・人員").frame(maxWidth: .infinity, alignment: .leading)
                                Text("勤務回数").frame(width: 72, alignment: .trailing)
                                Text("構成比").frame(width: 62, alignment: .trailing)
                                Text("予定人件費").frame(width: 118, alignment: .trailing)
                            }.font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(.vertical, 8)
                            Divider()
                            ForEach(Array(departmentCosts.enumerated()), id: \.element.name) { index, item in
                                let people = Set(monthAssignments.filter { assignment in
                                    (store.staffMember(id: assignment.staffID)?.department ?? "未分類") == item.name
                                }.map(\.staffID)).count
                                VStack(alignment: .leading, spacing: 9) {
                                    HStack(spacing: 8) {
                                        HStack(spacing: 8) {
                                            RoundedRectangle(cornerRadius: 3).fill(departmentColor(index)).frame(width: 5, height: 34)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(item.name).font(.subheadline.weight(.semibold))
                                                Text("勤務スタッフ \(people)名").font(.caption).foregroundStyle(.secondary)
                                            }
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                        Text("\(item.shifts)回").frame(width: 72, alignment: .trailing).monospacedDigit()
                                        Text("\(departmentShare(item.cost))%").frame(width: 62, alignment: .trailing).foregroundStyle(.secondary).monospacedDigit()
                                        Text("¥\(item.cost.formatted())").frame(width: 118, alignment: .trailing).font(.subheadline.weight(.bold)).monospacedDigit()
                                    }
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.gray.opacity(0.12))
                                            Capsule().fill(departmentColor(index)).frame(width: geo.size.width * CGFloat(item.cost) / CGFloat(max(departmentCosts.map(\.cost).max() ?? 1, 1)))
                                        }
                                    }.frame(height: 7)
                                }.padding(.vertical, 9)
                                Divider()
                            }
                            HStack {
                                Text("合計").font(.subheadline.weight(.bold))
                                Spacer()
                                Text("\(monthAssignments.count)回").font(.subheadline.weight(.semibold))
                                Text("100%").frame(width: 62, alignment: .trailing).font(.subheadline.weight(.semibold))
                                Text("¥\(monthEstimate.formatted())").frame(width: 118, alignment: .trailing).font(.subheadline.weight(.bold)).monospacedDigit()
                            }.padding(.top, 4)
                            }
                        }
                    }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(16)))
                }
                if laborTab == "スタッフ別" {
                VStack(alignment: .leading, spacing: 14) {
                    (usesCompactLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center))) {
                        SectionHeading(title: "スタッフ別勤務実績", subtitle: "選択月・勤務区分の標準時間による概算")
                        if !usesCompactLayout { Spacer(minLength: 8) }
                        Button { exportLaborCSV() } label: {
                            Label("CSV出力", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .disabled(staffMonthlyStats.isEmpty || laborCSVShareIsBusy)
                    }
                    if staffMonthlyStats.isEmpty {
                        Text("対象月に勤務シフトが登録されていません。")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("スタッフ名・部署・雇用形態で検索", text: $staffSearchText)
                                .textFieldStyle(.plain)
                            if !staffSearchText.isEmpty {
                                Button { staffSearchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(11)
                        .background(Color.gray.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                        if !usesCompactLayout {
                        HStack {
                            Text("スタッフ・部署")
                            Spacer()
                            Text("回数").frame(width: 46, alignment: .trailing)
                            Text("時間").frame(width: 54, alignment: .trailing)
                            Text("概算人件費").frame(width: 108, alignment: .trailing)
                        }.font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        }
                        if filteredStaffMonthlyStats.isEmpty {
                            Text("検索条件に一致するスタッフがいません。")
                                .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                        }
                        ForEach(filteredStaffMonthlyStats, id: \.staff.id) { item in
                            if usesCompactLayout {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.staff.name).font(.headline)
                                    Text(item.staff.department + (item.staff.isActive ? "" : "・休止中")).font(.subheadline).foregroundStyle(.secondary)
                                    Text("勤務 \(item.shifts)回・" + String(format: "%.2f時間", item.hours)).font(.subheadline)
                                    Text("概算人件費 ¥\(item.cost.formatted())").font(.headline).monospacedDigit()
                                }.padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.staff.name).font(.subheadline.weight(.semibold))
                                    HStack(spacing: 6) {
                                        Text(item.staff.department).font(.caption).foregroundStyle(.secondary)
                                        if !item.staff.isActive {
                                            Text("休止中").font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Color.gray.opacity(0.12), in: Capsule())
                                        }
                                    }
                                }
                                Spacer(minLength: 4)
                                Text("\(item.shifts)").frame(width: 46, alignment: .trailing).monospacedDigit()
                                Text(String(format: "%.2fh", item.hours)).frame(width: 54, alignment: .trailing).monospacedDigit()
                                Text("¥\(item.cost.formatted())").frame(width: 108, alignment: .trailing).font(.subheadline.weight(.semibold)).monospacedDigit()
                            }.padding(.vertical, 7)
                            }
                            Divider()
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("シフト別人件費明細").font(.headline)
                            Text("登録シフトごとの勤務日・適用時給・概算人件費です。旧形式は現在時給による推定です。")
                                .font(.caption).foregroundStyle(.secondary)
                            Picker("明細スタッフ", selection: $laborDetailStaffID) {
                                Text("全スタッフ").tag(nil as UUID?)
                                ForEach(staffMonthlyStats, id: \.staff.id) { item in
                                    Text(item.staff.name).tag(Optional(item.staff.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                TextField("氏名・部署・勤務日・勤務区分で検索", text: $laborDetailSearchText)
                                    .textFieldStyle(.plain)
                                if !laborDetailSearchText.isEmpty {
                                    Button { laborDetailSearchText = "" } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    }.buttonStyle(.plain).accessibilityLabel("明細検索をクリア")
                                }
                            }
                            .padding(11)
                            .background(Color.gray.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                            Text("検索結果 \(searchedLaborDetails.count)件 / 対象 \(visibleLaborDetails.count)件（集計・CSVは検索対象外）")
                                .font(.caption).foregroundStyle(.secondary)
                            ViewThatFits(in: .horizontal) {
                                laborDetailSummary
                                VStack(alignment: .leading, spacing: 5) { laborDetailSummaryCompact }
                            }
                            laborDetailSearchSummary
                            if searchedLaborDetails.isEmpty {
                                Text("表示できるシフト明細がありません。")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                ForEach(displayedLaborDetails, id: \.assignment.id) { detail in
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(detail.assignment.dateKey).font(.caption).foregroundStyle(.secondary)
                                            Text(detail.staff.name).font(.subheadline.weight(.semibold))
                                            if !detail.staff.isActive { Text("休止中").font(.caption2).foregroundStyle(.secondary) }
                                            Spacer(minLength: 4)
                                            Text("¥\(ShiftLaborEstimate.cost(detail.assignment, hourlyWage: detail.staff.hourlyWage).formatted())")
                                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                                        }
                                        ViewThatFits(in: .horizontal) {
                                            laborDetailMetadata(detail.assignment, staff: detail.staff)
                                            VStack(alignment: .leading, spacing: 3) {
                                                laborDetailMetadata(detail.assignment, staff: detail.staff, compact: true)
                                            }
                                        }

                                    }
                                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                }
                                if displayedLaborDetails.count < searchedLaborDetails.count {
                                    Button("さらに表示（残り\(searchedLaborDetails.count - displayedLaborDetails.count)件）") {
                                        laborDetailLimit += 60
                                    }
                                    .modifier(AppActionStyle())
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        Button { prepareFilteredCSV() } label: {
                            Label("表示条件の明細をCSV出力", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .modifier(AppActionStyle())
                        .disabled(searchedLaborDetails.isEmpty || laborCSVShareIsBusy)
                        Text("選択スタッフと文字検索に一致する全明細を出力します。「さらに表示」の件数制限は適用しません。")
                            .font(.caption).foregroundStyle(.secondary)
                        if laborCSVShareIsBusy {
                            Label("CSV共有画面を閉じると、次のCSVを出力できます。", systemImage: "square.and.arrow.up")
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("laborCSVShareBusy")
                        }
                        if let laborShareStatus {
                            Label(laborShareStatus, systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("laborCSVShareStatus")
                        }
                        Button { exportLaborShiftDetailCSV() } label: {
                            Label("シフト別時給・人件費CSV", systemImage: "tablecells")
                        }
                        .modifier(AppActionStyle())
                        .disabled(monthAssignments.isEmpty || laborCSVShareIsBusy)
                        Text("シフトごとの適用時給・時給記録の有無・概算人件費を出力します。月途中の時給変更も行別に確認できます。")
                            .font(.caption).foregroundStyle(.secondary)
                        if legacyWageShiftCount > 0 {
                            Label("対象月に時給記録のない旧シフトが\(legacyWageShiftCount)件あります。これらは現在の時給による概算です。", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        Text("※休止中のスタッフも過去の登録シフトがある場合は集計・CSVに含まれます。勤務回数・時間は登録シフトからの概算であり、実際の打刻時間ではありません。")
                            .font(.caption).foregroundStyle(.secondary)
                        if let warning = workloadWarning {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("勤務量の確認") .font(.subheadline.weight(.semibold))
                                    Text(warning).font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(16)))
                }
                if laborTab == "スタッフ別" {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeading(title: "登録スタッフ", subtitle: "時給設定を確認")
                    ForEach(Array(Set(store.selectedStaff.map(\.department))).sorted(), id: \.self) { department in
                        HStack { Text(department); Spacer(); Text("\(store.selectedStaff.filter { $0.department == department }.count)名").foregroundStyle(.secondary) }
                    }
                }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(16)))
                }
                Text("※予定勤務時間と休憩から、1日8時間超の時間外25%・22〜5時の深夜25%を加算した概算です。週40時間超・法定休日・月60時間超・変形労働時間制などは未対応です。給与確定には利用しないでください。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(workspaceAppearance.inset(usesCompactLayout ? 12 : 24))
        }
        // FIXED248: Keep the temporary source alive when the app moves to the
        // background or this view loses focus. A system share extension may still
        // be reading the file. Cleanup belongs exclusively to sheet dismissal.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && laborActiveShareID != nil {
                laborShareWasBackgrounded = true
            } else if phase == .active && laborShareWasBackgrounded {
                // FIXED249: Returning to the foreground is not an activity result.
                // Do not overwrite a later success/cancel/error callback with a
                // provisional "returned" status. Retain the flag until dismissal.
            }
        }
        .onChange(of: selectedMonth) { _, _ in
            laborDetailLimit = 60
            laborDetailStaffID = nil
        }
        .onChange(of: laborDetailStaffID) { _, _ in laborDetailLimit = 60 }
        .onChange(of: laborDetailSearchText) { _, _ in laborDetailLimit = 60 }
        .onChange(of: store.selectedLocationID) { _, _ in
            laborDetailLimit = 60
            laborDetailStaffID = nil
            laborDetailSearchText = ""
            showBudgetEditor = false
            budgetLocationID = nil
        }
        .confirmationDialog("検索結果CSVの出力確認", isPresented: $showFilteredCSVConfirmation, titleVisibility: .visible) {
            Button("対象 \(pendingFilteredCSV?.rows.count ?? 0)件をCSV出力") {
                guard !laborCSVShareIsBusy else {
                    laborExportError = "CSVの共有画面を閉じてから、もう一度出力してください。"
                    pendingFilteredCSV = nil
                    return
                }
                guard filteredCSVScopeIsCurrent, let request = pendingFilteredCSV else {
                    laborExportError = "確認後にホテル・対象月・検索条件、またはシフト・スタッフ情報が変更されました。もう一度出力内容を確認してください。"
                    pendingFilteredCSV = nil
                    return
                }
                exportFilteredLaborShiftDetailCSV(request)
                pendingFilteredCSV = nil
            }
            .disabled((pendingFilteredCSV?.rows.isEmpty ?? true) || laborCSVShareIsBusy)
            Button("キャンセル", role: .cancel) { pendingFilteredCSV = nil }
        } message: {
            Text("ホテル：\(pendingFilteredCSV?.hotelName ?? exportHotelName)\n対象月：\(pendingFilteredCSV?.month ?? monthPrefix)\nスタッフ：\(pendingFilteredCSV?.staffName ?? "全スタッフ")\n検索：\(pendingFilteredCSV?.query.isEmpty == false ? (pendingFilteredCSV?.query ?? "") : "指定なし")\n出力件数：\(pendingFilteredCSV?.rows.count ?? 0)件\n※画面の60件表示制限に関係なく全件を出力します。")
        }
        .sheet(item: $laborExportItem, onDismiss: {
            // FIXED242: Keep the source file available throughout the share operation.
            // Only delete the temporary source after the activity sheet closes.
            // FIXED243: SwiftUI may clear the sheet item before onDismiss.
            // Keep an independent source URL until dismissal, including cancellation.
            // FIXED244: Clear presentation state before cleaning the completed share.
            // Cleanup is limited to files created inside the app-owned CSV directory.
            // FIXED246: Dismissal can occur without an activity completion callback
            // (for example, interactive dismissal or a presentation interruption).
            if laborShareStatus == nil {
                // FIXED249: No activity callback was delivered. Distinguish an
                // interrupted/backgrounded share from an ordinary dismissal,
                // without claiming that a file was successfully saved.
                laborShareStatus = laborShareWasBackgrounded
                    ? "アプリ復帰後にCSV共有画面が閉じました。保存先をご確認ください。必要なら再出力できます。"
                    : "共有画面を閉じました。保存されたかどうかは保存先をご確認ください。再度CSV出力できます。"
            }
            let completedURL = laborSharedTemporaryURL
            // FIXED247: Invalidate callbacks from a dismissed activity controller.
            laborActiveShareID = nil
            laborShareWasBackgrounded = false
            laborSharedTemporaryURL = nil
            laborExportItem = nil
            if let url = completedURL { removeSharedLaborCSV(at: url) }
        }) { item in
            ShareSheet(items: [item.url], onCompletion: { completed, error in
                // FIXED247: An old share callback must never change a newer share status.
                guard laborActiveShareID == item.id else { return }
                // FIXED246: Activity completion can report an actual system error.
                // Do not equate activity completion with a successful save to Files.
                if let error {
                    laborShareStatus = "共有処理でエラーが発生しました。保存先を確認し、必要ならCSVを再出力してください。"
                    NSLog("HOTEL SHIFT: CSV share failed: %@", String(describing: error))
                } else {
                    laborShareStatus = completed ? "共有操作が完了しました。保存先をご確認ください。" : "共有操作をキャンセルしました。再度CSV出力できます。"
                }
            })
        }
        .alert("CSVを保存できません", isPresented: Binding(
            get: { laborExportError != nil },
            set: { if !$0 { laborExportError = nil } }
        )) {
            Button("OK", role: .cancel) { laborExportError = nil }
        } message: {
            Text(laborExportError ?? "端末の空き容量を確認して再度お試しください。")
        }
        .sheet(isPresented: $showBudgetEditor) {
            NavigationStack {
                Form {
                    Section("月間人件費予算") {
                        HStack {
                            Text("¥")
                            TextField("例：2600000", text: $budgetDraft)
                                .keyboardType(.numberPad)
                        }
                        if LaborBudgetSettings.parse(budgetDraft) == nil {
                            Text("0以上の整数で入力してください。金額が大きすぎる場合も保存できません。")
                                .font(.caption).foregroundStyle(.red)
                        }
                        Text("選択中の店舗に対する月間予算です。保存すると差額カードと予算超過表示に反映されます。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("人件費予算の設定")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { showBudgetEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            guard budgetLocationID == store.selectedLocationID,
                                  let value = LaborBudgetSettings.parse(budgetDraft) else { return }
                            monthlyBudget = value
                            showBudgetEditor = false
                        }.disabled(budgetLocationID != store.selectedLocationID || LaborBudgetSettings.parse(budgetDraft) == nil)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
    private var phoneLaborHeader: some View {
        HStack(spacing: 4) {
            Button { selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 44)
            }.accessibilityLabel("前月")
            Text(selectedMonth.japaneseMonth).font(.headline).lineLimit(1).minimumScaleFactor(0.85)
            Button { selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 44)
            }.accessibilityLabel("翌月")
            Spacer(minLength: 0)
            Button { budgetLocationID = store.selectedLocationID; budgetDraft = String(max(0, monthlyBudget)); showBudgetEditor = true } label: {
                Text("予算設定").font(.caption.bold()).padding(.horizontal, 10).frame(minHeight: 44)
                    .modifier(AppGlassSurface(shape: RoundedRectangle(cornerRadius: 12), interactive: true))
            }.buttonStyle(.plain)
        }
    }
    private func laborMiniMetric(title: String, value: String, suffix: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title2.weight(.bold)).monospacedDigit()
                Text(suffix).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }

    private func laborSummaryCard(title: String, value: String, caption: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: icon).foregroundStyle(tint); Spacer(); Text(title).font(.subheadline).foregroundStyle(.secondary) }
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Color(red: 0.08, green: 0.17, blue: 0.28)).lineLimit(1).minimumScaleFactor(0.65)
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(14)))
    }
    private func departmentColor(_ index: Int) -> Color {
        [Color.blue, Color.green, Color(red: 0.95, green: 0.62, blue: 0.20), Color.purple, Color.pink, Color.cyan][index % 6]
    }
    private func donutFraction(_ cost: Int) -> CGFloat {
        let total = max(departmentCosts.reduce(0) { $0 + $1.cost }, 1)
        return CGFloat(max(0, cost)) / CGFloat(total)
    }
    private func donutStart(_ index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        return departmentCosts.prefix(index).reduce(CGFloat(0)) { $0 + donutFraction($1.cost) }
    }
    private func departmentShare(_ cost: Int) -> Int {
        let total = departmentCosts.reduce(0) { $0 + $1.cost }
        return total == 0 ? 0 : Int((Double(cost) / Double(total) * 100).rounded())
    }
    private var workloadWarning: String? {
        let flagged = staffMonthlyStats.filter { $0.hours >= 160 || $0.shifts >= 22 }
        guard !flagged.isEmpty else { return nil }
        let names = flagged.prefix(3).map { $0.staff.name }.joined(separator: "、")
        let suffix = flagged.count > 3 ? " ほか\(flagged.count - 3)名" : ""
        return "標準時間で月160時間以上、または月22回以上のスタッフがあります：\(names)\(suffix)。実際の勤務時間・休憩・休日を確認してください。この表示は法令違反の判定ではありません。"
    }
    private var filteredCSVStaffName: String {
        guard let id = laborDetailStaffID else { return "全スタッフ" }
        return store.selectedStaff.first(where: { $0.id == id })?.name ?? "選択スタッフ（現在は未登録）"
    }
    // FIXED231: Export one row per actual shift, retaining the rate source.
    // This is an estimate, not a payroll ledger or a historical wage reconstruction.
    // FIXED237: Export the entire filtered result, independent of the 60-row UI pagination.
    // This is separate from the existing monthly detail and summary CSV exports.
    private func exportFilteredLaborShiftDetailCSV(_ request: FilteredCSVRequest) {
        let header = ["ホテル名", "対象月", "勤務日", "スタッフ名", "部署", "勤務区分", "勤務時間（概算）", "適用時給", "時給区分", "概算人件費"]
        let rows: [[String]] = request.rows.map { item in
            let assignment = item.assignment
            let staff = item.staff
            let wage = assignment.hourlyWageSnapshot ?? staff.hourlyWage
            return [request.hotelName, request.month, assignment.dateKey, staff.name, staff.department,
                    assignment.type.rawValue, String(format: "%.2f", ShiftLaborEstimate.paidHours(assignment)),
                    String(wage), assignment.hourlyWageSnapshot == nil ? "旧形式・現在時給で概算" : "シフト保存時の時給",
                    String(ShiftLaborEstimate.cost(assignment, hourlyWage: staff.hourlyWage))]
        }
        let filename = "\(safeFilenamePart(request.hotelName))_検索結果人件費_\(request.month)_\(UUID().uuidString).csv"
        writeLaborCSVRows([header] + rows, filename: filename, errorDescription: "検索結果CSVの保存に失敗しました。端末の空き容量を確認してください。")
    }

    private func exportLaborShiftDetailCSV() {
        let staffByID = Dictionary(uniqueKeysWithValues: store.selectedStaff.map { ($0.id, $0) })
        let header = ["ホテル名", "対象月", "勤務日", "スタッフ名", "部署", "勤務区分", "勤務時間（概算）", "適用時給", "時給区分", "概算人件費"]
        let rows: [[String]] = monthAssignments.sorted {
            if $0.dateKey == $1.dateKey { return $0.staffID.uuidString < $1.staffID.uuidString }
            return $0.dateKey < $1.dateKey
        }.compactMap { assignment in
            guard let staff = staffByID[assignment.staffID] else { return nil }
            let wage = assignment.hourlyWageSnapshot ?? staff.hourlyWage
            return [exportHotelName, monthPrefix, assignment.dateKey, staff.name, staff.department,
                    assignment.type.rawValue, String(format: "%.2f", ShiftLaborEstimate.paidHours(assignment)),
                    String(wage), assignment.hourlyWageSnapshot == nil ? "旧形式・現在時給で概算" : "シフト保存時の時給",
                    String(ShiftLaborEstimate.cost(assignment, hourlyWage: staff.hourlyWage))]
        }
        let filename = "\(safeFilenamePart(exportHotelName))_シフト別人件費_\(monthPrefix)_\(UUID().uuidString).csv"
        writeLaborCSVRows([header] + rows, filename: filename, errorDescription: "CSVの保存に失敗しました。端末の空き容量を確認してください。")
    }
    private func exportLaborCSV() {
        // One CSV contains detail rows first, followed by department and monthly summaries.
        // The first column makes it easy to filter detail vs. summary rows in Excel.
        let header = ["ホテル名", "行種別", "対象月", "スタッフ名", "部署", "雇用形態", "勤務回数", "標準勤務時間", "時給（現在）", "概算人件費", "時給記録済シフト数", "旧形式シフト数"]
        let detailRows = staffMonthlyStats.map { item in
            [exportHotelName, "スタッフ明細", monthPrefix, item.staff.name, item.staff.department, item.staff.employment, String(item.shifts), String(format: "%.2f", item.hours), String(item.staff.hourlyWage), String(item.cost), String(monthAssignments.filter { $0.staffID == item.staff.id && $0.hourlyWageSnapshot != nil }.count), String(monthAssignments.filter { $0.staffID == item.staff.id && $0.hourlyWageSnapshot == nil }.count)]
        }
        let departmentRows = departmentCosts.map { item in
            [exportHotelName, "部署別集計", monthPrefix, "", item.name, "", String(item.shifts), "", "", String(item.cost)]
        }
        let totalShifts = staffMonthlyStats.reduce(0) { $0 + $1.shifts }
        let totalHours = staffMonthlyStats.reduce(0.0) { $0 + $1.hours }
        // FIXED190: Match the detail precision and use the same monthly estimate
        // that is shown in the headline, rather than a separately rounded value.
        let monthlyTotal = [exportHotelName, "月間合計", monthPrefix, "全スタッフ", "全体", "", String(totalShifts), String(format: "%.2f", totalHours), "", String(monthEstimate)]
        let allRows = [header] + detailRows + [[""]] + departmentRows + [[""]] + [monthlyTotal]
        let filename = "\(safeFilenamePart(exportHotelName))_月間勤務実績_\(monthPrefix)_\(UUID().uuidString).csv"
        writeLaborCSVRows(allRows, filename: filename, errorDescription: "CSVの保存に失敗しました。端末の空き容量を確認して再度お試しください。")
    }
    // FIXED241: Write CSV incrementally rather than building one giant CSV string.
    // A partially written file is removed if encoding or disk I/O fails.
    private func writeLaborCSVRows(_ rows: [[String]], filename: String, errorDescription: String) {
        // FIXED242: Do not replace a share sheet's source while it is presented.
        guard !laborExportInProgress, laborExportItem == nil, laborSharedTemporaryURL == nil else {
            laborExportError = "CSVの共有画面を閉じてから、もう一度出力してください。"
            return
        }
        laborExportInProgress = true
        laborShareStatus = nil
        laborShareWasBackgrounded = false
        defer { laborExportInProgress = false }
        let manager = FileManager.default
        let directory = laborCSVDirectory
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            // FIXED244: An interrupted share can leave an orphaned CSV behind.
            // Remove only old exports in this dedicated directory, never a live share.
            removeExpiredLaborCSVFiles(in: directory)
        } catch {
            laborExportError = errorDescription
            NSLog("HOTEL SHIFT: CSV directory unavailable: %@", String(describing: error))
            return
        }
        let url = directory.appendingPathComponent(filename)
        guard manager.createFile(atPath: url.path, contents: nil) else {
            laborExportError = errorDescription
            return
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.write(contentsOf: Data([0xEF, 0xBB, 0xBF]))
            for row in rows {
                let line = row.map { csvEscape($0) }.joined(separator: ",") + "\r\n"
                guard let data = line.data(using: .utf8) else {
                    throw CocoaError(.fileWriteInapplicableStringEncoding)
                }
                try handle.write(contentsOf: data)
            }
            try handle.synchronize()
            // FIXED243: A file must contain the UTF-8 BOM and at least one CSV row.
            let attributes = try manager.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 3 else { throw CocoaError(.fileWriteUnknown) }
            laborExportError = nil
            let exportItem = OutputFileItem(url: url)
            laborActiveShareID = exportItem.id
            laborSharedTemporaryURL = url
            laborExportItem = exportItem
        } catch {
            try? manager.removeItem(at: url)
            laborExportError = errorDescription + " 保存先の空き容量やファイルへのアクセスを確認して、再度お試しください。"
            NSLog("HOTEL SHIFT: CSV write failed: %@", String(describing: error))
        }
    }
    // FIXED244: Isolate temporary wage CSVs from other app exports.
    private var laborCSVDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("HOTEL_SHIFT_Labor_CSV", isDirectory: true)
    }
    private func removeSharedLaborCSV(at url: URL) {
        guard url.deletingLastPathComponent().standardizedFileURL == laborCSVDirectory.standardizedFileURL else { return }
        do { try FileManager.default.removeItem(at: url) }
        catch { NSLog("HOTEL SHIFT: temporary CSV cleanup failed: %@", String(describing: error)) }
    }
    private func removeExpiredLaborCSVFiles(in directory: URL) {
        let manager = FileManager.default
        let expiry = Date().addingTimeInterval(-24 * 60 * 60)
        guard let urls = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        for url in urls where url.pathExtension.lowercased() == "csv" && url != laborSharedTemporaryURL {
            guard let properties = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  properties.isRegularFile == true,
                  let modified = properties.contentModificationDate,
                  modified < expiry else { continue }
            do { try manager.removeItem(at: url) }
            catch { NSLog("HOTEL SHIFT: expired CSV cleanup failed: %@", String(describing: error)) }
        }
    }
    private var exportHotelName: String {
        let trimmed = hotelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "ホテル名未設定" : trimmed
    }
    private func safeFilenamePart(_ value: String) -> String {
        ExportFilename.component(value)
    }
    private func csvEscape(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    private var deltaText: String {
        let difference = monthEstimate - previousMonthEstimate
        if difference == 0 { return "±¥0" }
        return (difference > 0 ? "+¥" : "−¥") + abs(difference).formatted()
    }
    private func shortYen(_ value: Int) -> String {
        if value >= 10000 { return String(format: "%.1f万", Double(value) / 10000) }
        return "\(value)"
    }
}

// FIXED204: Backup and restore is a standalone sidebar destination.
// Keep the destructive confirmation and security-scoped JSON import in one screen.
struct BackupRestoreView: View {
    @Environment(\.workspaceAppearance) private var workspaceAppearance
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var exportItem: OutputFileItem?
    @State private var showBackupImporter = false
    @State private var showRestoreConfirm = false
    @State private var selectedBackupURL: URL?
    @State private var isWorking = false
    @State private var backupMessage = ""
    @State private var temporaryBackup: URL?

    private let ink = Color(red: 0.08, green: 0.16, blue: 0.25)
    private let muted = Color(red: 0.39, green: 0.45, blue: 0.52)
    private let blue = Color(red: 0.12, green: 0.43, blue: 0.91)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ((UIDevice.current.userInterfaceIdiom == .phone || (workspaceAppearance.isDesktop && horizontalSizeClass == .compact)) ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("バックアップを作成", systemImage: "externaldrive.fill").font(.headline).foregroundStyle(ink)
                        Text("現在のデータ全体をJSONファイルとして書き出します。共有画面で「ファイルに保存」などを選択してください。")
                            .font(.subheadline).foregroundStyle(muted)
                        Button {
                            guard !isWorking else { return }
                            isWorking = true
                            Task {
                                if let url = await store.exportBackup() { temporaryBackup = url; exportItem = OutputFileItem(url: url) }
                                else { backupMessage = "バックアップファイルを作成できませんでした。" }
                                isWorking = false
                            }
                        } label: {
                            Label(isWorking ? "処理中…" : "バックアップを作成", systemImage: "square.and.arrow.up.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                        }.modifier(AppActionStyle(prominent: true)).tint(blue)
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(14)))
                    VStack(alignment: .leading, spacing: 14) {
                        Label("バックアップから復元", systemImage: "arrow.clockwise.circle.fill").font(.headline).foregroundStyle(ink)
                        Text("保存したHOTEL SHIFTのJSONファイルを選択します。復元すると現在のデータ全体が置き換わります。")
                            .font(.subheadline).foregroundStyle(muted)
                        Button { showBackupImporter = true } label: {
                            Label("復元ファイルを選択", systemImage: "folder")
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                        }.modifier(AppActionStyle()).tint(blue)
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(14)))
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("復元前に現在のデータをバックアップしてください").font(.subheadline.weight(.semibold))
                        Text("復元は現在のデータ全体を置き換えます。iCloud同期中は共有先にも反映されます。")
                            .font(.caption).foregroundStyle(muted)
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                if !backupMessage.isEmpty {
                    Text(backupMessage).font(.subheadline)
                        .foregroundStyle(backupMessage.contains("成功") ? Color.green : Color.red)
                }
            }
            .padding(workspaceAppearance.inset(UIDevice.current.userInterfaceIdiom == .phone ? 12 : 20)).frame(maxWidth: workspaceAppearance.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(workspaceAppearance.background(Color(red: 0.95, green: 0.965, blue: 0.98)))
        .sheet(item: $exportItem, onDismiss: {
            if let url = temporaryBackup { Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: url) } }
            temporaryBackup = nil
        }) { item in ShareSheet(items: [item.url]) }
        .fileImporter(isPresented: $showBackupImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                selectedBackupURL = urls.first
                if selectedBackupURL != nil { showRestoreConfirm = true }
            case .failure:
                backupMessage = "ファイルを開けませんでした。JSONバックアップを選択してください。"
            }
        }
        .disabled(isWorking)
        .confirmationDialog("現在のデータをバックアップで置き換えますか？", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("復元する", role: .destructive) {
                guard !isWorking else { return }
                let selected = selectedBackupURL
                selectedBackupURL = nil; isWorking = true
                Task {
                    if let url = selected, await store.importBackup(from: url) { backupMessage = "復元に成功しました。" }
                    else { backupMessage = "復元に失敗しました。形式・空き容量を確認し、編集中の場合はもう一度お試しください。" }
                    isWorking = false
                }
            }
            Button("キャンセル", role: .cancel) { selectedBackupURL = nil }
        } message: {
            Text("復元すると現在のスタッフ・シフト・施設データはバックアップの内容に置き換わります。")
        }
    }
}

struct OutputView: View {
    @Environment(\.workspaceAppearance) private var workspaceAppearance
    @EnvironmentObject private var store: ShiftStore
    @State private var exportItem: OutputFileItem?
    @State private var pdfMonth = Calendar.current.startOfMonth(for: Date())
    @State private var showPDFInfo = false
    @State private var selectedTab = 0
    @State private var paperSize = "A4横"
    @State private var periodMode = "1か月"
    @State private var selectedDepartment = "すべて"
    @State private var activePDFPreview: OutputPDFPreviewItem?
    @State private var isGeneratingPDF = false
    @State private var isGeneratingCSV = false
    @State private var csvError: String?
    @State private var pdfGenerationTask: Task<Void, Never>?
    @State private var previewExportItem: OutputFileItem?
    @State private var showStaffName = true
    @State private var showWorkTime = true
    @State private var showBreakTime = true
    @State private var showMemo = true
    @State private var showWage = false

    private let ink = Color(red: 0.08, green: 0.16, blue: 0.25)
    private let muted = Color(red: 0.39, green: 0.45, blue: 0.52)
    private let blue = Color(red: 0.12, green: 0.43, blue: 0.91)

    var body: some View {
        GeometryReader { geometry in
        let stacked = geometry.size.width < 850
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // FIXED204: Backup & Restore has its own sidebar screen.
                if UIDevice.current.userInterfaceIdiom != .phone { outputTabs }
                if selectedTab == 0 {
                    let pdfLayout = workspaceAppearance.isDesktop && !stacked
                        ? AnyLayout(DashboardEqualHeightRow(weights: [320, max(1, geometry.size.width - 336)], spacing: 16))
                        : (stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16)))
                    pdfLayout {
                        VStack(alignment: .leading, spacing: 16) {
                            sectionTitle("出力設定", subtitle: "対象月と帳票の表示内容を設定")
                            VStack(alignment: .leading, spacing: 8) {
                                Text("対象年月").font(.caption.weight(.semibold)).foregroundStyle(muted)
                                HStack(spacing: 0) {
                                    Button { changeMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 40) }.buttonStyle(.plain)
                                    Spacer(minLength: 2)
                                    Text(pdfMonth.japaneseMonth).font(.subheadline.weight(.bold)).monospacedDigit()
                                    Spacer(minLength: 2)
                                    Button { changeMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 40) }.buttonStyle(.plain)
                                }.foregroundStyle(ink).background(Color.white, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.black.opacity(0.1), lineWidth: 1))
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text("用紙レイアウト").font(.caption.weight(.semibold)).foregroundStyle(muted)
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    ForEach(["A4横", "A4縦", "A3横", "A3縦"], id: \.self) { size in paperButton(size) }
                                }
                            }
                            if UIDevice.current.userInterfaceIdiom == .phone {
                                phoneOutputFilters
                                phoneOutputFields(wageTitle: "人件費")
                            } else {
                            outputRangeAndDepartment
                            VStack(alignment: .leading, spacing: 10) {
                                Text("表示項目").font(.caption.weight(.semibold)).foregroundStyle(muted)
                                outputToggle("スタッフ名", isOn: $showStaffName)
                                outputToggle("勤務時間", isOn: $showWorkTime)
                                outputToggle("休憩時間", isOn: $showBreakTime)
                                outputToggle("メモ欄", isOn: $showMemo)
                                outputToggle("人件費", isOn: $showWage)
                            }
                            }
                            if UIDevice.current.userInterfaceIdiom != .phone && !workspaceAppearance.isDesktop {
                            Button {
                                startPDFGeneration(preview: true)
                            } label: {
                                HStack {
                                    if isGeneratingPDF { ProgressView().tint(.white) }
                                    Label(isGeneratingPDF ? "PDFを作成中…" : "プレビュー・PDF作成", systemImage: "doc.viewfinder")
                                }
                                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .foregroundStyle(.white)
                                    .background {
                                        if workspaceAppearance.isDesktop { Capsule().fill(blue) }
                                        else { RoundedRectangle(cornerRadius: 10).fill(blue) }
                                    }
                            }.buttonStyle(.plain).disabled(isGeneratingPDF)
                            }
                        }
                        .padding(16).frame(maxWidth: stacked ? .infinity : 320,
                                           maxHeight: workspaceAppearance.isDesktop && !stacked ? .infinity : nil, alignment: .topLeading)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(14)))
                        .overlay(RoundedRectangle(cornerRadius: workspaceAppearance.radius(14)).stroke(Color.black.opacity(0.06), lineWidth: 1))

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("シフト表　\(pdfMonth.japaneseMonth)").font(.subheadline.weight(.bold)).foregroundStyle(ink)
                                    Text("簡易イメージ（実際のPDFとはレイアウトが異なる場合があります）").font(.caption2).foregroundStyle(muted)
                                }
                                Spacer()
                                Button { openActualPDFPreview() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.headline).padding(8).modifier(AppGlassSurface(shape: RoundedRectangle(cornerRadius: 8), interactive: true)) }.buttonStyle(.plain).accessibilityLabel("プレビューを全画面表示").disabled(isGeneratingPDF)
                            }
                            ShiftPrintPreview(month: pdfMonth, showStaffName: showStaffName, showWorkTime: showWorkTime, showBreakTime: showBreakTime, showMemo: showMemo, showWage: showWage, paperSize: paperSize, periodMode: periodMode, department: selectedDepartment,
                                              maximumHeight: workspaceAppearance.isDesktop ? nil : 360)
                            HStack(spacing: 8) {
                                Label(paperSize, systemImage: "doc").font(.caption2).foregroundStyle(muted)
                                Spacer()
                                Text("ページ数は全画面PDFプレビューで確認").font(.caption2).foregroundStyle(muted)
                            }
                            if UIDevice.current.userInterfaceIdiom == .phone {
                                phonePDFButtons
                            } else if !workspaceAppearance.isDesktop {
                            (UIDevice.current.userInterfaceIdiom == .phone ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))) {
                                Button { startPDFGeneration(preview: false) } label: {
                                    Label("PDF保存", systemImage: "arrow.down.doc.fill").frame(maxWidth: .infinity).padding(.vertical, 11)
                                }.modifier(AppActionStyle(prominent: true)).tint(blue).disabled(isGeneratingPDF)
                                Button { startPDFGeneration(preview: false) } label: {
                                    Label("印刷 / AirPrint", systemImage: "printer.fill").frame(maxWidth: .infinity).padding(.vertical, 11)
                                }.modifier(AppActionStyle()).disabled(isGeneratingPDF)
                            }
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity,
                                           maxHeight: workspaceAppearance.isDesktop && !stacked ? .infinity : nil, alignment: .topLeading)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(14)))
                        .overlay(RoundedRectangle(cornerRadius: workspaceAppearance.radius(14)).stroke(Color.black.opacity(0.06), lineWidth: 1))
                    }
                    if workspaceAppearance.isDesktop {
                        desktopPDFActions(width: geometry.size.width)
                    }
                } else if selectedTab == 1 {
                    VStack(alignment: .leading, spacing: 18) {
                        sectionTitle("印刷設定", subtitle: "印刷前に用紙と帳票の表示項目を確認してください")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(["A4横", "A4縦", "A3横", "A3縦"], id: \.self) { size in paperButton(size) }
                        }
                        if UIDevice.current.userInterfaceIdiom == .phone {
                            phoneOutputFilters
                            phoneOutputFields(wageTitle: "時給を表示")
                        } else {
                        outputRangeAndDepartment
                        Divider()
                        outputToggle("スタッフ名を表示", isOn: $showStaffName)
                        outputToggle("勤務時間を表示", isOn: $showWorkTime)
                        outputToggle("休憩時間を表示", isOn: $showBreakTime)
                        outputToggle("メモ欄を表示", isOn: $showMemo)
                        outputToggle("時給を表示", isOn: $showWage)
                        }
                        Text("設定はプレビューとPDFに反映されます。A4縦の「1か月」は番号・スタッフ名の欄を狭め、1表で表示します。「時給」は人件費合計ではありません。休憩時間は各勤務設定に準ずる旨を表示します。")
                            .font(.caption).foregroundStyle(muted)
                    }.padding(20).background(Color.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(14)))
                } else if selectedTab == 2 {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("CSV出力", subtitle: "表計算ソフトで確認・集計")
                            Text("対象施設のスタッフ・シフト情報をCSV形式で書き出します。Excelなどで開けます。")
                                .font(.subheadline).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                            Button {
                                guard !isGeneratingCSV else { return }
                                let locationID = store.selectedLocationID
                                isGeneratingCSV = true
                                Task {
                                    let url = await store.exportCSV()
                                    if locationID == store.selectedLocationID {
                                        if url != nil { prepareExport(url) } else { csvError = "CSVを作成できませんでした。空き容量を確認してください。" }
                                    } else {
                                        if let url { Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: url) } }
                                        csvError = "店舗が切り替わりました。選択中の店舗で再度出力してください。"
                                    }
                                    isGeneratingCSV = false
                                }
                            } label: {
                                Label(isGeneratingCSV ? "CSVを作成中…" : "CSVファイルを出力", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                            }.modifier(AppActionStyle(prominent: true)).tint(blue).disabled(isGeneratingCSV)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.white, in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(14)))
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(Color.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("出力したファイルは安全な場所に保存").font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                        Text("PDF・CSV・JSONは共有画面から「ファイルに保存」やAirDropを選べます。定期的なバックアップをおすすめします。")
                            .font(.caption).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(workspaceAppearance.inset(UIDevice.current.userInterfaceIdiom == .phone ? 12 : 20)).frame(maxWidth: workspaceAppearance.contentWidth, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if UIDevice.current.userInterfaceIdiom == .phone {
                outputTabs.padding(.horizontal, 12).padding(.vertical, 8).modifier(AppGlassSurface(shape: RoundedRectangle(cornerRadius: 0)))
            }
        }
        .background(workspaceAppearance.background(Color(red: 0.95, green: 0.965, blue: 0.98)))
        // FIXED197: A preview is a snapshot of the selected export settings.
        // Never keep presenting that snapshot after settings or hotel change.
        .onChange(of: pdfConfigurationSignature) { _, _ in
            invalidatePDFPreview()
        }
        .onChange(of: store.pdfRevision) { _, _ in
            invalidatePDFPreview()
        }
        .onChange(of: store.selectedLocationID) { _, _ in
            invalidatePDFPreview()
            selectedDepartment = "すべて"
        }
        // FIXED467: Start cold PDF/font initialization while export settings are viewed.
        .task {
            _ = await store.exportShiftPDFAsync(
                month: pdfMonth, paperSize: paperSize, showStaffName: showStaffName,
                showWorkTime: showWorkTime, showBreakTime: showBreakTime,
                showMemo: showMemo, showWage: showWage,
                department: selectedDepartment, periodMode: periodMode)
        }
        .onDisappear { pdfGenerationTask?.cancel() }
        .alert("CSV出力", isPresented: Binding(get: { csvError != nil }, set: { if !$0 { csvError = nil } })) {
            Button("OK") { csvError = nil }
        } message: { Text(csvError ?? "") }
        .sheet(item: $exportItem) { item in ShareSheet(items: [item.url]) }
        .fullScreenCover(item: $activePDFPreview) { preview in
            NavigationStack {
                Group {
                    if preview.document.pageCount > 0 {
                        VStack(spacing: 0) {
                            Text("実際の出力PDF・全\(preview.document.pageCount)ページ")
                                .font(.subheadline).padding(8)
                            OutputActualPDFView(document: preview.document)
                        }
                    } else {
                        ContentUnavailableView("PDFを表示できません", systemImage: "doc.richtext")
                    }
                }.background(Color.gray.opacity(0.12))
                .navigationTitle("PDFプレビュー")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { previewExportItem = OutputFileItem(url: preview.url) } label: {
                            Label("保存・共有", systemImage: "square.and.arrow.up")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("閉じる") { activePDFPreview = nil }
                    }
                }
                .sheet(item: $previewExportItem) { item in ShareSheet(items: [item.url]) }
            }
        }
        .alert("PDFを作成できません", isPresented: $showPDFInfo) { Button("OK", role: .cancel) {} } message: { Text("シフト表PDFの作成に失敗しました。シフトデータを確認して、もう一度お試しください。") }
    }

    private var phonePDFButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                phonePDFPill("プレビュー") { startPDFGeneration(preview: true) }
                phonePDFPill("保存", prominent: true) { startPDFGeneration(preview: false) }
                phonePDFPill("印刷") { startPDFGeneration(preview: false) }
            }.disabled(isGeneratingPDF)
            if isGeneratingPDF { ProgressView("PDFを作成中…").font(.caption) }
        }
    }
    private func phonePDFPill(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(prominent ? Color.white : blue)
                .modifier(AppGlassSurface(shape: Capsule(), interactive: true, tint: prominent ? blue : nil))
                .contentShape(Capsule())
        }.buttonStyle(.plain)
    }
    private var phoneOutputFilters: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("出力範囲").font(.caption.weight(.semibold)).foregroundStyle(muted)
                Picker("出力範囲", selection: $periodMode) {
                    Text("前半（1〜15日）").tag("前半")
                    Text("後半（16日〜末日）").tag("後半")
                    Text("1か月分").tag("1か月")
                    Text("上下に半月分割").tag("上下分割")
                }.pickerStyle(.menu).labelsHidden().lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text("部署").font(.caption.weight(.semibold)).foregroundStyle(muted)
                Picker("部署", selection: $selectedDepartment) {
                    Text("すべて").tag("すべて")
                    ForEach(departmentOptions, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu).labelsHidden().lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func phoneOutputFields(wageTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("表示項目").font(.caption.weight(.semibold)).foregroundStyle(muted).padding(.bottom, 6)
            outputToggle("スタッフ名", isOn: $showStaffName).padding(.vertical, 10)
            Divider()
            outputToggle("勤務時間", isOn: $showWorkTime).padding(.vertical, 10)
            Divider()
            outputToggle("休憩時間", isOn: $showBreakTime).padding(.vertical, 10)
            Divider()
            outputToggle("メモ欄", isOn: $showMemo).padding(.vertical, 10)
            Divider()
            outputToggle(wageTitle, isOn: $showWage).padding(.vertical, 10)
        }
    }
    private func desktopPDFActions(width: CGFloat) -> some View {
        let buttonWidth = max(190, (width - 24) / 3)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Button { startPDFGeneration(preview: true) } label: {
                    HStack(spacing: 8) {
                        if isGeneratingPDF { ProgressView().tint(.white) }
                        Label(isGeneratingPDF ? "PDFを作成中…" : "プレビュー・PDF作成", systemImage: "doc.viewfinder")
                    }
                    .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: buttonWidth, height: 44)
                    .foregroundStyle(.white).background(blue, in: Capsule())
                }.buttonStyle(.plain)
                Button { startPDFGeneration(preview: false) } label: {
                    Label("PDF保存", systemImage: "arrow.down.doc.fill")
                        .frame(width: max(0, buttonWidth - 24), height: 36)
                }.modifier(AppActionStyle(prominent: true)).tint(blue)
                Button { startPDFGeneration(preview: false) } label: {
                    Label("印刷 / AirPrint", systemImage: "printer.fill")
                        .frame(width: max(0, buttonWidth - 24), height: 36)
                }.modifier(AppActionStyle())
            }
            .disabled(isGeneratingPDF)
            .padding(.vertical, 4)
        }
    }
    private var outputRangeAndDepartment: some View {
        (workspaceAppearance.isDesktop ? AnyLayout(HStackLayout(alignment: .top, spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))) {
            VStack(alignment: .leading, spacing: 8) {
                Text("出力範囲").font(.caption.weight(.semibold)).foregroundStyle(muted)
                Picker("出力範囲", selection: $periodMode) {
                    Text("前半（1〜15日）").tag("前半")
                    Text("後半（16日〜末日）").tag("後半")
                    Text("1か月分").tag("1か月")
                    Text("1か月分・上下に半月分割").tag("上下分割")
                }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text("部署").font(.caption.weight(.semibold)).foregroundStyle(muted)
                Picker("部署", selection: $selectedDepartment) {
                    Text("すべて").tag("すべて")
                    ForEach(departmentOptions, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var outputTabs: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .phone {
                Picker("印刷・出力", selection: $selectedTab) {
                    Text("PDF出力").tag(0)
                    Text("印刷設定").tag(1)
                    Text("CSV出力").tag(2)
                }.modifier(PhoneTabStyle())
            } else {
                HStack(spacing: 6) {
                    outputTab("PDF出力", icon: "doc.richtext", index: 0)
                    outputTab("印刷設定", icon: "slider.horizontal.3", index: 1)
                    outputTab("CSV出力", icon: "tablecells", index: 2)
                }
                .padding(5).background(Color.white, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.black.opacity(0.06), lineWidth: 1))

            }
        }
    }
    private func outputTab(_ title: String, icon: String, index: Int) -> some View {
        Button { selectedTab = index } label: {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(selectedTab == index ? blue : muted)
                .background(selectedTab == index ? blue.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if UIDevice.current.userInterfaceIdiom != .phone { Text(title).font(.headline).foregroundStyle(ink) }
            Text(subtitle).font(.caption).foregroundStyle(muted)
        }
    }
    private func paperButton(_ title: String) -> some View {
        Button { paperSize = title } label: {
            Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                .foregroundStyle(paperSize == title ? .white : ink)
                .modifier(AppGlassSurface(shape: RoundedRectangle(cornerRadius: 9), interactive: true, tint: paperSize == title ? blue : nil))
        }.buttonStyle(.plain)
    }
    private func outputToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn).font(.subheadline).tint(blue)
    }
    private func changeMonth(_ amount: Int) { pdfMonth = Calendar.current.date(byAdding: .month, value: amount, to: pdfMonth) ?? pdfMonth }
    private var departmentOptions: [String] {
        Array(Set(store.selectedStaff.map(\.department))).filter { !$0.isEmpty }.sorted()
    }
    // FIXED197: All PDF options are part of the preview snapshot identity.
    private var pdfConfigurationSignature: String {
        [String(pdfMonth.timeIntervalSinceReferenceDate), paperSize, periodMode,
         selectedDepartment, String(showStaffName), String(showWorkTime),
         String(showBreakTime), String(showMemo), String(showWage)].joined(separator: "|")
    }
    private func invalidatePDFPreview() {
        activePDFPreview = nil
        previewExportItem = nil
    }

    // FIXED196: Full-screen preview uses the same generated PDF as export.
    // The small SwiftUI table remains a clearly labelled schematic only.
    private func openActualPDFPreview() {
        startPDFGeneration(preview: true)
    }

    @MainActor
    private func startPDFGeneration(preview: Bool) {
        guard !isGeneratingPDF else { return }
        isGeneratingPDF = true
        let signature = pdfConfigurationSignature
        let locationID = store.selectedLocationID
        let revision = store.pdfRevision
        pdfGenerationTask = Task { @MainActor in
            defer { isGeneratingPDF = false }
            let url = await store.exportShiftPDFAsync(
                month: pdfMonth, paperSize: paperSize, showStaffName: showStaffName,
                showWorkTime: showWorkTime, showBreakTime: showBreakTime,
                showMemo: showMemo, showWage: showWage,
                department: selectedDepartment, periodMode: periodMode)
            // Discard results if settings, hotel or source data changed while rendering.
            guard !Task.isCancelled, signature == pdfConfigurationSignature,
                  locationID == store.selectedLocationID, revision == store.pdfRevision else {
                // The preparation can also be in use by another caller.
                return
            }
            guard let url else { showPDFInfo = true; return }
            if preview {
                guard let document = PDFDocument(url: url), document.pageCount > 0 else {
                    showPDFInfo = true
                    return
                }
                activePDFPreview = OutputPDFPreviewItem(document: document, url: url)
            } else {
                prepareExport(url)
            }
        }
    }
    private func prepareExport(_ url: URL?) { guard let url else { return }; exportItem = OutputFileItem(url: url) }
}

// FIXED455: PDF document and presentation identity change atomically.
private struct OutputPDFPreviewItem: Identifiable {
    let id = UUID()
    let document: PDFDocument
    let url: URL
}

// FIXED196: Render actual PDF pages rather than a second, approximate layout.
private struct OutputActualPDFView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemGray5
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}


private struct ShiftPrintPreview: View {
    @EnvironmentObject private var store: ShiftStore
    let month: Date
    let showStaffName: Bool
    let showWorkTime: Bool
    let showBreakTime: Bool
    let showMemo: Bool
    let showWage: Bool
    let paperSize: String
    var periodMode: String = "1か月"
    var department: String = "すべて"
    var fullScreen: Bool = false
    var maximumHeight: CGFloat? = 360
    private let blue = Color(red: 0.12, green: 0.43, blue: 0.91)
    private var days: [Date] {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let all = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
        switch periodMode {
        case "前半": return all.filter { calendar.component(.day, from: $0) <= 15 }
        case "上下分割": return all
        case "後半": return all.filter { calendar.component(.day, from: $0) >= 16 }
        default: return all
        }
    }
    private var staff: [StaffMember] { store.selectedStaff.filter { $0.isActive && (department == "すべて" || $0.department == department) }.sorted { ($0.department, $0.name) < ($1.department, $1.name) } }
    // FIXED466: One lookup build per preview update, not one full history scan per cell.
    private func assignmentLookup(for dates: [Date]) -> [UUID: [String: ShiftAssignment]] {
        let keys = Set(dates.map(\.shiftDateKey))
        var result: [UUID: [String: ShiftAssignment]] = [:]
        for assignment in store.selectedAssignments(on: keys) {
            if result[assignment.staffID]?[assignment.dateKey] == nil {
                result[assignment.staffID, default: [:]][assignment.dateKey] = assignment
            }
        }
        return result
    }
    var body: some View {
        if periodMode == "上下分割" {
            VStack(spacing: 8) {
                ShiftPrintPreview(month: month, showStaffName: showStaffName, showWorkTime: showWorkTime, showBreakTime: showBreakTime, showMemo: showMemo, showWage: showWage, paperSize: paperSize, periodMode: "前半", department: department, fullScreen: fullScreen, maximumHeight: maximumHeight)
                Divider().overlay(Color.black.opacity(0.35))
                ShiftPrintPreview(month: month, showStaffName: showStaffName, showWorkTime: showWorkTime, showBreakTime: showBreakTime, showMemo: showMemo, showWage: showWage, paperSize: paperSize, periodMode: "後半", department: department, fullScreen: fullScreen, maximumHeight: maximumHeight)
            }
            .padding(5)
            .background(Color.white)
            .overlay(Rectangle().stroke(Color.black.opacity(0.15), lineWidth: 1))
        } else {
        let previewDays = days
        let dateKeys = Dictionary(uniqueKeysWithValues: previewDays.map { ($0, $0.shiftDateKey) })
        let assignments = assignmentLookup(for: previewDays)
        GeometryReader { geo in
            ScrollView(.vertical) {
            VStack(spacing: 0) {
                HStack(spacing: 1) {
                    Text(showStaffName ? (showWage ? "氏名 / 時給" : "氏名") : "No.")
                        .font(.system(size: max(8, min(11, geo.size.width / 50)), weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .frame(width: geo.size.width * 0.20, alignment: .center)
                    ForEach(previewDays, id: \.shiftDateKey) { date in
                        VStack(spacing: 1) {
                            Text("\(Calendar.current.component(.day, from: date))")
                            Text(date.formatted(.dateTime.weekday(.narrow)))
                        }.frame(maxWidth: .infinity).foregroundStyle(Calendar.current.component(.weekday, from: date) == 1 ? .red : (Calendar.current.component(.weekday, from: date) == 7 ? .blue : .primary))
                    }
                }.font(.system(size: max(5, min(8, geo.size.width / 65)), weight: .bold)).padding(.vertical, 4).background(Color.blue.opacity(0.10))
                ForEach(Array(staff.enumerated()), id: \.element.id) { row, person in
                    HStack(spacing: 1) {
                        Text(showStaffName ? "\(person.name)\(showWage ? " ¥\(person.hourlyWage)" : "")" : String(format: "%02d", row + 1))
                            .font(.system(size: max(7, min(12, geo.size.width / 50)), weight: .bold))
                            .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                            .frame(width: geo.size.width * 0.20, alignment: .center)
                        ForEach(previewDays, id: \.shiftDateKey) { date in
                            let assignment = assignments[person.id]?[dateKeys[date] ?? date.shiftDateKey]
                            VStack(spacing: 1) {
                                Text(assignment?.type == .off ? "-" : (assignment?.type.rawValue.replacingOccurrences(of: "番", with: "") ?? "—")).fontWeight(.semibold)
                                if showWorkTime, let assignment, ![ShiftType.off, .paidLeave, .afterNight].contains(assignment.type) {
                                    Text("\(assignment.type.start)-\(assignment.type.end)").font(.system(size: 4))
                                }
                                if showMemo, let note = assignment?.note, !note.isEmpty { Text(note).lineLimit(1).font(.system(size: 4)) }
                            }.frame(maxWidth: .infinity).padding(.vertical, 3)
                                .background(assignment?.type == .off ? Color.green.opacity(0.12) : (assignment?.type == .late ? Color.orange.opacity(0.12) : Color.blue.opacity(0.06)))
                        }
                    }.font(.system(size: max(4, min(7, geo.size.width / 75))))
                    Divider().overlay(Color.black.opacity(0.10))
                }
                Spacer(minLength: 2)
                HStack(spacing: 5) { if showWorkTime { Text("勤務時間") }; if showBreakTime { Text("休憩時間：勤務設定に準ずる") }; if showMemo { Text("メモ欄") }; Spacer(); Text(paperSize) }.font(.system(size: 6)).foregroundStyle(.secondary).padding(.top, 4)
            }.padding(5).background(Color.white).overlay(Rectangle().stroke(Color.black.opacity(0.15), lineWidth: 1))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }.aspectRatio(paperSize.hasSuffix("縦") ? 0.707 : 1.414, contentMode: .fit).frame(maxHeight: fullScreen ? .infinity : maximumHeight)
        }
    }
}

private struct OutputFileItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct OutputCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: icon).font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(color).frame(width: 46, height: 46)
                    .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                Text(title).font(.headline).foregroundStyle(Color(red: 0.08, green: 0.16, blue: 0.25))
                Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                HStack {
                    Text("出力する").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
                }.foregroundStyle(color)
            }
            .padding(18).frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.07), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView: View {
    @Environment(\.workspaceAppearance) private var workspaceAppearance
    @EnvironmentObject private var store: ShiftStore
    @EnvironmentObject private var cloud: CloudSync
    @AppStorage("hotelShift.hotelName") private var hotelName = ""
    @AppStorage("hotelShift.heroMessage") private var heroMessage = "スタッフの笑顔が、お客様の特別な時間をつくります。"
    @AppStorage("hotelShift.heroImageBase64") private var heroImageBase64 = ""
    @AppStorage("hotelShift.logoImageBase64") private var logoImageBase64 = ""
    @AppStorage("hotelShift.accentGold") private var accentGold = true
    @State private var heroSelection: PhotosPickerItem?
    @State private var logoSelection: PhotosPickerItem?
    @State private var imageError = ""
    @State private var showBasicPatterns = false
    @State private var showSampleConfirmation = false
    @State private var sampleNotice: String?
    @State private var selectedSettingsPane: SettingsPane? = .cloud
    private enum SettingsPane: String, CaseIterable, Identifiable {
        case cloud = "iCloud同期・共有", brand = "ホテルのブランド設定", hero = "ホーム画面の写真", logo = "ホテルのロゴ"
        case patterns = "基本パターン", hours = "標準実働時間", sample = "サンプルデータ", about = "アプリとデータ"
        var id: Self { self }
        var icon: String {
            switch self {
            case .cloud: return "icloud"
            case .brand: return "building.2"
            case .hero: return "photo"
            case .logo: return "photo.on.rectangle"
            case .patterns: return "square.grid.2x2"
            case .hours: return "clock"
            case .sample: return "tray.and.arrow.down"
            case .about: return "info.circle"
            }
        }
    }
    private func shows(_ pane: SettingsPane) -> Bool {
        #if targetEnvironment(macCatalyst)
        return (selectedSettingsPane ?? .cloud) == pane
        #else
        return true
        #endif
    }

    var body: some View {
        Group {
            #if targetEnvironment(macCatalyst)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(SettingsPane.allCases) { pane in
                                Button { selectedSettingsPane = pane } label: {
                                    Label(pane.rawValue, systemImage: pane.icon)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12).padding(.vertical, 10)
                                        .foregroundStyle(selectedSettingsPane == pane ? Color.accentColor : Color.primary)
                                        .fontWeight(selectedSettingsPane == pane ? .semibold : .regular)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selectedSettingsPane == pane ? .isSelected : [])
                            }
                        }.padding(.vertical, 8)
                    }
                    .background(Color.clear)
                    .frame(width: geometry.size.width < 700 ? 170 : 210)
                    Divider()
                    settingsForm.id(selectedSettingsPane).frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            #else
            settingsForm
            #endif
        }
        .buttonStyle(.borderless)
        .scrollContentBackground(.hidden).padding(.horizontal, workspaceAppearance.inset(UIDevice.current.userInterfaceIdiom == .phone ? 0 : 24))
        .confirmationDialog("サンプルデータを追加", isPresented: $showSampleConfirmation, titleVisibility: .visible) {
            Button("4店舗・100人を追加") {
                sampleNotice = store.addSampleData() ? "サンプル4店舗・各25人を追加しました。店舗切り替えから確認できます。" : "追加できませんでした。追加済みか、保存状態を確認してください。"
            }
            Button("キャンセル", role: .cancel) { }
        } message: { Text("既存の店舗・スタッフ・シフトは残ります。iCloud同期中は共有先にもサンプルが追加されます。") }
        .alert("サンプルデータ", isPresented: Binding(get: { sampleNotice != nil }, set: { if !$0 { sampleNotice = nil } })) {
            Button("OK") { sampleNotice = nil }
        } message: { Text(sampleNotice ?? "") }
        .sheet(item: $cloud.shareSheet) { presentation in
            CloudSharingView(presentation: presentation, sync: cloud)
        }
        .sheet(isPresented: $showBasicPatterns) {
            ShiftPatternManager(month: Calendar.current.startOfMonth(for: Date()), openConflict: { _, _ in }, managementOnly: true)
                .environmentObject(store)
        }
        .onChange(of: heroSelection) { _, item in Task { await loadImage(item, isLogo: false) } }
        .onChange(of: logoSelection) { _, item in Task { await loadImage(item, isLogo: true) } }
    }

    private var settingsForm: some View {
        Form {
            if shows(.cloud) { CloudSyncSettings() }
            if shows(.brand) {
            Section {
                TextField("ホテル名（例：〇〇ホテル）", text: $hotelName)
                TextField("写真カードのメッセージ", text: $heroMessage, axis: .vertical).lineLimit(2...4)
                Text("ホームの写真カードでホテル名の下に表示します。空欄にするとメッセージを非表示にできます。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("ゴールドのアクセントカラー", isOn: $accentGold)
                Text("ホテル名・写真・ロゴはこの端末内に保存されます。サンプル名を使わず、導入するホテルごとに設定できます。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { settingsHeading("ホテルのブランド設定", pane: .brand) }
            }

            if shows(.hero) {
            Section {
                if let data = Data(base64Encoded: heroImageBase64), let image = StaffPhotoDecodeCache.image(from: data) {
                    Image(uiImage: image).resizable().scaledToFill().frame(height: 130).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ZStack { RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.08, green: 0.16, blue: 0.25)); Image(systemName: "building.2.crop.circle").font(.system(size: 46)).foregroundStyle(.white.opacity(0.8)) }.frame(height: 110)
                }
                PhotosPicker(selection: $heroSelection, matching: .images, photoLibrary: .shared()) {
                    Label(heroImageBase64.isEmpty ? "ホテル写真を選択" : "ホテル写真を変更", systemImage: "photo")
                }
                if !heroImageBase64.isEmpty { Button("写真を削除", role: .destructive) { heroImageBase64 = "" } }
            } header: { settingsHeading("ホーム画面のメイン写真", pane: .hero) }
            }

            if shows(.logo) {
            Section {
                HStack(spacing: 14) {
                    if let data = Data(base64Encoded: logoImageBase64), let image = StaffPhotoDecodeCache.image(from: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "building.2.crop.circle").font(.system(size: 44)).foregroundStyle(.secondary).frame(width: 72, height: 72).background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $logoSelection, matching: .images, photoLibrary: .shared()) { Label(logoImageBase64.isEmpty ? "ロゴを選択" : "ロゴを変更", systemImage: "photo.on.rectangle") }
                        if !logoImageBase64.isEmpty { Button("ロゴを削除", role: .destructive) { logoImageBase64 = "" } }
                    }
                }
            } header: { settingsHeading("ホテルのロゴ", pane: .logo) }
            }

            if shows(.patterns) {
            Section {
                Button { showBasicPatterns = true } label: {
                    HStack {
                        Label("基本パターンの作成・編集", systemImage: "square.grid.2x2")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                }
                Text("選択中の店舗の曜日別勤務区分・勤務時間・休憩を登録できます。保存したパターンはスタッフ詳細の週・期間パターンにも表示されます。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { settingsHeading("基本パターン", pane: .patterns) }
            }
            if shows(.hours) {
            Section {
                Text("人件費の概算に使用する時間です。ホテルの勤務ルールに合わせて変更してください。割増賃金は別途確認が必要です。")
                    .font(.caption).foregroundStyle(.secondary)
                ShiftHoursSettingRow(title: "早番", key: "hotelShift.hours.early", defaultHours: 8)
                ShiftHoursSettingRow(title: "日勤", key: "hotelShift.hours.day", defaultHours: 8)
                ShiftHoursSettingRow(title: "遅番", key: "hotelShift.hours.late", defaultHours: 8)
                ShiftHoursSettingRow(title: "夜勤", key: "hotelShift.hours.night", defaultHours: 11)
            } header: { settingsHeading("勤務区分ごとの標準実働時間", pane: .hours) }
            }
            if shows(.sample) {
            Section {
                Button("4店舗 × 25人のサンプルを追加") { showSampleConfirmation = true }
                    .disabled(store.hasSampleLocations)
                Text(store.hasSampleLocations ? "4店舗のサンプルデータは追加済みです。店舗切り替えから確認できます。" : "既存データを残して、サンプル4店舗・100人と今月／翌月のシフト・希望休を追加します。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { settingsHeading("サンプルデータ", pane: .sample) }
            }
            if shows(.about) {
            Section {
                LabeledContent("アプリ名", value: "HOTEL SHIFT")
                Button("表示環境をコピー") {
                    let sdk = Bundle.main.infoDictionary?["DTSDKName"] as? String ?? "不明"
                    let xcode = Bundle.main.infoDictionary?["DTXcodeBuild"] as? String ?? "不明"
                    let renderer: String
                    if UIAccessibility.isReduceTransparencyEnabled { renderer = "Reduced transparency" }
                    else {
                        #if compiler(>=6.2)
                        if #available(iOS 26.0, macCatalyst 26.0, *) { renderer = "Native system TabView; other controls use Liquid Glass" }
                        else { renderer = "Legacy OS fallback" }
                        #else
                        renderer = "Legacy SDK fallback"
                        #endif
                    }
                    UIPasteboard.general.string = "HOTEL SHIFT FIXED560\nOS: \(UIDevice.current.systemVersion)\nSDK: \(sdk)\nXcode build: \(xcode)\nRenderer: \(renderer)\nReduce Transparency: \(UIAccessibility.isReduceTransparencyEnabled)"
                }
                LabeledContent("保存方式", value: "端末内保存 ＋ iCloud共有（接続時）")
                LabeledContent("サーバー接続", value: "iCloud / CloudKit（接続時）")
                Text("データは端末内に保存され、iCloud共有への接続時は参加した端末間で同期します。定期的にバックアップも作成してください。")
            } header: { settingsHeading("アプリとデータ", pane: .about) }
            }
            if !imageError.isEmpty { Section { Text(imageError).foregroundStyle(.red) } }
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder private func settingsHeading(_ title: String, pane: SettingsPane) -> some View {
        #if targetEnvironment(macCatalyst)
        Label(title, systemImage: pane.icon)
        #else
        Text(title)
        #endif
    }

    @MainActor private func loadImage(_ item: PhotosPickerItem?, isLogo: Bool) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                imageError = "画像を読み込めませんでした。別の画像を選択してください。"; return
            }
            let pixels = isLogo ? 512 : 1600
            let compressed = await Task.detached(priority: .userInitiated) { ShiftPhotoProcessing.jpeg(data, maxPixels: pixels, quality: 0.78) }.value
            guard !Task.isCancelled, (isLogo ? logoSelection : heroSelection) == item else { return }
            guard let compressed else { imageError = "画像を読み込めませんでした。"; return }
            let encoded = compressed.base64EncodedString()
            if isLogo { logoImageBase64 = encoded } else { heroImageBase64 = encoded }
            imageError = ""
        } catch { imageError = "画像の読み込みに失敗しました。もう一度お試しください。" }
    }
}

private struct ShiftHoursSettingRow: View {
    let title: String
    let key: String
    let defaultHours: Int
    @AppStorage private var hours: Int

    init(title: String, key: String, defaultHours: Int) {
        self.title = title
        self.key = key
        self.defaultHours = defaultHours
        self._hours = AppStorage(wrappedValue: defaultHours, key)
    }

    var body: some View {
        Stepper(value: $hours, in: 0...16, step: 1) {
            HStack { Text(title); Spacer(); Text("\(hours)時間").foregroundStyle(.secondary).monospacedDigit() }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onCompletion: ((Bool, Error?) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onCompletion: onCompletion) }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { [weak coordinator = context.coordinator] _, completed, _, error in
            DispatchQueue.main.async { coordinator?.finish(completed: completed, error: error) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    final class Coordinator {
        var onCompletion: ((Bool, Error?) -> Void)?
        private var didFinish = false
        init(onCompletion: ((Bool, Error?) -> Void)?) { self.onCompletion = onCompletion }
        func finish(completed: Bool, error: Error?) {
            guard !didFinish else { return }
            didFinish = true
            onCompletion?(completed, error)
        }
    }
}

// MARK: - 店舗管理
struct LocationManagementView: View {
    @Environment(\.workspaceAppearance) private var workspaceAppearance
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var usesCompactLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone ||
        (workspaceAppearance.isDesktop && horizontalSizeClass == .compact)
    }
    @State private var showAdd = false
    @State private var newName = ""
    @State private var address = ""
    @State private var phone = ""
    @State private var roomCountText = ""
    @State private var floorCountText = ""
    @State private var editingLocationID: UUID? = nil
    @State private var search = ""
    @State private var facilityTab = "施設概要"
    @State private var showDelete = false
    @State private var showDeleteFromEdit = false
    @State private var showDeletePhotoConfirm = false
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var draftPhotoData: Data? = nil
    @State private var photoError: String? = nil
    @State private var profileValidationError: String? = nil
    private let navy = Color(red: 0.055, green: 0.15, blue: 0.25)
    private let blue = Color(red: 0.10, green: 0.43, blue: 0.91)

    private var filteredLocations: [HotelLocation] {
        store.data.locations.filter { location in
            search.isEmpty || location.name.localizedCaseInsensitiveContains(search) || (location.address ?? "").localizedCaseInsensitiveContains(search) || (location.phone ?? "").localizedCaseInsensitiveContains(search)
        }
    }
    private var selected: HotelLocation? { store.selectedLocation }
    private var staffCount: Int { store.selectedStaff.count }

    var body: some View {
        Group {
            if usesCompactLayout { ScrollView { locationContent }.scrollDismissesKeyboard(.interactively) }
            else { locationContent }
        }

        .safeAreaInset(edge: .top, spacing: 0) {
            if usesCompactLayout { phoneLocationHeader }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            // Capture the target facility before the asynchronous photo load starts,
            // so switching facilities while loading cannot attach the photo to the wrong store.
            let targetLocationID = editingLocationID
            Task {
                do {
                    if let rawData = try await item.loadTransferable(type: Data.self) {
                        let jpeg = await Task.detached(priority: .userInitiated) { ShiftPhotoProcessing.jpeg(rawData, maxPixels: 1000, quality: 0.78) }.value
                        guard !Task.isCancelled, selectedPhoto == item else { return }
                        if let jpeg {
                            if let targetLocationID { store.updateLocationPhoto(id: targetLocationID, photoData: jpeg) } else { draftPhotoData = jpeg }
                            selectedPhoto = nil; photoError = nil
                        } else { photoError = "画像を読み込めませんでした。別の写真を選択してください。"; selectedPhoto = nil }
                    } else { photoError = "画像を読み込めませんでした。別の写真を選択してください。"; selectedPhoto = nil }
                } catch {
                    await MainActor.run { photoError = "写真の読み込みに失敗しました。"; selectedPhoto = nil }
                }
            }
        }
        .alert("写真を読み込めません", isPresented: Binding(get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
            Button("OK", role: .cancel) { photoError = nil }
        } message: { Text(photoError ?? "") }
        .alert("入力内容を確認してください", isPresented: Binding(get: { profileValidationError != nil }, set: { if !$0 { profileValidationError = nil } })) {
            Button("OK", role: .cancel) { profileValidationError = nil }
        } message: { Text(profileValidationError ?? "") }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    Section("店舗写真") {
                        let savedPhoto = editingLocationID.flatMap { id in store.data.locations.first(where: { $0.id == id })?.photoData }
                        let displayedPhoto = editingLocationID == nil ? draftPhotoData : savedPhoto
                        VStack(alignment: .leading, spacing: 12) {
                            Group {
                                if let data = displayedPhoto, let image = StaffPhotoDecodeCache.image(from: data) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.10))
                                        Image(systemName: "building.2.crop.circle").font(.system(size: 34)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label("写真を変更", systemImage: "photo")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .modifier(AppActionStyle())

                            Button(role: .destructive) {
                                showDeletePhotoConfirm = true
                            } label: {
                                Label("写真を削除", systemImage: "trash")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .modifier(AppActionStyle())
                            .disabled(displayedPhoto == nil)

                            Text(displayedPhoto == nil ? "写真は未登録です。「写真を変更」から登録できます。" : "写真は保存後、店舗一覧と詳細にも反映されます。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section("基本情報") {
                        TextField("店舗名・ホテル名", text: $newName)
                        TextField("住所", text: $address, axis: .vertical).lineLimit(1...3)
                        TextField("電話番号", text: $phone).keyboardType(.phonePad)
                    }
                    Section("施設規模") {
                        TextField("客室数", text: $roomCountText).keyboardType(.numberPad)
                        TextField("フロア数", text: $floorCountText).keyboardType(.numberPad)
                    }
                    if editingLocationID != nil {
                        Section {
                            Button(role: .destructive) { showDeleteFromEdit = true } label: {
                                Label("この店舗を削除", systemImage: "trash")
                            }
                            .disabled(store.data.locations.count <= 1)
                        } footer: {
                            Text(store.data.locations.count <= 1 ? "最後の1店舗は削除できません。" : "誤操作防止のため、店舗の削除はこの編集画面からのみ行えます。")
                        }
                    }
                    if editingLocationID != nil {
                        Section { Text("施設情報はこの端末内に保存され、店舗を切り替えても保持されます。") .font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                    .navigationTitle(editingLocationID == nil ? "店舗を新規登録" : "施設情報を編集")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { showAdd = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("保存") {
                            let cleanedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let duplicate = hasDuplicateLocationName(cleanedName, excluding: editingLocationID)
                            if cleanedName.isEmpty {
                                profileValidationError = "店舗名を入力してください。"
                                return
                            }
                            if duplicate {
                                profileValidationError = "同じ店舗名がすでに登録されています。別の名前を入力してください。"
                                return
                            }
                            if (!roomCountText.isEmpty && (Int(roomCountText) == nil || Int(roomCountText)! <= 0)) || (!floorCountText.isEmpty && (Int(floorCountText) == nil || Int(floorCountText)! <= 0)) {
                                profileValidationError = "客室数・フロア数は1以上の整数で入力してください。"
                                return
                            }
                            if let editingLocationID {
                                store.updateLocationProfile(id: editingLocationID, name: cleanedName, address: address, phone: phone, roomCount: Int(roomCountText), floorCount: Int(floorCountText))
                            } else {
                                store.addLocation(name: cleanedName)
                                if let created = store.selectedLocation {
                                    store.updateLocationProfile(id: created.id, name: cleanedName, address: address, phone: phone, roomCount: Int(roomCountText), floorCount: Int(floorCountText))
                                    if let draftPhotoData { store.updateLocationPhoto(id: created.id, photoData: draftPhotoData) }
                                }
                            }
                            showAdd = false
                        }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                    }
            }
            .alert("写真を削除しますか？", isPresented: $showDeletePhotoConfirm) {
                Button("写真を削除する", role: .destructive) {
                    if let editingLocationID { store.updateLocationPhoto(id: editingLocationID, photoData: nil) }
                    else { draftPhotoData = nil }
                    selectedPhoto = nil
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("店舗写真を削除します。キャンセルを選ぶと写真はそのまま残ります。")
            }
            .alert("店舗を削除しますか？", isPresented: $showDeleteFromEdit) {
                Button("削除する", role: .destructive) {
                    if let editingLocationID { store.deleteLocation(id: editingLocationID) }
                    showAdd = false
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この店舗に所属するスタッフ・シフト・希望休も削除されます。この操作は取り消せません。")
            }
            .presentationDetents([.large])
        }
    }
    private var phoneLocationHeader: some View {
        HStack(spacing: 10) {
            Button { prepareNewLocation(); showAdd = true } label: {
                Image(systemName: "plus").font(.headline).frame(width: 44, height: 44)
                    .modifier(AppGlassSurface(shape: Circle(), interactive: true))
            }.buttonStyle(.plain).accessibilityLabel("店舗を新規登録")
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("店舗名・住所・電話番号で検索", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 32, height: 32)
                    }.buttonStyle(.plain).accessibilityLabel("店舗検索をクリア")
                }
            }.padding(.horizontal, 14).frame(minHeight: 44)
                .modifier(AppGlassSurface(shape: Capsule(), interactive: true))
        }.padding(.horizontal, 12).padding(.vertical, 8)
            .modifier(AppGlassSurface(shape: RoundedRectangle(cornerRadius: 0)))
    }
    private var locationContent: some View {
        VStack(spacing: 12) {
            if !usesCompactLayout {
            (usesCompactLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout())) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("登録店舗の一覧と施設情報を管理").font(.caption).foregroundStyle(.secondary)
                }
                if !usesCompactLayout { Spacer() }
                TextField("店舗名・住所・電話番号で検索", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: usesCompactLayout ? .infinity : 270)
                Button { prepareNewLocation(); showAdd = true } label: {
                    Label("新規登録", systemImage: "plus").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 10).background(blue, in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(.white)
                }
            }.padding(.horizontal, workspaceAppearance.inset(usesCompactLayout ? 12 : 22)).padding(.vertical, 16)

            }
            (usesCompactLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))) {
                if usesCompactLayout {
                    locationDetailPanel
                    locationListPanel
                } else {
                    locationListPanel
                    locationDetailPanel
                }
            }
            .padding(.horizontal, workspaceAppearance.inset(usesCompactLayout ? 12 : 22)).padding(.bottom, workspaceAppearance.inset(20))
        }
    }


    private var locationListPanel: some View {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("店舗一覧").font(.system(size: 15, weight: .bold))
                        Spacer()
                        Text("\(store.data.locations.count)店舗").font(.caption).foregroundStyle(.secondary)
                    }
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if filteredLocations.isEmpty {
                                ContentUnavailableView(search.isEmpty ? "店舗がありません" : "該当する店舗がありません", systemImage: "building.2", description: Text(search.isEmpty ? "新規登録から店舗を追加してください。" : "店舗名・住所・電話番号を変えて検索してください。"))
                                    .padding(.vertical, 18)
                            }
                            ForEach(filteredLocations) { location in
                                Button { store.selectedLocationID = location.id } label: {
                                    HStack(spacing: 11) {
                                        Group {
                                            if let data = location.photoData, let uiImage = StaffPhotoDecodeCache.image(from: data) {
                                                Image(uiImage: uiImage).resizable().scaledToFill()
                                            } else {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 9).fill(LinearGradient(colors: [Color(red: 0.25, green: 0.54, blue: 0.82), navy], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                    Image(systemName: "building.2.fill").font(.system(size: 25)).foregroundStyle(.white)
                                                }
                                            }
                                        }.frame(width: 70, height: 66).clipShape(RoundedRectangle(cornerRadius: 9))
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(location.name).font(.system(size: 14, weight: .bold)).foregroundStyle(navy).lineLimit(2)
                                            if let address = location.address, !address.isEmpty {
                                                Text(address).font(.system(size: workspaceAppearance.fontSize(10))).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            HStack(spacing: 7) {
                                                if let rooms = location.roomCount { Label("客室\(rooms)", systemImage: "bed.double").labelStyle(.titleAndIcon) }
                                                Text(location.id == store.selectedLocationID ? "選択中" : "施設情報")
                                                    .foregroundStyle(location.id == store.selectedLocationID ? blue : .secondary)
                                            }.font(.system(size: workspaceAppearance.fontSize(10), weight: .medium))
                                        }
                                        Spacer(minLength: 0)
                                        if location.id == store.selectedLocationID { Image(systemName: "checkmark.circle.fill").foregroundStyle(blue) }
                                    }
                                    .padding(10).background(.white, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                                        location.id == store.selectedLocationID ? blue.opacity(usesCompactLayout ? 0.28 : 1) : Color.black.opacity(0.07),
                                        lineWidth: location.id == store.selectedLocationID ? (usesCompactLayout ? 3 : 1.5) : 1))
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(height: usesCompactLayout ? 260 : nil)
                }
                .padding(15).frame(minWidth: usesCompactLayout ? 0 : 260, idealWidth: usesCompactLayout ? nil : 330, maxWidth: usesCompactLayout ? .infinity : 390).background(usesCompactLayout ? Color.clear : Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(15)))

    }
    private var locationDetailPanel: some View {
                VStack(alignment: .leading, spacing: 14) {
                    if let selected {
                        HStack(alignment: .center, spacing: 14) {
                            Group {
                                if let data = selected.photoData, let uiImage = StaffPhotoDecodeCache.image(from: data) {
                                    Image(uiImage: uiImage).resizable().scaledToFill()
                                } else {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 13).fill(LinearGradient(colors: [Color(red: 0.20, green: 0.48, blue: 0.76), navy], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        Image(systemName: "building.2.crop.circle.fill").font(.system(size: 40)).foregroundStyle(.white)
                                    }
                                }
                            }.frame(width: 86, height: 82).clipShape(RoundedRectangle(cornerRadius: 13))
                            if usesCompactLayout {
                                VStack(alignment: .center, spacing: 4) {
                                    Text(selected.name).font(.system(size: 22, weight: .bold)).foregroundStyle(navy)
                                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                                    phoneFacilityEditButton(selected)
                                }.frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(selected.name).font(.system(size: 20, weight: .bold)).foregroundStyle(navy)
                                    Text("施設情報").font(.caption).foregroundStyle(.secondary)
                                    Label("この端末内に保存", systemImage: "checkmark.shield.fill").font(.system(size: workspaceAppearance.fontSize(11), weight: .medium)).foregroundStyle(.green)
                                }
                            }
                            if !usesCompactLayout {
                            Spacer()
                            Button { prepareEdit(selected); showAdd = true } label: {
                                Label("施設情報を編集", systemImage: "pencil")
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(10)
                                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }
                            }
                        }
                        Divider()
                        if usesCompactLayout {
                            Picker("施設情報の表示", selection: $facilityTab) {
                                Text("施設概要").tag("施設概要")
                                Text("施設情報の管理").tag("施設情報の管理")
                            }.modifier(PhoneTabStyle())
                            phoneFacilityList(selected)
                        } else {
                        Text("施設概要").font(.system(size: 15, weight: .bold)).foregroundStyle(navy)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: usesCompactLayout ? 1 : 2), spacing: 12) {
                            facilityInfoCard(title: "施設名", value: selected.name, icon: "building.2")
                            facilityInfoCard(title: "登録スタッフ", value: "\(staffCount)名", icon: "person.2")
                            facilityInfoCard(title: "登録シフト", value: "\(store.selectedAssignmentCount)件", icon: "calendar")
                            facilityInfoCard(title: "管理方式", value: "ローカル保存", icon: "internaldrive")
                        }
                        Text("施設情報の管理").font(.system(size: 15, weight: .bold)).foregroundStyle(navy).padding(.top, 4)
                        VStack(spacing: 0) {
                            facilityDetailRow(icon: "mappin.and.ellipse", title: "住所", value: selected.address ?? "設定未登録")
                            Divider().padding(.leading, 42)
                            facilityDetailRow(icon: "phone", title: "電話番号", value: selected.phone ?? "設定未登録")
                            Divider().padding(.leading, 42)
                            facilityDetailRow(icon: "bed.double", title: "客室・フロア", value: "客室\(selected.roomCount.map(String.init) ?? "未設定")室・\(selected.floorCount.map(String.init) ?? "未設定")階")
                            Divider().padding(.leading, 42)
                            facilityDetailRow(icon: "person.3", title: "スタッフ数", value: "\(staffCount)名")
                        }.padding(.horizontal, 12).background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                        if !usesCompactLayout { Spacer(minLength: 0) }
                        HStack {
                            Text("店舗を切り替えると、スタッフ・シフト・集計も選択店舗に切り替わります。").font(.system(size: workspaceAppearance.fontSize(11))).foregroundStyle(.secondary)
                            Spacer()
                        }.padding(.top, 5)
                    } else {
                        ContentUnavailableView("店舗がありません", systemImage: "building.2", description: Text("新規登録から店舗を追加してください。"))
                    }
                }
                .padding(18).frame(maxWidth: .infinity, maxHeight: usesCompactLayout ? nil : .infinity, alignment: .topLeading).background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: workspaceAppearance.radius(15)))
    }
    private func phoneFacilityEditButton(_ location: HotelLocation) -> some View {
        Button { prepareEdit(location); showAdd = true } label: {
            Text("施設情報を編集").font(.caption.weight(.semibold))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12).frame(height: 32)
                .modifier(AppGlassSurface(shape: Capsule(), interactive: true))
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func phoneFacilityList(_ location: HotelLocation) -> some View {
        let rows: [(title: String, value: String, icon: String)] = facilityTab == "施設概要" ? [
            ("施設名", location.name, "building.2"),
            ("登録スタッフ", "\(staffCount)名", "person.2"),
            ("登録シフト", "\(store.selectedAssignmentCount)件", "calendar"),
            ("管理方式", "ローカル保存", "internaldrive")
        ] : [
            ("住所", (location.address?.isEmpty == false ? location.address : nil) ?? "未設定", "mappin.and.ellipse"),
            ("電話番号", (location.phone?.isEmpty == false ? location.phone : nil) ?? "未設定", "phone"),
            ("客室・フロア", "客室\(location.roomCount.map(String.init) ?? "未設定")室・\(location.floorCount.map(String.init) ?? "未設定")階", "bed.double"),
            ("スタッフ数", "\(staffCount)名", "person.3")
        ]
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: row.icon).font(.system(size: 21)).foregroundStyle(blue)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.title).font(.caption).foregroundStyle(.secondary)
                        Text(row.value).font(.subheadline).foregroundStyle(navy)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 14)
                if index < rows.count - 1 { Divider().padding(.leading, 40) }
            }
        }
    }

    private func prepareNewLocation() {
        editingLocationID = nil
        newName = ""
        address = ""
        phone = ""
        roomCountText = ""
        floorCountText = ""
        draftPhotoData = nil
        selectedPhoto = nil
        showDeleteFromEdit = false
    }

    private func prepareEdit(_ location: HotelLocation) {
        editingLocationID = location.id
        newName = location.name
        address = location.address ?? ""
        phone = location.phone ?? ""
        roomCountText = location.roomCount.map(String.init) ?? ""
        floorCountText = location.floorCount.map(String.init) ?? ""
        draftPhotoData = nil
        selectedPhoto = nil
        showDeleteFromEdit = false
    }

    private func hasDuplicateLocationName(_ name: String, excluding id: UUID?) -> Bool {
        for location in store.data.locations {
            if location.id == id { continue }
            let existingName = location.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if existingName.localizedCaseInsensitiveCompare(name) == .orderedSame {
                return true
            }
        }
        return false
    }

    private func facilityInfoCard(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium)).foregroundStyle(blue).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: workspaceAppearance.fontSize(10), weight: .medium)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 14, weight: .bold)).foregroundStyle(navy).lineLimit(usesCompactLayout ? nil : 1)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06)))
    }

    private func facilityDetailRow(icon: String, title: String, value: String) -> some View {
        (usesCompactLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))) {
            Image(systemName: icon).foregroundStyle(blue).frame(width: 26)
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).frame(width: usesCompactLayout ? nil : 90, alignment: .leading)
            if !usesCompactLayout { Spacer() }
            Text(value).font(.system(size: 12, weight: .medium)).foregroundStyle(navy)
        }.padding(.vertical, 12)
    }
}

// FIXED484: Stable route from every schedule name, resolving live data by staff/store ID.
struct ScheduleStaffProfileSheet: View {
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.dismiss) private var dismiss
    let staffID: UUID
    let locationID: UUID?
    let referenceDate: Date
    @State private var editingStaff: StaffMember?
    @State private var statusConfirmation: StaffMember?
    @State private var error: String?
    @State private var pendingEditError: String?
    private var current: StaffMember? {
        guard locationID == store.selectedLocationID else { return nil }
        return store.data.staff.first { $0.id == staffID && $0.locationID == locationID }
    }
    var body: some View {
        Group {
            if let person = current {
                StaffDetailSheet(staff: person, referenceDate: referenceDate, onEdit: {
                    editingStaff = current
                }, onChangeStatus: { statusConfirmation = $0 })
            } else {
                NavigationStack {
                    ContentUnavailableView("スタッフを表示できません", systemImage: "person.crop.circle.badge.exclamationmark",
                                           description: Text("店舗・スタッフ情報が変更されました。画面を閉じて再選択してください。"))
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } } }
                }
            }
        }
        .sheet(item: $editingStaff, onDismiss: {
            if let pendingEditError { error = pendingEditError; self.pendingEditError = nil }
        }) { original in
            StaffFormSheet(title: "スタッフ情報を編集", initial: original,
                           availableDepartments: Array(Set(store.selectedStaff.map(\.department))).sorted(),
                           minimumWage: 0, showsMinimumWageReference: false) { name, department, employment, wage, photo in
                guard current == original,
                      store.saveStaffProfile(expected: original, name: name, department: department,
                                             employment: employment, wage: wage, photoData: photo) else {
                    pendingEditError = "編集中にスタッフ情報や店舗が変更されました。最新の内容を確認してください。"
                    return
                }
            }
        }
        .confirmationDialog("勤務状態を変更しますか？", isPresented: Binding(get: { statusConfirmation != nil }, set: { if !$0 { statusConfirmation = nil } }), titleVisibility: .visible) {
            Button(statusConfirmation?.isActive == true ? "休止中に変更" : "勤務可能に戻す") {
                defer { statusConfirmation = nil }
                guard let original = statusConfirmation, current == original,
                      store.setStaffProfileActive(expected: original, active: !original.isActive) else {
                    error = "確認中にスタッフ情報や店舗が変更されました。再操作してください。"; return
                }
            }
            Button("キャンセル", role: .cancel) { statusConfirmation = nil }
        } message: { Text("過去の勤務・希望休・個人時間・パターンは削除しません。") }
        .alert("変更できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onChange(of: store.selectedLocationID) { _, _ in editingStaff = nil; statusConfirmation = nil; dismiss() }
    }
}

private struct StaffEmploymentDatesEditor: View {
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.dismiss) private var dismiss
    let original: StaffMember
    @State private var hasJoin = false
    @State private var hasLeave = false
    @State private var join = Date()
    @State private var leave = Date()
    @State private var initialized = false
    @State private var error: String?
    private var joinKey: String? { hasJoin ? join.shiftDateKey : nil }
    private var leaveKey: String? { hasLeave ? leave.shiftDateKey : nil }
    private var dirty: Bool {
        initialized && (joinKey != original.joinDate || leaveKey != original.leaveDate)
    }
    @State private var discard = false
    var body: some View {
        NavigationStack {
            Form {
                Section("入社・退職日の記録") {
                    Toggle("入社日を記録", isOn: $hasJoin)
                    if hasJoin { DatePicker("入社日", selection: $join, displayedComponents: .date) }
                    Toggle("退職日を記録", isOn: $hasLeave)
                    if hasLeave { DatePicker("退職日", selection: $leave, displayedComponents: .date) }
                    if !StaffProfileValidation.validDates(join: joinKey, leave: leaveKey) {
                        Text("退職日は入社日以降にしてください。").foregroundStyle(.red)
                    }
                }
                Text("日付は記録用です。表への表示は「勤務可能／休止中」で切り替えます。日付を保存しても過去のシフトは変更しません。")
                    .font(.caption).foregroundStyle(.secondary)
            }.navigationTitle("入社日・退職日")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { if dirty { discard = true } else { dismiss() } }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            guard store.saveStaffEmploymentDates(expected: original, join: joinKey, leave: leaveKey) else {
                                error = "スタッフ情報や店舗が変わったか、日付が不正です。最新の詳細から開き直してください。"; return
                            }
                            dismiss()
                        }.disabled(!initialized || !StaffProfileValidation.validDates(join: joinKey, leave: leaveKey))
                    }
                }
                .onAppear {
                    guard !initialized else { return }
                    if let date = original.joinDate.flatMap({ Date.keyFormatter.date(from: $0) }) { join = date; hasJoin = true }
                    if let date = original.leaveDate.flatMap({ Date.keyFormatter.date(from: $0) }) { leave = date; hasLeave = true }
                    initialized = true
                }
                .confirmationDialog("変更を破棄しますか？", isPresented: $discard, titleVisibility: .visible) {
                    Button("破棄する", role: .destructive) { dismiss() }
                    Button("編集を続ける", role: .cancel) {}
                }
                .alert("保存できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK") { error = nil }
                } message: { Text(error ?? "") }
        }.interactiveDismissDisabled(dirty)
    }
}

// FIXED490: Poster for the supplied mobile form, compatible with EldiaShift.
enum RequestQRCode {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>(); cache.countLimit = 12; cache.totalCostLimit = 4 * 1024 * 1024; return cache
    }()
    static func image(_ text: String, size: CGFloat) -> UIImage? {
        guard size.isFinite, size > 0 else { return nil }
        let key = "\(Int(size))|\(text)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = max(1, floor(size / output.extent.width))
        guard let cg = context.createCGImage(output.transformed(by: CGAffineTransform(scaleX: scale, y: scale)), from: output.extent.applying(CGAffineTransform(scaleX: scale, y: scale))) else { return nil }
        let image = UIImage(cgImage: cg)
        images.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
        return image
    }
    @MainActor static func posterPDF(storeName: String) -> URL? {
        let renderer = ImageRenderer(content: RequestQRPoster(storeName: storeName, url: RequestFormLink.url(storeName: storeName)))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("希望休の申請QR_\(UUID().uuidString).pdf")
        var made = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let context = CGContext(file as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil); draw(context); context.endPDFPage(); context.closePDF(); made = true
        }
        guard made, FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }
}
struct RequestQRPoster: View {
    let storeName: String
    let url: URL
    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("HOTEL SHIFT").font(.system(size: 20, weight: .heavy)).foregroundStyle(Color(white: 0.35))
                Text("希望休の申請").font(.system(size: 42, weight: .heavy))
                Text(storeName).font(.system(size: 22, weight: .bold)).lineLimit(2).multilineTextAlignment(.center)
            }.frame(width: 480)
            if let qr = RequestQRCode.image(url.absoluteString, size: 900) {
                Image(uiImage: qr).interpolation(.none).resizable().frame(width: 290, height: 290)
                    .padding(18).background(Color.white).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.8), lineWidth: 2))
            }
            VStack(alignment: .leading, spacing: 14) {
                step(1, "スマホでQRコードを読み取る")
                step(2, "名前・希望日・理由を入力する")
                step(3, "LINEで担当者へ送る")
            }.frame(width: 450, alignment: .leading)
            Text("送信先でシフト担当者を選んでください。\nLINEが使えない場合は「文章をコピー」などからお送りください。")
                .font(.system(size: 13)).foregroundStyle(Color(white: 0.4)).multilineTextAlignment(.center).frame(width: 470)
        }.foregroundStyle(Color.black).frame(width: 595, height: 842).background(Color.white).environment(\.colorScheme, .light)
    }
    private func step(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 14) {
            Text("\(n)").font(.system(size: 18, weight: .bold)).foregroundStyle(Color.white).frame(width: 30, height: 30).background(Color.black, in: Circle())
            Text(text).font(.system(size: 20, weight: .semibold))
        }
    }
}
private struct RequestQRSheet: View {
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.dismiss) private var dismiss
    @State private var locationID: UUID?
    @State private var outputFile: OutputFileItem?
    @State private var error: String?
    @State private var copied = false
    private var location: HotelLocation? { store.data.locations.first { $0.id == locationID } }
    private var url: URL { RequestFormLink.url(storeName: location?.name ?? "") }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        Text("店舗").font(.subheadline.weight(.semibold))
                        Picker("店舗", selection: $locationID) {
                            ForEach(store.data.locations) { Text($0.name).tag(Optional($0.id)) }
                        }.frame(maxWidth: .infinity, alignment: .trailing)
                    }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 9))
                    RequestQRPoster(storeName: location?.name ?? "", url: url)
                        .scaleEffect(0.5).frame(width: 297.5, height: 421)
                        .overlay(Rectangle().stroke(Color.gray.opacity(0.25))).shadow(color: .black.opacity(0.05), radius: 8, y: 3)
                        .accessibilityLabel("\(location?.name ?? "")の希望休申請QRポスター")
                    HStack(spacing: 12) {
                        Button { makePDF() } label: { Label("印刷・PDF", systemImage: "printer") }.buttonStyle(RequestActionStyle(color: .blue))
                        ShareLink(item: url) { Label("リンクを共有", systemImage: "link") }.buttonStyle(RequestActionStyle(color: .blue))
                    }.font(.system(size: 14, weight: .semibold)).disabled(location == nil)
                    Button {
                        UIPasteboard.general.url = url; copied = true
                    } label: { Label(copied ? "コピーしました" : "リンクをコピー", systemImage: "doc.on.doc") }.disabled(location == nil)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("事務所や休憩室など、スタッフが見る場所に貼ってください。QRを読むと指定のスマホ申請フォームが開きます。スタッフ側にアプリは不要です。")
                        Text("LINEで届いたリンクを開き「SHIFTで取り込む」を押すか、アプリの「申請を受け取る」にリンク・文章を貼り付けてください。")
                        Text("「印刷・PDF」では共有画面からプリント・ファイル保存を選べます。")
                        Text(url.absoluteString).font(.caption2).textSelection(.enabled)
                    }.font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(22).frame(maxWidth: 580).frame(maxWidth: .infinity)
            }.background(Color(red: 0.95, green: 0.96, blue: 0.98))
                .navigationTitle("申請用QRコード").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
                .onAppear { locationID = store.selectedLocationID }
                .onChange(of: locationID) { _, _ in copied = false }
                .sheet(item: $outputFile) { ShareSheet(items: [$0.url]) }
                .alert("確認してください", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func makePDF() {
        guard let location, let file = RequestQRCode.posterPDF(storeName: location.name) else { error = "PDFを作成できませんでした。"; return }
        outputFile = OutputFileItem(url: file)
    }
}


// Original vector avatar. The same renderer is used for preview and stored PNG.
private struct StaffAvatarConfiguration: Equatable, Codable {
    var dimensional: Bool { false }
    var clothing = "シンプル"
    var nose = "ふつう"
    var hijabColor: Int? = nil
    var eyeScale: Double = 1
    var eyeSpacing: Double = 1
    var mouthScale: Double = 1
    var skin = 1
    var face = "まるい"
    var hairColor = 0
    var hair = "ショート"
    var expression = "笑顔"
    var eyes = "ふつう"
    var eyebrows = "ふつう"
    var beard = "なし"
    var accessory = "なし"
    var glassesShape = "スクエア"
    var glasses = false
    var background = 0
    var outfit = 0
}

private enum StaffAvatarDrawing {
    static let skins: [UIColor] = [UIColor(red: 1, green: 0.85, blue: 0.71, alpha: 1), UIColor(red: 0.90, green: 0.68, blue: 0.49, alpha: 1), UIColor(red: 0.67, green: 0.43, blue: 0.29, alpha: 1), UIColor(red: 0.39, green: 0.25, blue: 0.19, alpha: 1), UIColor(red: 1, green: 0.92, blue: 0.84, alpha: 1), UIColor(red: 0.96, green: 0.76, blue: 0.62, alpha: 1), UIColor(red: 0.76, green: 0.54, blue: 0.37, alpha: 1), UIColor(red: 0.49, green: 0.32, blue: 0.23, alpha: 1), UIColor(red: 0.98, green: 0.82, blue: 0.69, alpha: 1), UIColor(red: 0.84, green: 0.61, blue: 0.45, alpha: 1), UIColor(red: 0.72, green: 0.46, blue: 0.32, alpha: 1), UIColor(red: 0.58, green: 0.37, blue: 0.26, alpha: 1), UIColor(red: 0.94, green: 0.73, blue: 0.57, alpha: 1), UIColor(red: 0.99, green: 0.89, blue: 0.77, alpha: 1), UIColor(red: 0.45, green: 0.29, blue: 0.21, alpha: 1), UIColor(red: 0.33, green: 0.21, blue: 0.17, alpha: 1)]
    static let hairs: [UIColor] = [UIColor(white: 0.12, alpha: 1), UIColor(red: 0.36, green: 0.21, blue: 0.13, alpha: 1), UIColor(red: 0.79, green: 0.59, blue: 0.26, alpha: 1), UIColor(white: 0.65, alpha: 1), UIColor(red: 0.59, green: 0.28, blue: 0.16, alpha: 1), UIColor(red: 0.96, green: 0.86, blue: 0.64, alpha: 1), UIColor(red: 0.38, green: 0.27, blue: 0.50, alpha: 1), UIColor(red: 0.93, green: 0.93, blue: 0.91, alpha: 1), UIColor(red: 0.16, green: 0.11, blue: 0.09, alpha: 1), UIColor(red: 0.45, green: 0.3, blue: 0.2, alpha: 1), UIColor(red: 0.68, green: 0.46, blue: 0.27, alpha: 1), UIColor(red: 0.74, green: 0.34, blue: 0.22, alpha: 1), UIColor(red: 0.3, green: 0.34, blue: 0.39, alpha: 1), UIColor(red: 0.18, green: 0.35, blue: 0.35, alpha: 1), UIColor(red: 0.72, green: 0.44, blue: 0.58, alpha: 1), UIColor(red: 0.94, green: 0.8, blue: 0.64, alpha: 1)]
    static let backgrounds: [UIColor] = [UIColor(red: 0.83, green: 0.91, blue: 1, alpha: 1), UIColor(red: 0.87, green: 0.94, blue: 0.84, alpha: 1), UIColor(red: 1, green: 0.87, blue: 0.86, alpha: 1), UIColor(red: 0.92, green: 0.86, blue: 0.98, alpha: 1), UIColor(red: 1, green: 0.95, blue: 0.76, alpha: 1), UIColor(red: 0.78, green: 0.94, blue: 0.93, alpha: 1), UIColor(red: 0.98, green: 0.85, blue: 0.93, alpha: 1), UIColor(red: 0.88, green: 0.90, blue: 0.92, alpha: 1), UIColor(red: 0.98, green: 0.92, blue: 0.86, alpha: 1), UIColor(red: 0.84, green: 0.96, blue: 0.98, alpha: 1), UIColor(red: 0.95, green: 0.94, blue: 0.86, alpha: 1), UIColor(red: 0.92, green: 0.94, blue: 0.98, alpha: 1), UIColor(red: 0.87, green: 0.82, blue: 0.76, alpha: 1), UIColor(red: 0.74, green: 0.87, blue: 0.82, alpha: 1), UIColor(red: 0.9, green: 0.81, blue: 0.83, alpha: 1), UIColor(red: 0.76, green: 0.83, blue: 0.95, alpha: 1)]
    static let outfits: [UIColor] = [UIColor(red: 0.12, green: 0.28, blue: 0.46, alpha: 1), UIColor(red: 0.21, green: 0.48, blue: 0.40, alpha: 1), UIColor(red: 0.70, green: 0.28, blue: 0.26, alpha: 1), UIColor(red: 0.47, green: 0.30, blue: 0.62, alpha: 1), UIColor(red: 0.85, green: 0.57, blue: 0.19, alpha: 1), UIColor(red: 0.18, green: 0.57, blue: 0.65, alpha: 1), UIColor(red: 0.32, green: 0.34, blue: 0.38, alpha: 1), UIColor(red: 0.91, green: 0.87, blue: 0.79, alpha: 1), UIColor(red: 0.18, green: 0.23, blue: 0.32, alpha: 1), UIColor(red: 0.81, green: 0.4, blue: 0.57, alpha: 1), UIColor(red: 0.64, green: 0.7, blue: 0.3, alpha: 1), UIColor(red: 0.38, green: 0.58, blue: 0.78, alpha: 1), UIColor(red: 0.82, green: 0.47, blue: 0.23, alpha: 1), UIColor(red: 0.44, green: 0.31, blue: 0.21, alpha: 1), UIColor(red: 0.9, green: 0.9, blue: 0.88, alpha: 1), UIColor(red: 0.15, green: 0.16, blue: 0.18, alpha: 1)]
    static let hairStyles = ["ショート", "ロング", "カール", "ボブ", "前髪", "センター分け", "おだんご", "ベリーショート", "マッシュ", "サイド分け", "外はね", "ウェーブ", "ポニーテール", "ツインテール", "三つ編み", "モヒカン", "アフロ", "刈り上げ", "ぱっつん", "なし"]
    static let faces = ["まるい", "すっきり", "面長", "ふっくら", "たまご型", "四角", "逆三角", "小顔"]
    static let expressions = ["笑顔", "おだやか", "ウインク", "にっこり", "びっくり", "大笑い", "への字", "にやり", "口を結ぶ"]
    static let eyeStyles = ["ふつう", "まるい", "細め", "にこにこ", "ぱっちり", "たれ目", "つり目", "まつげ"]
    static let browStyles = ["ふつう", "太め", "きりっと", "アーチ", "細い", "困り眉"]
    static let beardStyles = ["なし", "口ひげ", "あごひげ", "無精ひげ", "フル", "ちょびひげ"]
    static let accessories = ["なし", "ピアス", "ヘアピン", "リボン", "ヘッドバンド", "そばかす", "ヒジャブ"]
    static let glassesStyles = ["スクエア", "まる", "サングラス", "細フレーム", "ハーフリム", "大きめ"]
    static let clothes = ["シンプル", "スーツ", "シャツ", "ポロシャツ", "ボーダー"]
    static let noses = ["ふつう", "小さめ", "まるい", "すっきり"]
    static func png(_ configuration: StaffAvatarConfiguration) -> Data? {
        guard let image = render(configuration, size: 640).cgImage,
              let json = try? JSONEncoder().encode(configuration),
              let text = String(data: json, encoding: .utf8) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        let properties: [String: Any] = [kCGImagePropertyPNGDictionary as String: ["Description": "hotelshift-avatar-v1:" + text]]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
    static func restored(from data: Data?) -> StaffAvatarConfiguration? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let png = properties[kCGImagePropertyPNGDictionary as String] as? [String: Any],
              let text = png["Description"] as? String,
              text.hasPrefix("hotelshift-avatar-v1:"), text.utf8.count < 16000,
              let json = String(text.dropFirst("hotelshift-avatar-v1:".count)).data(using: .utf8),
              var value = try? JSONDecoder().decode(StaffAvatarConfiguration.self, from: json) else { return nil }
        value.skin = min(skins.count - 1, max(0, value.skin))
        value.hairColor = min(hairs.count - 1, max(0, value.hairColor))
        value.background = min(backgrounds.count - 1, max(0, value.background))
        value.outfit = min(outfits.count - 1, max(0, value.outfit))
        if let color = value.hijabColor { value.hijabColor = min(outfits.count - 1, max(0, color)) }
        value.eyeScale = value.eyeScale.isFinite ? min(1.3, max(0.8, value.eyeScale)) : 1
        value.eyeSpacing = value.eyeSpacing.isFinite ? min(1.15, max(0.85, value.eyeSpacing)) : 1
        value.mouthScale = value.mouthScale.isFinite ? min(1.2, max(0.8, value.mouthScale)) : 1
        return value
    }
    static func render(_ c: StaffAvatarConfiguration, size: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            let g = context.cgContext
            g.scaleBy(x: size / 320, y: size / 320)
            func mixed(_ color: UIColor, white: CGFloat) -> UIColor {
                var r: CGFloat = 0, green: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
                color.getRed(&r, green: &green, blue: &b, alpha: &a)
                return UIColor(red: r + (1-r)*white, green: green + (1-green)*white, blue: b + (1-b)*white, alpha: a)
            }
            func shaded(_ path: UIBezierPath, _ color: UIColor) {
                guard c.dimensional else { color.setFill(); path.fill(); return }
                g.saveGState(); path.addClip()
                let colors = [mixed(color, white: 0.22).cgColor, color.cgColor, color.withAlphaComponent(1).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.6, 1]) {
                    let bounds = path.bounds
                    g.drawLinearGradient(gradient, start: CGPoint(x: bounds.minX, y: bounds.minY), end: CGPoint(x: bounds.maxX, y: bounds.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                    g.setBlendMode(.multiply)
                    let shade = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.2).cgColor] as CFArray
                    if let shadow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: shade, locations: [0, 1]) {
                        g.drawLinearGradient(shadow, start: CGPoint(x: bounds.midX, y: bounds.midY), end: CGPoint(x: bounds.maxX, y: bounds.maxY), options: .drawsAfterEndLocation)
                    }
                }
                g.restoreGState()
            }
            func ellipse(_ rect: CGRect, _ color: UIColor) { shaded(UIBezierPath(ovalIn: rect), color) }
            func stroke(_ points: [CGPoint], color: UIColor, width: CGFloat) {
                guard let first = points.first else { return }
                let p = UIBezierPath(); p.move(to: first)
                for point in points.dropFirst() { p.addLine(to: point) }
                p.lineWidth = width; p.lineCapStyle = .round; p.lineJoinStyle = .round; color.setStroke(); p.stroke()
            }
            backgrounds[c.background].setFill(); g.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
            let skin = skins[c.skin], hair = hairs[c.hairColor]
            let wearsHijab = c.accessory == "ヒジャブ"
            let fabric = outfits[c.hijabColor ?? c.outfit]
            let ink = UIColor(red: 0.16, green: 0.12, blue: 0.12, alpha: 1)
            if !wearsHijab {
            if c.hair == "ポニーテール" { ellipse(CGRect(x: 213, y: 104, width: 48, height: 146), hair) }
            if c.hair == "三つ編み" { for i in 0..<5 { ellipse(CGRect(x: 213 + (i % 2) * 8, y: 116 + i * 23, width: 34, height: 36), hair) } }
            if c.hair == "ツインテール" {
                for x in [CGFloat(51), CGFloat(221)] { ellipse(CGRect(x: x, y: 95, width: 48, height: 153), hair) }
            }
            if c.hair == "アフロ" { ellipse(CGRect(x: 59, y: 15, width: 202, height: 208), hair) }
            if c.hair == "ロング" { ellipse(CGRect(x: 75, y: 40, width: 170, height: 238), hair) }
            if c.hair == "ボブ" { ellipse(CGRect(x: 75, y: 43, width: 170, height: 185), hair) }
            if c.hair == "おだんご" { ellipse(CGRect(x: 127, y: 15, width: 66, height: 60), hair) }
            }
            ellipse(CGRect(x: 53, y: 238, width: 214, height: 160), outfits[c.outfit])
            if c.clothing == "ボーダー" {
                outfits[c.outfit].withAlphaComponent(0.4).setFill()
                for y in stride(from: 273, through: 315, by: 14) { UIColor.white.withAlphaComponent(0.55).setFill(); UIBezierPath(rect: CGRect(x: 90, y: y, width: 140, height: 5)).fill() }
            }
            if ["シャツ", "スーツ", "ポロシャツ"].contains(c.clothing) {
                let collar = UIBezierPath(); collar.move(to: CGPoint(x: 132, y: 251)); collar.addLine(to: CGPoint(x: 160, y: 278)); collar.addLine(to: CGPoint(x: 188, y: 251)); collar.addLine(to: CGPoint(x: 179, y: 297)); collar.addLine(to: CGPoint(x: 141, y: 297)); collar.close(); UIColor.white.setFill(); collar.fill()
                if c.clothing == "スーツ" { let tie = UIBezierPath(); tie.move(to: CGPoint(x: 160, y: 273)); tie.addLine(to: CGPoint(x: 168, y: 306)); tie.addLine(to: CGPoint(x: 160, y: 315)); tie.addLine(to: CGPoint(x: 152, y: 306)); tie.close(); UIColor.systemBlue.setFill(); tie.fill() }
                if c.clothing == "ポロシャツ" { stroke([CGPoint(x: 160, y: 279), CGPoint(x: 160, y: 311)], color: .white, width: 3) }
            }
            skin.setFill(); UIBezierPath(roundedRect: CGRect(x: 139, y: 218, width: 42, height: 48), cornerRadius: 16).fill()
            if !wearsHijab {
                ellipse(CGRect(x: 78, y: 130, width: 26, height: 41), skin)
                ellipse(CGRect(x: 216, y: 130, width: 26, height: 41), skin)
            } else {
                ellipse(CGRect(x: 69, y: 30, width: 182, height: 244), fabric)
                let drape = UIBezierPath(); drape.move(to: CGPoint(x: 84, y: 174))
                drape.addQuadCurve(to: CGPoint(x: 65, y: 289), controlPoint: CGPoint(x: 78, y: 254))
                drape.addQuadCurve(to: CGPoint(x: 255, y: 289), controlPoint: CGPoint(x: 160, y: 323))
                drape.addQuadCurve(to: CGPoint(x: 236, y: 174), controlPoint: CGPoint(x: 242, y: 254))
                drape.close(); fabric.setFill(); drape.fill()
                stroke([CGPoint(x: 104, y: 224), CGPoint(x: 136, y: 264), CGPoint(x: 214, y: 286)], color: UIColor.white.withAlphaComponent(0.18), width: 3)
            }
            let face: CGRect
            switch c.face {
            case "すっきり": face = CGRect(x: 99, y: 54, width: 122, height: 184)
            case "面長": face = CGRect(x: 100, y: 48, width: 120, height: 195)
            case "ふっくら": face = CGRect(x: 83, y: 66, width: 154, height: 170)
            case "たまご型": face = CGRect(x: 95, y: 60, width: 130, height: 179)
            case "四角": face = CGRect(x: 90, y: 65, width: 140, height: 171)
            case "逆三角": face = CGRect(x: 89, y: 57, width: 142, height: 181)
            case "小顔": face = CGRect(x: 104, y: 70, width: 112, height: 158)
            default: face = CGRect(x: 90, y: 66, width: 140, height: 170)
            }
            if c.face == "四角" {
                skin.setFill(); UIBezierPath(roundedRect: face, cornerRadius: 38).fill()
            } else if c.face == "逆三角" {
                let outline = UIBezierPath(); outline.move(to: CGPoint(x: 93, y: 112))
                outline.addCurve(to: CGPoint(x: 160, y: 238), controlPoint1: CGPoint(x: 85, y: 193), controlPoint2: CGPoint(x: 143, y: 235))
                outline.addCurve(to: CGPoint(x: 227, y: 112), controlPoint1: CGPoint(x: 177, y: 235), controlPoint2: CGPoint(x: 235, y: 193))
                outline.addCurve(to: CGPoint(x: 93, y: 112), controlPoint1: CGPoint(x: 235, y: 38), controlPoint2: CGPoint(x: 85, y: 38))
                outline.close(); skin.setFill(); outline.fill()
            } else { ellipse(face, skin) }
            if c.hair != "なし" && !wearsHijab {
                let p = UIBezierPath(); p.move(to: CGPoint(x: 92, y: 142))
                p.addCurve(to: CGPoint(x: 112, y: 54), controlPoint1: CGPoint(x: 75, y: 90), controlPoint2: CGPoint(x: 91, y: 63))
                p.addCurve(to: CGPoint(x: 229, y: 135), controlPoint1: CGPoint(x: 200, y: 12), controlPoint2: CGPoint(x: 250, y: 76))
                p.addLine(to: CGPoint(x: 214, y: 105))
                p.addQuadCurve(to: CGPoint(x: 122, y: 97), controlPoint: CGPoint(x: 180, y: 113))
                p.addLine(to: CGPoint(x: 92, y: 142)); p.close(); shaded(p, hair)
                if c.dimensional {
                    for offset in [CGFloat(0), 15, 30] {
                        let lock = UIBezierPath(); lock.move(to: CGPoint(x: 99 + offset * 0.3, y: 109 - offset * 0.7))
                        lock.addCurve(to: CGPoint(x: 211 - offset * 0.3, y: 80 - offset * 0.5), controlPoint1: CGPoint(x: 116, y: 35 - offset * 0.15), controlPoint2: CGPoint(x: 180, y: 42 - offset * 0.1))
                        lock.lineWidth = 12; lock.lineCapStyle = .round
                        mixed(hair, white: 0.1).setStroke(); lock.stroke()
                        lock.lineWidth = 2; mixed(hair, white: 0.2).setStroke(); lock.stroke()
                    }
                }
                if ["マッシュ", "ぱっつん", "前髪", "ボブ"].contains(c.hair) {
                    hair.setFill()
                    UIBezierPath(roundedRect: CGRect(x: 103, y: 76, width: 114, height: 47), cornerRadius: 13).fill()
                }
                if c.hair == "ベリーショート" || c.hair == "刈り上げ" {
                    skin.setFill(); UIBezierPath(roundedRect: CGRect(x: 105, y: 88, width: 110, height: 34), cornerRadius: 8).fill()
                }
                if c.hair == "モヒカン" { ellipse(CGRect(x: 144, y: 12, width: 38, height: 88), hair) }
                if c.hair == "外はね" {
                    for x in [CGFloat(75), CGFloat(219)] { ellipse(CGRect(x: x, y: 173, width: 29, height: 41), hair) }
                }
                if c.hair == "サイド分け" { stroke([CGPoint(x: 118, y: 62), CGPoint(x: 130, y: 88)], color: skin, width: 5) }
                if c.hair == "センター分け" {
                    stroke([CGPoint(x: 160, y: 59), CGPoint(x: 160, y: 93)], color: skin, width: 7)
                }
                if c.hair == "ウェーブ" {
                    for x in stride(from: 97, through: 202, by: 21) { ellipse(CGRect(x: CGFloat(x), y: 77, width: 35, height: 37), hair) }
                }
                if c.hair == "カール" {
                    for x in stride(from: 92, through: 212, by: 24) { ellipse(CGRect(x: CGFloat(x), y: CGFloat(49 + (x % 3) * 5), width: 39, height: 47), hair) }
                }
            }
            let browWidth: CGFloat = c.eyebrows == "太め" ? 7 : c.eyebrows == "細い" ? 2 : 4
            let rise: CGFloat = c.eyebrows == "きりっと" ? 6 : 0
            if c.eyebrows == "アーチ" || c.eyebrows == "困り眉" {
                let d: CGFloat = c.eyebrows == "アーチ" ? -8 : 8
                stroke([CGPoint(x: 115, y: 130), CGPoint(x: 126, y: 126 + d), CGPoint(x: 137, y: 130)], color: hair, width: browWidth)
                stroke([CGPoint(x: 183, y: 130), CGPoint(x: 194, y: 126 + d), CGPoint(x: 205, y: 130)], color: hair, width: browWidth)
            } else {
            stroke([CGPoint(x: 115, y: 130 + rise), CGPoint(x: 137, y: 127)], color: hair, width: browWidth)
            stroke([CGPoint(x: 183, y: 127), CGPoint(x: 205, y: 130 + rise)], color: hair, width: browWidth)
            }
            for x in [CGFloat(160 - 35 * c.eyeSpacing), CGFloat(160 + 35 * c.eyeSpacing)] {
                if c.eyes == "にこにこ" || (c.expression == "ウインク" && x > 160) {
                    stroke([CGPoint(x: x - 8, y: 151), CGPoint(x: x, y: 145), CGPoint(x: x + 8, y: 151)], color: ink, width: 4)
                } else {
                    let width: CGFloat = (c.eyes == "まるい" ? 15 : c.eyes == "細め" ? 8 : 10) * CGFloat(c.eyeScale)
                    let height: CGFloat = (c.eyes == "細め" ? 8 : c.eyes == "まるい" ? 18 : 14) * CGFloat(c.eyeScale)
                    if ["たれ目", "つり目"].contains(c.eyes) {
                        let delta: CGFloat = c.eyes == "たれ目" ? 4 : -4
                        stroke([CGPoint(x: x - 7, y: 148 - delta), CGPoint(x: x + 7, y: 148 + delta)], color: ink, width: 4)
                    } else if c.eyes == "ぱっちり" || c.eyes == "まつげ" {
                        ellipse(CGRect(x: x - 8, y: 138, width: 16, height: 22), .white)
                        ellipse(CGRect(x: x - 5, y: 141, width: 10, height: 16), ink)
                        if c.eyes == "まつげ" { stroke([CGPoint(x: x - 8, y: 142), CGPoint(x: x - 13, y: 136)], color: ink, width: 2) }
                    } else if c.dimensional {
                        let w: CGFloat = (c.eyes == "細め" ? 28.0 : 36.0) * CGFloat(c.eyeScale)
                        let h: CGFloat = (c.eyes == "細め" ? 20.0 : 37.0) * CGFloat(c.eyeScale)
                        let rect = CGRect(x: x - w / 2, y: 150 - h / 2, width: w, height: h)
                        ellipse(rect.insetBy(dx: -1, dy: -2), skin.withAlphaComponent(0.6))
                        ellipse(rect, .white)
                        ellipse(CGRect(x: x - w * 0.28, y: 150 - h * 0.45, width: w * 0.56, height: h * 0.9), UIColor(red: 0.22, green: 0.13, blue: 0.09, alpha: 1))
                        ellipse(CGRect(x: x - w * 0.16, y: 150 - h * 0.28, width: w * 0.32, height: h * 0.56), ink)
                        ellipse(CGRect(x: x - 3, y: 140, width: 6, height: 7), .white)
                    } else {
                        ellipse(CGRect(x: x - width / 2, y: 150 - height / 2, width: width, height: height), ink)
                    }
                }
            }
            if c.dimensional {
                ellipse(CGRect(x: 148, y: 166, width: 25, height: 21), skin)
                ellipse(CGRect(x: 107, y: 172, width: 22, height: 10), UIColor.systemPink.withAlphaComponent(0.08))
                ellipse(CGRect(x: 192, y: 172, width: 22, height: 10), UIColor.systemPink.withAlphaComponent(0.08))
            } else {
                if c.nose == "まるい" { ellipse(CGRect(x: 153, y: 165, width: 14, height: 12), ink.withAlphaComponent(0.18)) }
                else {
                    let length: CGFloat = c.nose == "小さめ" ? 12 : c.nose == "すっきり" ? 26 : 23
                    stroke([CGPoint(x: 160, y: 153), CGPoint(x: 154, y: 153 + length), CGPoint(x: 165, y: 153 + length)], color: ink.withAlphaComponent(0.35), width: c.nose == "すっきり" ? 2 : 3)
                }
            }
            g.saveGState()
            g.translateBy(x: 160, y: 199); g.scaleBy(x: CGFloat(c.mouthScale), y: 1); g.translateBy(x: -160, y: -199)
            if c.expression == "への字" {
                stroke([CGPoint(x: 144, y: 204), CGPoint(x: 160, y: 194), CGPoint(x: 176, y: 204)], color: ink, width: 4)
            } else if c.expression == "口を結ぶ" {
                stroke([CGPoint(x: 151, y: 198), CGPoint(x: 169, y: 198)], color: ink, width: 3)
            } else if c.expression == "にやり" {
                stroke([CGPoint(x: 143, y: 199), CGPoint(x: 166, y: 202), CGPoint(x: 180, y: 191)], color: ink, width: 4)
            } else if c.expression == "大笑い" {
                ellipse(CGRect(x: 138, y: 187, width: 44, height: 31), ink)
                UIColor.white.setFill(); UIBezierPath(roundedRect: CGRect(x: 143, y: 188, width: 34, height: 8), cornerRadius: 3).fill()
            } else if c.expression == "おだやか" {
                stroke([CGPoint(x: 145, y: 199), CGPoint(x: 175, y: 199)], color: ink, width: 4)
            } else if c.expression == "びっくり" {
                ellipse(CGRect(x: 150, y: 188, width: 20, height: 25), ink)
            } else if c.expression == "にっこり" {
                ellipse(CGRect(x: 139, y: 187, width: 42, height: 25), ink)
                UIColor.white.setFill(); UIBezierPath(roundedRect: CGRect(x: 143, y: 188, width: 34, height: 8), cornerRadius: 3).fill()
            } else {
                let p = UIBezierPath(); p.move(to: CGPoint(x: 140, y: 191))
                p.addQuadCurve(to: CGPoint(x: 180, y: 191), controlPoint: CGPoint(x: 160, y: 218))
                p.lineWidth = 4; p.lineCapStyle = .round; ink.setStroke(); p.stroke()
            }
            g.restoreGState()
            if c.beard == "フル" { stroke([CGPoint(x: 119, y: 199), CGPoint(x: 134, y: 223), CGPoint(x: 160, y: 232), CGPoint(x: 186, y: 223), CGPoint(x: 201, y: 199)], color: hair, width: 10) }
            if c.beard == "無精ひげ" { for x in stride(from: 136, through: 184, by: 8) { stroke([CGPoint(x: x, y: 218), CGPoint(x: x - 2, y: 223)], color: hair, width: 1) } }
            if c.beard == "ちょびひげ" { stroke([CGPoint(x: 154, y: 183), CGPoint(x: 166, y: 183)], color: hair, width: 5) }
            if c.beard == "口ひげ" {
                ellipse(CGRect(x: 140, y: 181, width: 22, height: 8), hair)
                ellipse(CGRect(x: 158, y: 181, width: 22, height: 8), hair)
            } else if c.beard == "あごひげ" {
                ellipse(CGRect(x: 144, y: 215, width: 32, height: 17), hair)
            }
            if c.accessory == "リボン" { ellipse(CGRect(x: 100, y: 69, width: 25, height: 17), .systemPink); ellipse(CGRect(x: 121, y: 69, width: 25, height: 17), .systemPink) }
            if c.accessory == "ヘッドバンド" { stroke([CGPoint(x: 100, y: 103), CGPoint(x: 130, y: 85), CGPoint(x: 188, y: 85), CGPoint(x: 220, y: 103)], color: outfits[c.outfit], width: 9) }
            if c.accessory == "そばかす" { for x in [112, 121, 130, 190, 199, 208] { ellipse(CGRect(x: x, y: x % 2 == 0 ? 169 : 174, width: 2, height: 2), .brown) } }
            if c.accessory == "ピアス" {
                for x in [CGFloat(89), CGFloat(231)] { ellipse(CGRect(x: x - 4, y: 161, width: 8, height: 11), .systemYellow) }
            } else if c.accessory == "ヘアピン" {
                stroke([CGPoint(x: 105, y: 99), CGPoint(x: 127, y: 87)], color: .systemPink, width: 7)
            }
            if c.glasses {
                for x in [CGFloat(107), CGFloat(177)] {
                    let rect = CGRect(x: x, y: 137, width: 37, height: 30)
                    let p = c.glassesShape == "まる" ? UIBezierPath(ovalIn: rect) : UIBezierPath(roundedRect: rect, cornerRadius: 6)
                    if c.glassesShape == "サングラス" { ink.withAlphaComponent(0.85).setFill(); p.fill() }
                    p.lineWidth = c.glassesShape == "細フレーム" ? 1.5 : 3; ink.setStroke(); p.stroke()
                    if c.glassesShape == "大きめ" { let outer = UIBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerRadius: 9); outer.lineWidth = 2; outer.stroke() }
                    if c.glassesShape == "ハーフリム" { skin.setStroke(); let bottom = UIBezierPath(); bottom.move(to: CGPoint(x: x + 5, y: 167)); bottom.addLine(to: CGPoint(x: x + 32, y: 167)); bottom.lineWidth = 4; bottom.stroke() }
                }
                stroke([CGPoint(x: 144, y: 147), CGPoint(x: 177, y: 147)], color: ink, width: 3)
            }
        }
    }
}

private struct StaffAvatarCreator: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: StaffAvatarConfiguration
    @State private var saveError = false
    @State private var copied = false
    @State private var sourceItem: PhotosPickerItem?
    @State private var analysing = false
    @State private var analysisError: String?
    @State private var analysisNotice: String?
    @State private var analysisTask: Task<Void, Never>?
    @State private var analysisRequest = UUID()
    let sourcePhoto: Data?
    let onUse: (StaffAvatarConfiguration, Data) -> Void
    init(initial: StaffAvatarConfiguration, sourcePhoto: Data?, onUse: @escaping (StaffAvatarConfiguration, Data) -> Void) {
        _configuration = State(initialValue: StaffAvatarDrawing.restored(from: sourcePhoto) ?? initial)
        self.sourcePhoto = sourcePhoto; self.onUse = onUse
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if usesSideBySide(in: geometry.size) {
                    HStack(spacing: 0) {
                        avatarPreview
                            .frame(width: min(420, max(180, geometry.size.width * 0.38)))
                        Divider()
                        settingsForm.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        avatarPreview.frame(height: min(330, geometry.size.height * 0.37))
                        Divider()
                        settingsForm.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .onChange(of: sourceItem) { _, item in
                guard let item else { return }
                startAnalysis {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw StaffAvatarPhotoError.unreadable }
                    return data
                }
            }
            .onDisappear { analysisTask?.cancel(); analysisRequest = UUID() }
            .onChange(of: configuration) { _, _ in copied = false }
            .navigationTitle("アバターを作成").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("このアバターを使う") {
                        guard let data = StaffAvatarDrawing.png(configuration) else { saveError = true; return }
                        onUse(configuration, data); dismiss()
                    }.disabled(analysing)
                }
            }
            .alert("アバターを作成できません", isPresented: Binding(
                get: { analysisError != nil || saveError },
                set: { if !$0 { analysisError = nil; saveError = false } }
            )) {
                Button("OK", role: .cancel) { analysisError = nil; saveError = false }
            } message: { Text(analysisError ?? "画像を作成できませんでした。もう一度お試しください。") }
        }
    }
    private func usesSideBySide(in size: CGSize) -> Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return UIDevice.current.userInterfaceIdiom == .pad && size.width > size.height
        #endif
    }
    private var avatarPreview: some View {
        GeometryReader { geometry in
            let side = max(48, min(360, min(geometry.size.width - 32, geometry.size.height - 110)))
            VStack(spacing: 12) {
                Text("プレビュー").font(.headline)
                Image(uiImage: StaffAvatarDrawing.render(configuration, size: 640))
                    .resizable().scaledToFit().frame(width: side, height: side)
                    .clipShape(Circle())
                    .accessibilityLabel("作成中のアバター")
                Button {
                    guard let data = StaffAvatarDrawing.png(configuration) else { saveError = true; return }
                    UIPasteboard.general.setData(data, forPasteboardType: UTType.png.identifier)
                    copied = true
                } label: {
                    Label(copied ? "画像をコピーしました" : "画像をコピー", systemImage: "doc.on.doc")
                        .frame(minHeight: 44)
                }.buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }
    private var settingsForm: some View {
            Form {
                Section("写真から作成・端末内処理") {
                    PhotosPicker(selection: $sourceItem, matching: .images) {
                        Label("顔写真を選んでアバター化", systemImage: "person.crop.rectangle")
                    }.disabled(analysing)
                    if let sourcePhoto, StaffAvatarDrawing.restored(from: sourcePhoto) == nil {
                        Button("登録中の写真から作成") { startAnalysis { sourcePhoto } }.disabled(analysing)
                    }
                    if analysing { ProgressView("顔の特徴を読み取り中…") }
                    if let analysisNotice { Text(analysisNotice).font(.footnote).foregroundStyle(.secondary) }
                    Text("顔が1人、正面に写った写真を選んでください。輪郭・目・口と肌色の目安を反映します。写真をサーバーへ送信しません。髪型などは下で調整できます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.buttonStyle(.borderless)
                Section {
                    Button { randomize() } label: {
                        Label("おまかせで組み合わせる", systemImage: "shuffle")
                    }.buttonStyle(.borderless)
                }
                Section("顔と表情") {
                    VStack(alignment: .leading) {
                        Text("目の大きさ"); Slider(value: $configuration.eyeScale, in: 0.8...1.3)
                        Text("目の間隔"); Slider(value: $configuration.eyeSpacing, in: 0.85...1.15)
                        Text("口の幅"); Slider(value: $configuration.mouthScale, in: 0.8...1.2)
                    }
                    Picker("輪郭", selection: $configuration.face) {
                        ForEach(StaffAvatarDrawing.faces, id: \.self) { Text($0).tag($0) }
                    }
                    swatches("肌の色", colors: StaffAvatarDrawing.skins, selection: $configuration.skin)
                    Picker("表情", selection: $configuration.expression) {
                        ForEach(StaffAvatarDrawing.expressions, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("鼻", selection: $configuration.nose) {
                        ForEach(StaffAvatarDrawing.noses, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("目", selection: $configuration.eyes) {
                        ForEach(StaffAvatarDrawing.eyeStyles, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("眉", selection: $configuration.eyebrows) {
                        ForEach(StaffAvatarDrawing.browStyles, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("ひげ", selection: $configuration.beard) {
                        ForEach(StaffAvatarDrawing.beardStyles, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("メガネ", isOn: $configuration.glasses)
                    if configuration.glasses {
                        Picker("メガネの形", selection: $configuration.glassesShape) {
                            ForEach(StaffAvatarDrawing.glassesStyles, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Picker("小物・かぶりもの", selection: $configuration.accessory) {
                        ForEach(StaffAvatarDrawing.accessories, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("髪") {
                    Picker("髪型", selection: $configuration.hair) {
                        ForEach(StaffAvatarDrawing.hairStyles, id: \.self) { Text($0).tag($0) }
                    }
                    swatches("髪の色", colors: StaffAvatarDrawing.hairs, selection: $configuration.hairColor)
                }.disabled(configuration.accessory == "ヒジャブ")
                if configuration.accessory == "ヒジャブ" {
                    Section("ヒジャブ") {
                        swatches("布の色", colors: StaffAvatarDrawing.outfits, selection: Binding(
                            get: { configuration.hijabColor ?? configuration.outfit },
                            set: { configuration.hijabColor = $0 }
                        ))
                    }
                }
                Section("服と背景") {
                    Picker("服装", selection: $configuration.clothing) {
                        ForEach(StaffAvatarDrawing.clothes, id: \.self) { Text($0).tag($0) }
                    }
                    swatches("服の色", colors: StaffAvatarDrawing.outfits, selection: $configuration.outfit)
                    swatches("背景色", colors: StaffAvatarDrawing.backgrounds, selection: $configuration.background)
                }
                Section {
                    Text("「このアバターを使う」でスタッフ写真に反映します。スタッフ情報の「保存」で登録が完了します。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
    }
    @MainActor private func startAnalysis(_ load: @escaping () async throws -> Data) {
        analysisTask?.cancel()
        let request = UUID(); analysisRequest = request
        analysing = true; analysisError = nil; analysisNotice = nil
        let original = configuration
        analysisTask = Task { @MainActor in
            defer { if analysisRequest == request { analysing = false; sourceItem = nil } }
            do {
                let bytes = try await load()
                let result = try await Task.detached(priority: .userInitiated) {
                    try StaffAvatarPhotoAnalysis.suggest(bytes, initial: original)
                }.value
                guard !Task.isCancelled, analysisRequest == request else { return }
                guard configuration == original else {
                    analysisNotice = "読み取り中に調整した内容を優先しました。写真から作り直す場合は再度選んでください。"
                    return
                }
                configuration = result
                analysisNotice = "写真から顔の特徴を反映しました。髪型・色・表情を確認して調整してください。"
            } catch {
                guard !Task.isCancelled, analysisRequest == request else { return }
                analysisError = (error as? StaffAvatarPhotoError)?.errorDescription ?? "写真を解析できませんでした。明るい場所で正面から写った写真をお試しください。"
            }
        }
    }
    private func randomize() {
        var next = StaffAvatarConfiguration()
        next.skin = Int.random(in: StaffAvatarDrawing.skins.indices)
        next.hairColor = Int.random(in: StaffAvatarDrawing.hairs.indices)
        next.background = Int.random(in: StaffAvatarDrawing.backgrounds.indices)
        next.outfit = Int.random(in: StaffAvatarDrawing.outfits.indices)
        next.face = StaffAvatarDrawing.faces.randomElement() ?? "まるい"
        next.hair = StaffAvatarDrawing.hairStyles.randomElement() ?? "ショート"
        next.expression = StaffAvatarDrawing.expressions.randomElement() ?? "笑顔"
        next.eyes = StaffAvatarDrawing.eyeStyles.randomElement() ?? "ふつう"
        next.eyebrows = StaffAvatarDrawing.browStyles.randomElement() ?? "ふつう"
        next.beard = StaffAvatarDrawing.beardStyles.randomElement() ?? "なし"
        next.accessory = StaffAvatarDrawing.accessories.randomElement() ?? "なし"
        next.hijabColor = Int.random(in: StaffAvatarDrawing.outfits.indices)
        next.clothing = StaffAvatarDrawing.clothes.randomElement() ?? "シンプル"
        next.nose = StaffAvatarDrawing.noses.randomElement() ?? "ふつう"
        next.glasses = Bool.random()
        next.glassesShape = StaffAvatarDrawing.glassesStyles.randomElement() ?? "スクエア"
        configuration = next
    }
    private func swatches(_ title: String, colors: [UIColor], selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(colors.indices, id: \.self) { index in
                    Button { selection.wrappedValue = index } label: {
                        Circle().fill(Color(uiColor: colors[index])).frame(width: 36, height: 36)
                            .overlay(Circle().stroke(Color.primary.opacity(0.2)))
                            .overlay { if selection.wrappedValue == index { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .black) } }
                            .frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(title) \(index + 1)")
                        .accessibilityAddTraits(selection.wrappedValue == index ? .isSelected : [])
                }
            }
        }
    }
}

private enum StaffAvatarPhotoError: LocalizedError {
    case unreadable, noFace, multipleFaces, missingFeatures
    var errorDescription: String? {
        switch self {
        case .unreadable: return "画像を読み込めませんでした。別の写真を選んでください。"
        case .noFace: return "顔が見つかりませんでした。正面の顔が大きく写った写真を選んでください。"
        case .multipleFaces: return "複数の顔が見つかりました。1人だけ写った写真を選んでください。"
        case .missingFeatures: return "目や口を十分に読み取れませんでした。明るく、正面に近い写真を選んでください。"
        }
    }
}

private enum StaffAvatarPhotoAnalysis {
    // Vision and pixel sampling run locally; this path has no network calls.
    static func suggest(_ data: Data, initial: StaffAvatarConfiguration) throws -> StaffAvatarConfiguration {
        guard let image = ShiftPhotoProcessing.thumbnail(data, maxPixels: 1200)?.cgImage else { throw StaffAvatarPhotoError.unreadable }
        let request = VNDetectFaceLandmarksRequest()
        try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
        let faces = request.results ?? []
        guard !faces.isEmpty else { throw StaffAvatarPhotoError.noFace }
        guard faces.count == 1, let face = faces.first else { throw StaffAvatarPhotoError.multipleFaces }
        guard let features = face.landmarks,
              let left = features.leftEye, let right = features.rightEye,
              let lips = features.outerLips,
              left.pointCount >= 2, right.pointCount >= 2, lips.pointCount >= 4 else { throw StaffAvatarPhotoError.missingFeatures }
        func bounds(_ region: VNFaceLandmarkRegion2D) -> CGRect {
            let points = region.normalizedPoints
            let xs = points.map { CGFloat($0.x) }, ys = points.map { CGFloat($0.y) }
            return CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0,
                          width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
        }
        let box = face.boundingBox
        let width = box.width * CGFloat(image.width), height = box.height * CGFloat(image.height)
        guard width > 0, height > 0 else { throw StaffAvatarPhotoError.noFace }
        let l = bounds(left), r = bounds(right), mouth = bounds(lips)
        var result = initial
        let ratio = width / height
        result.face = ratio < 0.69 ? "面長" : ratio < 0.79 ? "すっきり" : ratio > 0.94 ? "ふっくら" : "まるい"
        let openness = ((l.height + r.height) * height) / max(1, (l.width + r.width) * width)
        result.eyeScale = min(1.3, max(0.8, 0.85 + Double(openness) * 0.7))
        result.eyeSpacing = min(1.15, max(0.85, Double(abs(l.midX - r.midX)) / 0.42))
        result.mouthScale = min(1.2, max(0.8, Double(mouth.width) / 0.4))
        result.eyes = "ふつう"
        result.expression = mouth.height * height / max(1, mouth.width * width) > 0.42 ? "にっこり" : "笑顔"
        // Cheek patches avoid hair, mouth and the eye area. Lighting remains a limitation.
        let samples = [CGFloat(0.25), CGFloat(0.75)].compactMap { x in
            sample(image, x: box.minX + box.width * x, y: box.minY + box.height * 0.36, radius: box.width * 0.045)
        }
        if !samples.isEmpty {
            let count = Double(samples.count)
            let rgb = (samples.reduce(0) { $0 + $1.0 } / count,
                       samples.reduce(0) { $0 + $1.1 } / count,
                       samples.reduce(0) { $0 + $1.2 } / count)
            result.skin = StaffAvatarDrawing.skins.indices.min { a, b in
                distance(rgb, StaffAvatarDrawing.skins[a]) < distance(rgb, StaffAvatarDrawing.skins[b])
            } ?? initial.skin
        }
        // Hair/eyewear/style are kept for the user to choose rather than guessed from landmarks.
        return result
    }
    private static func distance(_ rgb: (Double, Double, Double), _ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return pow(rgb.0 - Double(r), 2) + pow(rgb.1 - Double(g), 2) + pow(rgb.2 - Double(b), 2)
    }
    private static func sample(_ image: CGImage, x: CGFloat, y: CGFloat, radius: CGFloat) -> (Double, Double, Double)? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let rect = CGRect(x: (x - radius) * w, y: (1 - y - radius) * h,
                          width: radius * 2 * w, height: radius * 2 * h).integral
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !rect.isEmpty, let patch = image.cropping(to: rect) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 8 * 8 * 4)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(patch, in: CGRect(x: 0, y: 0, width: 8, height: 8)); return true
        }
        guard ok else { return nil }
        var sums = [Double](repeating: 0, count: 3)
        for pixel in 0..<64 { for channel in 0..<3 { sums[channel] += Double(bytes[pixel * 4 + channel]) / 255 } }
        return (sums[0] / 64, sums[1] / 64, sums[2] / 64)
    }
}
