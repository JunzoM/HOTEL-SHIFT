import SwiftUI
import PDFKit
import UIKit

struct ShiftCalendarView: View {
    @Environment(\.workspaceAppearance) private var workspaceAppearance
    private let initialDay: Date?
    @State private var appliedInitialDay = false
    init(initialDay: Date? = nil) { self.initialDay = initialDay }
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var month = Calendar.current.startOfMonth(for: Date())
    @AppStorage("hotelShift.dashboardSelectedDate") private var dashboardSelectedDateKey = ""
    // Keep the selected staff and date in one value so the sheet cannot open
    // before both pieces of state have updated on the first tap.
    @State private var editingSelection: ShiftEditSelection?
    @State private var selectedCell: ShiftCellSelection?
    @State private var detailRequest: ShiftRequest?
    @State private var pendingRequestConflictEdit: ShiftEditSelection?
    @State private var returnToRequestAfterEdit: UUID?
    @State private var showPrintInfo = false
    @State private var showPatterns = false
    @State private var pendingConflictEdit: ShiftEditSelection?
    @State private var returnToConflictsAfterEdit = false
    @StateObject private var workspace = ShiftWorkspaceControls()
    @State private var profileStaff: StaffMember?
    @State private var showLegend = false
    @State private var showDatePicker = false
    @State private var showNewLocation = false
    @State private var newLocationName = ""
    @State private var isPreparingPDF = false
    @State private var viewMode: ShiftCalendarMode = UIDevice.current.userInterfaceIdiom == .phone ? .day : .month
    @State private var minuteStep: Int = 15
    @State private var dayUsesTimeline = true
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var pdfPreview: PDFPreviewItem?
    private let calendar = Calendar.current
    private let labelWidth: CGFloat = 150

    private var dates: [Date] { (0..<calendar.range(of: .day, in: .month, for: month)!.count).compactMap { calendar.date(byAdding: .day, value: $0, to: month) } }

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Group {
                if viewMode == .month {
                    scheduleGrid(isWeek: false)
                } else if viewMode == .week {
                    scheduleGrid(isWeek: true)
                } else {
                    dayTimeline
                }
            }

        }
        .background(.white).padding(.horizontal, workspaceAppearance.inset(6)).padding(.bottom, workspaceAppearance.inset(4))
        .onChange(of: selectedDay) { _, date in
            dashboardSelectedDateKey = date.shiftDateKey
            month = calendar.startOfMonth(for: date)
        }
        .onChange(of: month) { _, date in
            if !calendar.isDate(selectedDay, equalTo: date, toGranularity: .month) { selectedDay = date }
        }
        .onChange(of: viewMode) { _, _ in workspace.reset() }
        .onChange(of: store.selectedLocationID) { _, _ in workspace.reset(); workspace.department = "すべて" }
        .sheet(item: $profileStaff) { person in
            ScheduleStaffProfileSheet(staffID: person.id, locationID: person.locationID,
                                      referenceDate: selectedDay).environmentObject(store)
        }
        .sheet(isPresented: $showLegend) { workspaceHelp }
        .popover(isPresented: $showDatePicker) {
            DatePicker("表示日", selection: $selectedDay, displayedComponents: .date)
                .datePickerStyle(.graphical).padding().frame(idealWidth: 330, maxWidth: 360)
        }
        .alert("店舗を追加", isPresented: $showNewLocation) {
            TextField("店舗名", text: $newLocationName)
            Button("キャンセル", role: .cancel) { newLocationName = "" }
            Button("追加") { store.addLocation(name: newLocationName); newLocationName = "" }
        }
        .sheet(isPresented: $showPatterns, onDismiss: {
            if let selection = pendingConflictEdit {
                pendingConflictEdit = nil
                editingSelection = selection
            }
        }) {
            ShiftPatternManager(month: month) { staffID, dateKey in
                guard let staff = store.selectedStaff.first(where: { $0.id == staffID }),
                      let date = Date.keyFormatter.date(from: dateKey) else { return }
                selectedDay = date
                month = calendar.startOfMonth(for: date)
                viewMode = .day
                pendingConflictEdit = ShiftEditSelection(staff: staff, date: date)
                returnToConflictsAfterEdit = true
                showPatterns = false
            }.environmentObject(store)
        }
        .sheet(item: $editingSelection, onDismiss: {
            // The conflict list is computed from the latest store data whenever
            // the pattern manager opens, including edits made in this sheet.
            if returnToConflictsAfterEdit {
                returnToConflictsAfterEdit = false
                showPatterns = true
            } else if let requestID = returnToRequestAfterEdit {
                returnToRequestAfterEdit = nil
                // Resolve the request again so approval status and shift conflict
                // are recalculated from the latest store data.
                if let request = (store.data.requests ?? []).first(where: { candidate in
                    candidate.id == requestID && candidate.locationID == store.selectedLocationID &&
                    store.selectedStaff.contains(where: { $0.id == candidate.staffID })
                }) {
                    detailRequest = request
                }
            }
        }) { selection in
            ShiftEditSheet(staff: selection.staff, date: selection.date)
                .environmentObject(store)
        }
        .sheet(item: $pdfPreview) { item in PDFOutputPreview(url: item.url, document: item.document) }
        .sheet(item: $detailRequest, onDismiss: {
            if let selection = pendingRequestConflictEdit {
                pendingRequestConflictEdit = nil
                editingSelection = selection
            }
        }) { request in
            RequestDetailSheet(request: request, staffName: store.data.staff.first(where: { $0.id == request.staffID })?.name ?? "不明なスタッフ") {
                guard let staff = store.selectedStaff.first(where: { $0.id == request.staffID }),
                      let date = Date.keyFormatter.date(from: request.dateKey) else { return }
                pendingRequestConflictEdit = ShiftEditSelection(staff: staff, date: date)
                returnToRequestAfterEdit = request.id
                selectedDay = date
                month = calendar.startOfMonth(for: date)
                viewMode = .day
                detailRequest = nil
            }
            .environmentObject(store)
        }
        .onAppear {
            guard !appliedInitialDay else { return }
            appliedInitialDay = true
            if let initialDay {
                selectedDay = Calendar.current.startOfDay(for: initialDay)
                month = calendar.startOfMonth(for: initialDay)
                dashboardSelectedDateKey = selectedDay.shiftDateKey
                viewMode = .day
                workspace.reset()
            } else if let selectedDate = Date.keyFormatter.date(from: dashboardSelectedDateKey) {
                month = calendar.startOfMonth(for: selectedDate)
                selectedDay = selectedDate
            }
        }
        // A sheet or selected cell belongs to the location where it was opened.
        // Clear transient selections when the hotel changes so an old staff ID
        // cannot be edited from the newly selected hotel's calendar.
        .onChange(of: store.selectedLocationID) { _, _ in
            editingSelection = nil
            selectedCell = nil
            detailRequest = nil
            showPatterns = false
            pendingConflictEdit = nil
            pendingRequestConflictEdit = nil
            returnToRequestAfterEdit = nil
            returnToConflictsAfterEdit = false
            pdfPreview = nil
        }
        .focusedSceneValue(\.shiftKeyboardActions, ShiftKeyboardActions(
            canUndo: workspace.editing && workspace.canUndo,
            canRedo: workspace.editing && workspace.canRedo,
            canExport: !isPreparingPDF,
            undo: { workspace.send(.undo) },
            redo: { workspace.send(.redo) },
            exportPDF: { prepareCalendarPDF() }
        ))
        .alert("PDFを作成できません", isPresented: $showPrintInfo) { Button("OK", role: .cancel) {} } message: { Text("シフト表PDFの作成に失敗しました。もう一度お試しください。") }
    }

    // FIXED495: View/edit controls above, centered date navigation beside history/filter below.
    @ViewBuilder private var workspaceHeader: some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            phoneWorkspaceHeader
        } else if horizontalSizeClass == .compact {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach([ShiftCalendarMode.month, .week, .day], id: \.self) { mode in
                        Button {
                            viewMode = mode
                        } label: {
                            Text(mode == .month ? "月" : mode == .week ? "週" : "日")
                                .frame(minWidth: 40, minHeight: 44)
                                .background(viewMode == mode ? Color.blue.opacity(0.12) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                        }
                        .accessibilityAddTraits(viewMode == mode ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                    Button(workspace.editing ? "編集中" : "編集する") { workspace.editing.toggle() }
                        .frame(minHeight: 44)
                    workspaceMenu(compact: true).frame(minWidth: 44, minHeight: 44)
                }
                periodControls(compact: true).frame(minHeight: 44)
                HStack {
                    Button { workspace.send(.undo) } label: {
                        Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44)
                    }.disabled(!workspace.editing || !workspace.canUndo).accessibilityLabel("取り消す")
                    Button { workspace.send(.redo) } label: {
                        Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44)
                    }.disabled(!workspace.editing || !workspace.canRedo).accessibilityLabel("やり直す")
                    Spacer(minLength: 0)
                    Menu {
                        Button("すべて") { workspace.department = "すべて" }
                        ForEach(Array(Set(store.selectedStaff.filter(\.isActive).map(\.department))).sorted(), id: \.self) { name in
                            Button(name) { workspace.department = name }
                        }
                    } label: {
                        Label("部署：\(workspace.department)", systemImage: "line.3.horizontal.decrease")
                            .lineLimit(1).frame(minHeight: 44)
                    }
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(red: 0.97, green: 0.98, blue: 1))
        } else {
            wideWorkspaceHeader
        }
    }

    private var phoneWorkspaceHeader: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Picker("表示期間", selection: $viewMode) {
                    Text("月").tag(ShiftCalendarMode.month)
                    Text("週").tag(ShiftCalendarMode.week)
                    Text("日").tag(ShiftCalendarMode.day)
                }.modifier(PhoneTabStyle())
                Button(workspace.editing ? "編集中" : "編集") { workspace.editing.toggle() }
                    .font(.subheadline.bold()).frame(minHeight: 44)
                    .modifier(AppActionStyle()).buttonBorderShape(.capsule)
                    .tint(workspace.editing ? .orange : .blue)
                workspaceMenu(compact: true).frame(minWidth: 36, minHeight: 44)
            }
            HStack(spacing: 4) {
                periodControls(compact: true)
                Spacer(minLength: 0)
                Menu {
                    Button("すべて") { workspace.department = "すべて" }
                    ForEach(Array(Set(store.selectedStaff.filter(\.isActive).map(\.department))).sorted(), id: \.self) { name in
                        Button(name) { workspace.department = name }
                    }
                } label: {
                    Image(systemName: workspace.department == "すべて" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .frame(width: 40, height: 44)
                }.accessibilityLabel("部署：\(workspace.department)")
            }
        }.padding(.horizontal, 8).padding(.vertical, 4)
            .overlay(alignment: .bottom) { Divider() }
    }
    private var wideWorkspaceHeader: some View {
        GeometryReader { geometry in
            let width = max(760, geometry.size.width - 24)
            let compact = width < 800
            let departmentWidth: CGFloat = compact ? 125 : 150
            ScrollView(.horizontal) {
                VStack(spacing: 4) {
                    ZStack {
                        HStack(spacing: 8) {
                        HStack(spacing: 2.4) {
                            modeButton("月", mode: .month)
                            modeButton("週", mode: .week)
                            modeButton("日", mode: .day)
                        }.padding(3.6).frame(width: 175.2)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 7.2))
                            .overlay(RoundedRectangle(cornerRadius: 7.2).stroke(Color.gray.opacity(0.2)))
                        editModeButton
                        }.frame(maxWidth: .infinity, alignment: .center)
                        HStack(spacing: 8) {
                            workspaceMenu(compact: compact)
                            if isPreparingPDF { ProgressView().controlSize(.small) }
                            else {
                                Label(store.storageWarning == nil ? "自動保存" : "保存を確認", systemImage: store.storageWarning == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 10)).foregroundStyle(store.storageWarning == nil ? Color.green : Color.orange)
                                    .labelStyle(.iconOnly).help(store.storageWarning ?? "変更は自動保存されます")
                            }
                        }.frame(maxWidth: .infinity, alignment: .trailing)
                    }.frame(width: width, height: 40)
                    HStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Button { workspace.send(.undo) } label: {
                                Image(systemName: "arrow.uturn.backward").font(.system(size: 18)).frame(width: 42, height: 34)
                            }.buttonStyle(.plain).disabled(!workspace.editing || !workspace.canUndo).accessibilityLabel("取り消す")
                            Button { workspace.send(.redo) } label: {
                                Image(systemName: "arrow.uturn.forward").font(.system(size: 18)).frame(width: 42, height: 34)
                            }.buttonStyle(.plain).disabled(!workspace.editing || !workspace.canRedo).accessibilityLabel("やり直す")
                            Menu {
                                Button("すべて") { workspace.department = "すべて" }
                                ForEach(Array(Set(store.selectedStaff.filter(\.isActive).map(\.department))).sorted(), id: \.self) { name in
                                    Button(name) { workspace.department = name }
                                }
                            } label: { Label("部署：\(workspace.department)", systemImage: "chevron.down").lineLimit(1) }
                                .buttonStyle(ScheduleToolbarButtonStyle()).frame(width: departmentWidth, alignment: .leading)
                        }
                        periodControls(compact: compact).fixedSize(horizontal: true, vertical: false)
                    }.frame(width: width, height: 34, alignment: .center)
                }.font(.caption).padding(.horizontal, 12)
            }.scrollIndicators(.hidden)
        }.frame(height: 80)
        .background(Color(red: 0.97, green: 0.98, blue: 1))
        .overlay(alignment: .bottom) { Divider() }
    }
    private var editModeButton: some View {
        Button { workspace.editing.toggle() } label: {
            Text(workspace.editing ? "編集中" : "編集する")
                .font(.system(size: 14.4, weight: .semibold))
                .foregroundStyle(workspace.editing ? Color.white : Color.blue)
                .frame(width: 92, height: 31.2)
                .background(workspace.editing ? Color.blue : Color.clear, in: RoundedRectangle(cornerRadius: 4.8))
                .padding(3.6)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 7.2))
                .overlay(RoundedRectangle(cornerRadius: 7.2).stroke(Color.gray.opacity(0.2)))
        }.buttonStyle(.plain)
    }
    private func modeButton(_ title: String, mode: ShiftCalendarMode) -> some View {
        Button { viewMode = mode } label: {
            Text(title).font(.system(size: 14.4, weight: .semibold))
                .foregroundStyle(viewMode == mode ? Color.white : Color.primary)
                .frame(width: 52.8, height: 31.2)
                .background(viewMode == mode ? Color.blue : Color.clear, in: RoundedRectangle(cornerRadius: 4.8))
        }.buttonStyle(.plain).accessibilityAddTraits(viewMode == mode ? .isSelected : [])
    }
    private func periodControls(compact: Bool) -> some View {
        HStack(spacing: compact ? 5 : 9) {
            Button { movePeriod(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 18)).frame(width: 36, height: 30) }.accessibilityLabel("前の期間")
            Button { showDatePicker = true } label: { Text(periodTitle(compact: compact)).font(.system(size: compact ? 12 : 14, weight: .semibold)).lineLimit(1) }
                .buttonStyle(.plain).accessibilityHint("日付を選択します")
            Button { movePeriod(1) } label: { Image(systemName: "chevron.right").font(.system(size: 18)).frame(width: 36, height: 30) }.accessibilityLabel("次の期間")
            Button("今日") { selectedDay = calendar.startOfDay(for: Date()); month = calendar.startOfMonth(for: Date()) }.buttonStyle(ScheduleToolbarButtonStyle())

        }.font(.caption)
    }
    private func locationMenu(compact: Bool) -> some View {
        Menu {
            ForEach(store.data.locations) { location in
                Button(location.name) { store.selectedLocationID = location.id }
            }
            Divider()
            Button("＋ 店舗を追加") { showNewLocation = true }
        } label: {
            if compact { Image(systemName: "building.2").frame(width: 30, height: 30) }
            else { Label(store.selectedLocation?.name ?? "店舗を選択", systemImage: "chevron.down").font(.caption.weight(.semibold)).lineLimit(1).frame(maxWidth: 135) }
        }.buttonStyle(ScheduleToolbarButtonStyle()).accessibilityLabel(store.selectedLocation?.name ?? "店舗を選択")
    }
    private func workspaceMenu(compact: Bool) -> some View {
        Menu {
            if UIDevice.current.userInterfaceIdiom == .phone {
                Button("取り消す") { workspace.send(.undo) }.disabled(!workspace.editing || !workspace.canUndo)
                Button("やり直す") { workspace.send(.redo) }.disabled(!workspace.editing || !workspace.canRedo)
                Divider()
            }
            if viewMode != .day {
                Button("セル選択を解除") { workspace.send(.toggleSelection) }.disabled(!workspace.editing)
                if viewMode == .week { Button("翌週の空欄へコピー") { workspace.send(.copyWeek) }.disabled(!workspace.editing) }
            } else {
                Button(dayUsesTimeline ? "詳細調整に切り替え" : "時間表に切り替え") { dayUsesTimeline.toggle(); workspace.reset() }
                Picker("時間の刻み", selection: $minuteStep) { Text("15分").tag(15); Text("30分").tag(30) }
            }
            Divider()
            Button("PDF / 印刷") { prepareCalendarPDF() }.disabled(isPreparingPDF)
            Button("凡例・希望休の件数・操作方法") { showLegend = true }
        } label: {
            if compact { Image(systemName: "ellipsis").frame(width: 28, height: 30) }
            else { Label("その他", systemImage: "ellipsis") }
        }.buttonStyle(ScheduleToolbarButtonStyle()).accessibilityLabel("その他のシフト操作")
    }
    private func periodTitle(compact: Bool) -> String {
        switch viewMode {
        case .month: return month.japaneseMonth
        case .day: return (compact ? "" : "\(calendar.component(.year, from: selectedDay))/") + ScheduleGridSupport.dateLabel(selectedDay) + "（" + selectedDay.formatted(.dateTime.weekday(.abbreviated)) + "）"
        case .week:
            let first = calendar.dateInterval(of: .weekOfYear, for: selectedDay)?.start ?? selectedDay
            let last = calendar.date(byAdding: .day, value: 6, to: first) ?? first
            return (compact ? "" : "\(calendar.component(.year, from: first))/") + ScheduleGridSupport.dateLabel(first) + "〜" + ScheduleGridSupport.dateLabel(last)
        }
    }
    private func movePeriod(_ direction: Int) {
        if viewMode == .month { month = calendar.date(byAdding: .month, value: direction, to: month) ?? month }
        else { selectedDay = calendar.date(byAdding: .day, value: direction * (viewMode == .week ? 7 : 1), to: selectedDay) ?? selectedDay }
    }
    @MainActor private func prepareCalendarPDF() {
        guard !isPreparingPDF else { return }
        isPreparingPDF = true
        let requestedMonth = month
        let location = store.selectedLocationID
        let revision = store.pdfRevision
        Task { @MainActor in
            defer { isPreparingPDF = false }
            let url = await store.exportShiftPDFAsync(month: requestedMonth)
            guard location == store.selectedLocationID, revision == store.pdfRevision, requestedMonth == month else { return }
            if let url, let document = PDFDocument(url: url), document.pageCount > 0 { pdfPreview = PDFPreviewItem(url: url, document: document) }
            else { showPrintInfo = true }
        }
    }
    private var workspaceHelp: some View {
        NavigationStack {
            List {
                Section("勤務区分") { ForEach(ShiftType.allCases) { type in HStack { ShiftPill(type: type); Spacer(); Text(type.start + "〜" + type.end).font(.caption) } } }
                Section("表示月の希望休・申請") {
                    requestLegend(color: .orange, title: "申請中", count: requestCount(.pending))
                    requestLegend(color: .green, title: "承認", count: requestCount(.approved))
                    requestLegend(color: .gray, title: "却下", count: requestCount(.rejected))
                }
                Section("編集") {
                    Text("「編集する」で下部に一括編集バーを表示します。週・月はセルをタップして複数選択し、勤務区分などを選んで適用します。長押しで個別編集できます。")
                    Text("セルの長押しで日シフトや時刻・休憩調整へ移動できます。日シフトは空欄タップで追加、バーの移動や両端で時刻を変更できます。")
                    Text("時間帯別人数は勤務帯と重なる人数です。休憩を控除した実配置人数ではありません。")
                }
            }.navigationTitle("シフト表の見方")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { showLegend = false } } }
        }
    }

    // FIXED478: Week and month share actual-time cells and pattern labels.
    private func scheduleGrid(isWeek: Bool) -> some View {
        IntegratedScheduleGrid(workspace: workspace, month: month, selectedDay: $selectedDay, isWeek: isWeek,
            edit: { staff, date in
                selectedCell = ShiftCellSelection(staff: staff, date: date)
                editingSelection = ShiftEditSelection(staff: staff, date: date)
            }, inspectRequest: { request in detailRequest = request },
            openDay: { date in selectedDay = date; viewMode = .day })
            .id(isWeek ? "week" : "month")
    }

    // FIXED477: EldiaShift-style daily timeline; retain the detailed slider workflow.
    private var dayTimeline: some View {
        Group {
            if dayUsesTimeline {
                IntegratedDayTimeline(workspace: workspace, day: selectedDay, minuteStep: $minuteStep)
                    .id(selectedDay.shiftDateKey + store.selectedLocationID.uuidString)
            } else {
                daySliderEditors
            }
        }.frame(maxHeight: .infinity)
    }

    private var daySliderEditors: some View {
        let dayKey = selectedDay.shiftDateKey
        let assignmentsByStaff = Dictionary(store.selectedAssignments(on: Set([dayKey]))
            .map { ($0.staffID, $0) }, uniquingKeysWith: { first, _ in first })
        let activeStaff = store.selectedStaff.filter(\.isActive)
        let approvedLeaveStaffIDs = Set(store.selectedRequestsUnsorted.lazy
            .filter { $0.dateKey == dayKey && $0.status == .approved }
            .map(\.staffID))
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(activeStaff) { staff in
                    let assignment = assignmentsByStaff[staff.id]
                    DayShiftTimeEditor(staff: staff, date: selectedDay, assignment: assignment, hasApprovedLeave: approvedLeaveStaffIDs.contains(staff.id), minuteStep: $minuteStep, editingEnabled: workspace.editing,
                        openStaffDetail: { profileStaff = staff }) { start, end, breakMinutes, breakStart in
                        store.setShiftTimes(staffID: staff.id, date: selectedDay, startMinutes: start, endMinutes: end, breakMinutes: breakMinutes, breakStartMinutes: breakStart)
                    }
                }
            }.padding(14)
        }.frame(maxHeight: .infinity).onChange(of: selectedDay) { _, date in dashboardSelectedDateKey = date.shiftDateKey; month = calendar.startOfMonth(for: date) }
    }

    private func isWorkingAssignment(_ assignment: ShiftAssignment) -> Bool {
        assignment.type != .off && assignment.type != .paidLeave && assignment.type != .afterNight
    }

    private func isApprovedLeaveConflict(assignment: ShiftAssignment?, request: ShiftRequest?) -> Bool {
        guard let assignment, let request else { return false }
        return request.status == .approved && isWorkingAssignment(assignment)
    }

    private func requestFor(staffID: UUID, date: Date) -> ShiftRequest? {
        let key = date.shiftDateKey
        return store.selectedRequestsUnsorted.first { request in
            request.staffID == staffID && request.dateKey == key
        }
    }

    @ViewBuilder
    private func requestMarker(_ request: ShiftRequest?) -> some View {
        if let request = request {
            Button {
                detailRequest = request
            } label: {
                Circle()
                    .fill(requestMarkerColor(request.status))
                    .frame(width: 10, height: 10)
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
            .accessibilityLabel("\(request.status.rawValue)の申請詳細を表示")
        }
    }

    private func requestMarkerColor(_ status: ShiftRequestStatus) -> Color {
        switch status {
        case .approved: return .green
        case .pending: return .orange
        case .rejected: return .gray
        }
    }

    private func requestCount(_ status: ShiftRequestStatus) -> Int {
        let prefix = DateFormatter.monthKey.string(from: month)
        return store.selectedRequestsUnsorted.filter { $0.status == status && $0.dateKey.hasPrefix(prefix) }.count
    }

    private func requestLegend(color: Color, title: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
            Text("\(count)").fontWeight(.semibold).monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func isDashboardSelected(_ date: Date) -> Bool {
        guard let selected = Date.keyFormatter.date(from: dashboardSelectedDateKey) else { return false }
        return calendar.isDate(date, inSameDayAs: selected)
    }

    private func weekday(_ date: Date) -> String {
        let index = Calendar.current.component(.weekday, from: date) - 1
        return ["日", "月", "火", "水", "木", "金", "土"][index]
    }
    private func weekdayColor(_ date: Date) -> Color { let w = calendar.component(.weekday, from: date); return w == 1 ? .red : (w == 7 ? .blue : .secondary) }
}


private enum ShiftCalendarMode: Hashable { case month, week, day }

private enum ShiftSaveNotice: String, Identifiable {
    case confirmation, success, failure
    var id: String { rawValue }
}

struct DayShiftTimeEditor: View {
    @EnvironmentObject private var store: ShiftStore
    let staff: StaffMember
    let date: Date
    let assignment: ShiftAssignment?
    let hasApprovedLeave: Bool
    @Binding var minuteStep: Int
    var editingEnabled = true
    var openStaffDetail: (() -> Void)? = nil
    let save: (Int, Int, Int, Int) -> Void
    @State private var start: Double = 540
    @State private var end: Double = 1080
    @State private var breakMinutes: Double = 60
    @State private var breakStart: Double = 720
    @State private var confirmationLocationID: UUID?
    @State private var timeSaveFailureMessage: String?
    @State private var saveNotice: ShiftSaveNotice?
    @State private var pendingTimeSave: (start: Int, end: Int, breakMinutes: Int, breakStart: Int)?
    private var safeBreak: Int { min(Int(breakMinutes), max(0, Int(end - start))) }
    private var safeBreakStart: Int { min(max(Int(start), Int(breakStart)), Int(end) - safeBreak) }
    private var estimate: (paid: Double, overtime: Double, night: Double) {
        var draft = assignment ?? ShiftAssignment(staffID: staff.id, dateKey: date.shiftDateKey, type: .day)
        draft.customStartMinutes = Int(start)
        draft.customEndMinutes = Int(end)
        draft.customBreakMinutes = safeBreak
        draft.customBreakStartMinutes = safeBreakStart
        return ShiftLaborEstimate.breakdown(draft)
    }
    private var estimatedCost: Int {
        Int(ceil(Double(assignment?.hourlyWageSnapshot ?? staff.hourlyWage) * (estimate.paid + 0.25 * estimate.overtime + 0.25 * estimate.night)))
    }
    private func hours(_ value: Double) -> String { String(format: "%.2f", value) }
    private func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let openStaffDetail { Button(staff.name, action: openStaffDetail).font(.subheadline.bold()).buttonStyle(.plain) }
                else { Text(staff.name).font(.subheadline.bold()) }
                Spacer(); Text(assignment?.type.rawValue ?? "未設定").font(.caption).foregroundStyle(.secondary)
            }
            if hasApprovedLeave {
                Label("この日は承認済みの希望休があります", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                if let assignment, assignment.type != .off && assignment.type != .paidLeave && assignment.type != .afterNight {
                    Label("勤務シフトと希望休が重複しています。保存前に勤務区分と希望休を確認してください。", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("承認済み希望休と勤務シフトが重複")
                }
            }
            Group {
            HStack { Text("開始"); Spacer(); Text(clock(Int(start))).monospacedDigit().foregroundStyle(.blue) }
            Slider(value: $start, in: 0...1430, step: Double(minuteStep)).tint(.blue).onChange(of: start) { _, value in if end < value + Double(minuteStep) { end = min(2879, value + Double(minuteStep)) } }
            HStack { Text("終了"); Spacer(); Text(clock(Int(end))).monospacedDigit().foregroundStyle(.blue) }
            Slider(value: $end, in: min(Double(minuteStep), start + Double(minuteStep))...2879, step: Double(minuteStep)).tint(.teal)
            HStack { Text("休憩"); Spacer(); Text("\(Int(breakMinutes))分").monospacedDigit() }
            Slider(value: $breakMinutes, in: 0...max(0, min(180, end - start)), step: 15).tint(.orange)
            HStack { Text("休憩開始"); Spacer(); Text(clock(Int(breakStart))).monospacedDigit() }
            Slider(value: $breakStart, in: start...max(start, end - Double(safeBreak)), step: Double(minuteStep)).tint(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("保存前の概算").font(.caption.bold())
                Text("実働 \(hours(estimate.paid))時間  ／  1日8時間超 \(hours(estimate.overtime))時間  ／  深夜 \(hours(estimate.night))時間")
                    .font(.caption).monospacedDigit()
                Text("予定人件費 ¥\(estimatedCost.formatted())（基本時給＋概算割増）")
                    .font(.subheadline.bold()).foregroundStyle(.blue)
                Text("法定休日・週40時間超・月60時間超・変形労働時間制などは未計算。給与確定には使用できません。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            HStack { Spacer(); Button("時間を保存") {
                let values = (start: Int(start), end: Int(end), breakMinutes: safeBreak, breakStart: safeBreakStart)
                // A new time entry creates a working day shift; existing non-working
                // assignments keep their shift type when only times are updated.
                let createsWorkingShift = assignment == nil || (assignment?.type != .off && assignment?.type != .paidLeave && assignment?.type != .afterNight)
                if hasApprovedLeave && createsWorkingShift {
                    pendingTimeSave = values
                    confirmationLocationID = store.selectedLocationID
                    saveNotice = .confirmation
                } else {
                    commitTimeSave(values)
                }
            }.modifier(AppActionStyle(prominent: true)) }
            }.disabled(!editingEnabled)
        }.padding(12).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .alert(item: $saveNotice) { notice in
                switch notice {
                case .confirmation:
                    return Alert(
                        title: Text("承認済みの希望休があります"),
                        message: Text("この日は承認済みの希望休があります。勤務時間を保存すると勤務シフトとの競合が発生または継続します。内容を確認してください。"),
                        primaryButton: .destructive(Text("重複を承知で時間を保存")) {
                            defer { pendingTimeSave = nil; confirmationLocationID = nil }
                            guard let values = pendingTimeSave else {
                                presentTimeSaveFailure("確認中の勤務時間が失われました。もう一度保存してください。")
                                return
                            }
                            guard confirmationLocationID == store.selectedLocationID else {
                                presentTimeSaveFailure("確認中に店舗が変更されました。現在の店舗で再操作してください。")
                                return
                            }
                            guard store.data.staff.contains(where: { $0.id == staff.id && $0.locationID == store.selectedLocationID }) else {
                                presentTimeSaveFailure("スタッフの所属が変更されました。スタッフ情報を確認してください。")
                                return
                            }
                            commitTimeSave(values)
                        },
                        secondaryButton: .cancel(Text("キャンセル")) {
                            pendingTimeSave = nil
                            confirmationLocationID = nil
                        }
                    )
                case .success:
                    return Alert(title: Text("操作が完了しました"),
                                 message: Text("\(staff.name)さんの\(date.formatted(date: .long, time: .omitted))の勤務時間を保存しました。"),
                                 dismissButton: .default(Text("閉じる")))
                case .failure:
                    return Alert(title: Text("勤務時間の保存を中止しました"),
                                 message: Text(timeSaveFailureMessage ?? "勤務時間を確認してから再操作してください。"),
                                 dismissButton: .default(Text("閉じる")) { timeSaveFailureMessage = nil })
                }
            }
            // FIXED185: Reinitialize the draft when its date, staff or hotel changes.
            // Two unassigned days both have assignment?.id == nil, so observing
            // only that ID previously leaked unsaved slider values across days.
            .onChange(of: date) { _, _ in resetTimeDraft() }
            .onChange(of: store.selectedLocationID) { _, _ in resetTimeDraft() }
            .onChange(of: staff.id) { _, _ in resetTimeDraft() }
            .onAppear { resetTimeDraft() }
            .onChange(of: assignment?.id) { _, _ in resetTimeDraft() }
    }
    private func resetTimeDraft() {
        pendingTimeSave = nil
        confirmationLocationID = nil
        saveNotice = nil
        timeSaveFailureMessage = nil
        start = Double(assignment?.customStartMinutes ?? defaultStart)
        end = Double(assignment?.customEndMinutes ?? defaultEnd)
        breakMinutes = Double(assignment?.customBreakMinutes ?? 60)
        breakStart = Double(assignment?.customBreakStartMinutes ?? (Int(start) + 240))
    }
    private func commitTimeSave(_ values: (start: Int, end: Int, breakMinutes: Int, breakStart: Int)) {
        guard store.selectedStaff.contains(where: { $0.id == staff.id }) else {
            presentTimeSaveFailure("対象スタッフが現在の店舗に所属していません。スタッフ情報を確認してください。")
            return
        }
        // FIXED186: Do not overwrite a shift that was created, deleted, or
        // replaced while this editor (or its confirmation alert) was open.
        let latest = store.assignment(staffID: staff.id, date: date)
        guard latest?.id == assignment?.id else {
            presentTimeSaveFailure("編集中にシフト情報が変更されました。画面を開き直して最新の内容を確認してください。")
            return
        }
        save(values.start, values.end, values.breakMinutes, values.breakStart)
        saveNotice = .success
    }
    private func presentTimeSaveFailure(_ message: String) {
        timeSaveFailureMessage = message
        saveNotice = .failure
    }
    private var defaultStart: Int { switch assignment?.type { case .early: return 360; case .day: return 540; case .late: return 780; case .night: return 1260; default: return 540 } }
    private var defaultEnd: Int { switch assignment?.type { case .early: return 900; case .day: return 1080; case .late: return 1320; case .night: return 1980; default: return 1080 } }
}

private struct PDFPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let document: PDFDocument
}

private struct PDFOutputPreview: View {
    let url: URL
    let document: PDFDocument
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    @State private var showPrintError = false

    var body: some View {
        NavigationStack {
            Group {
                if document.pageCount > 0 {
                    PDFDocumentView(document: document)
                        .background(Color(uiColor: .secondarySystemBackground))
                } else {
                    ContentUnavailableView("PDFを読み込めません", systemImage: "doc.richtext", description: Text("PDFファイルの作成に失敗した可能性があります。もう一度作成してください。"))
                }
            }
            .navigationTitle("シフト表 PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showShare = true } label: { Label("出力", systemImage: "square.and.arrow.up") }
                    Button { printPDF() } label: { Label("印刷", systemImage: "printer") }
                }
            }
            .sheet(isPresented: $showShare) {
                PDFActivitySheet(items: [url])
            }
            .alert("印刷を開始できません", isPresented: $showPrintError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("この端末では印刷を開始できませんでした。PDFの出力ボタンからファイルを保存してお試しください。")
            }
        }
    }

    private func printPDF() {
        guard UIPrintInteractionController.isPrintingAvailable else {
            showPrintError = true
            return
        }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = url.lastPathComponent
        info.outputType = .general
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true) { _, completed, error in
            if !completed && error != nil { showPrintError = true }
        }
    }
}

private struct PDFDocumentView: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .horizontal
        view.backgroundColor = .secondarySystemBackground
        view.document = document
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document { uiView.document = document }
        uiView.autoScales = true
    }
}

private struct PDFActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct ShiftCellSelection {
    let staff: StaffMember
    let date: Date
}

private struct ShiftEditSelection: Identifiable {
    let id = UUID()
    let staff: StaffMember
    let date: Date
}

struct ShiftEditSheet: View {
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.dismiss) private var dismiss
    let staff: StaffMember
    let date: Date
    @State private var selectedType: ShiftType = .day
    @State private var note = ""
    @State private var shiftSaveFailureMessage: String?
    @State private var saveNotice: ShiftSaveNotice?
    @State private var openedLocationID: UUID? = nil
    @State private var openedAssignmentID: UUID? = nil
    @State private var draftInitialized = false
    @State private var confirmedShiftType: ShiftType? = nil
    @State private var confirmedNote: String? = nil
    @State private var confirmedLocationID: UUID? = nil

    // Only approved leave requests conflict with a working shift. Pending requests
    // remain visible in the calendar but do not block routine scheduling.
    private var approvedRequest: ShiftRequest? {
        store.selectedRequestsUnsorted.first {
            $0.staffID == staff.id && $0.dateKey == date.shiftDateKey && $0.status == .approved
        }
    }

    private var isWorkingShift: Bool {
        selectedType != .off && selectedType != .paidLeave && selectedType != .afterNight
    }

    private func saveShift() {
        guard validateEditContext() else { return }
        if let current = store.selectedStaff.first(where: { $0.id == staff.id }),
           !current.isActive && store.assignment(staffID: staff.id, date: date) == nil {
            presentShiftSaveFailure("休止中のスタッフには新しいシフトを登録できません。スタッフ管理で勤務可能に戻してください。")
            return
        }
        if isWorkingShift, approvedRequest != nil {
            confirmedShiftType = selectedType
            confirmedNote = note
            confirmedLocationID = store.selectedLocationID
            saveNotice = .confirmation
        } else {
            commitShiftSave(type: selectedType, note: note)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("勤務対象") {
                    LabeledContent("スタッフ", value: staff.name)
                    LabeledContent("日付", value: date.formatted(date: .long, time: .omitted))
                }
                if let current = store.selectedStaff.first(where: { $0.id == staff.id }), !current.isActive {
                    Section {
                        Label(store.assignment(staffID: staff.id, date: date) == nil
                              ? "休止中のスタッフには新しいシフトを登録できません。"
                              : "休止中のスタッフの過去のシフトを編集中です。", systemImage: "info.circle")
                            .foregroundStyle(.orange)
                    }
                }
                Section("勤務区分") {
                    ForEach(ShiftType.allCases) { type in
                        Button { selectedType = type } label: {
                            HStack { ShiftPill(type: type); Text(store.selectedBasicPatterns.first(where: { $0.basicShiftType == type }).map { ScheduleGridSupport.patternTimeLines($0, type: type).joined(separator: " 〜 ") } ?? (type.start + (type.end == "—" ? "" : " 〜 " + type.end))).foregroundStyle(.secondary); Spacer(); if selectedType == type { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) } }
                        }.buttonStyle(.plain)
                    }
                }
                Section("メモ") { TextField("引き継ぎ事項・注意点など", text: $note, axis: .vertical).lineLimit(2...4) }
                if store.assignment(staffID: staff.id, date: date) != nil {
                    Section { Button("この日のシフトを削除", role: .destructive) {
                        guard validateEditContext() else { return }
                        store.clearShift(staffID: staff.id, date: date)
                        dismiss()
                    } }
                }
            }
            .navigationTitle("勤務を編集").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { saveShift() }.fontWeight(.semibold) }
            }
            .onAppear {
                guard !draftInitialized else { return }
                openedLocationID = store.selectedLocationID
                let original = store.assignment(staffID: staff.id, date: date)
                openedAssignmentID = original?.id
                selectedType = original?.type ?? .day
                note = original?.note ?? ""
                draftInitialized = true
            }
            .alert(item: $saveNotice) { notice in
                switch notice {
                case .confirmation:
                    return Alert(
                        title: Text("承認済みの希望休があります"),
                        message: Text(approvedRequest.map { "\(staff.name)さんは\(date.formatted(date: .long, time: .omitted))に「\($0.reason)」を申請し、承認されています。勤務区分「\(selectedType.rawValue)」を登録してよいか確認してください。" } ?? "承認済みの希望休と勤務予定が重複しています。"),
                        primaryButton: .destructive(Text("確認してシフトを保存")) {
                            defer { clearShiftConfirmation(keepNotice: true) }
                            guard let type = confirmedShiftType, let savedNote = confirmedNote else {
                                presentShiftSaveFailure("確認中のシフト内容が失われました。もう一度保存してください。")
                                return
                            }
                            guard confirmedLocationID == store.selectedLocationID else {
                                presentShiftSaveFailure("確認中に店舗が変更されました。現在の店舗で再操作してください。")
                                return
                            }
                            guard selectedType == type, note == savedNote else {
                                presentShiftSaveFailure("確認中に勤務区分またはメモが変更されました。内容を確認して再操作してください。")
                                return
                            }
                            guard store.selectedStaff.contains(where: { $0.id == staff.id }) else {
                                presentShiftSaveFailure("対象スタッフが現在の店舗に所属していません。スタッフ情報を確認してください。")
                                return
                            }
                            commitShiftSave(type: type, note: savedNote)
                        },
                        secondaryButton: .cancel(Text("戻って確認")) { clearShiftConfirmation() }
                    )
                case .success:
                    return Alert(title: Text("操作が完了しました"),
                                 message: Text("\(staff.name)さんの\(date.formatted(date: .long, time: .omitted))の勤務区分「\(selectedType.rawValue)」を保存しました。"),
                                 dismissButton: .default(Text("閉じる")) { dismiss() })
                case .failure:
                    return Alert(title: Text("シフトの保存を中止しました"),
                                 message: Text(shiftSaveFailureMessage ?? "シフト内容を確認して再操作してください。"),
                                 dismissButton: .default(Text("閉じる")) { shiftSaveFailureMessage = nil })
                }
            }
            .onChange(of: store.selectedLocationID) { _, _ in clearShiftConfirmation() }
            .onChange(of: selectedType) { _, _ in clearShiftConfirmation() }
            .onChange(of: note) { _, _ in clearShiftConfirmation() }
        }
        .presentationDetents([.medium, .large])
    }

    private func commitShiftSave(type: ShiftType, note: String) {
        guard validateEditContext() else { return }
        guard store.selectedStaff.contains(where: { $0.id == staff.id }) else {
            presentShiftSaveFailure("対象スタッフが現在の店舗に所属していません。スタッフ情報を確認してください。")
            return
        }
        guard let current = store.selectedStaff.first(where: { $0.id == staff.id }),
              current.isActive || store.assignment(staffID: staff.id, date: date) != nil else {
            presentShiftSaveFailure("休止中のスタッフには新しいシフトを登録できません。勤務可能に戻してから再操作してください。")
            return
        }
        store.setShift(staffID: staff.id, date: date, type: type, note: note)
        saveNotice = .success
    }
    // FIXED253: A sheet may remain alive while the hotel changes or another
    // screen replaces/deletes its assignment. Never apply a stale draft.
    private func validateEditContext() -> Bool {
        guard draftInitialized, openedLocationID == store.selectedLocationID else {
            presentShiftSaveFailure("編集中に店舗が変更されました。画面を閉じて開き直してください。")
            return false
        }
        guard let current = store.selectedStaff.first(where: { $0.id == staff.id }),
              current.locationID == openedLocationID else {
            presentShiftSaveFailure("対象スタッフの所属が変更されました。画面を開き直してください。")
            return false
        }
        guard store.assignment(staffID: staff.id, date: date)?.id == openedAssignmentID else {
            presentShiftSaveFailure("編集中にシフトが追加・削除・置換されました。最新の内容を確認してください。")
            return false
        }
        return true
    }

    private func presentShiftSaveFailure(_ message: String) {
        shiftSaveFailureMessage = message
        saveNotice = .failure
    }

    private func clearShiftConfirmation(keepNotice: Bool = false) {
        if !keepNotice { saveNotice = nil }
        confirmedShiftType = nil
        confirmedNote = nil
        confirmedLocationID = nil
    }
}

struct ShiftPill: View {
    let type: ShiftType
    var body: some View { Text(type.rawValue).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 5).background(shiftBackground(type), in: Capsule()).foregroundStyle(shiftForeground(type)) }
}

func shiftBackground(_ type: ShiftType) -> Color {
    switch type { case .early: return Color.blue.opacity(0.14); case .day: return Color.cyan.opacity(0.15); case .late: return Color.purple.opacity(0.14); case .night: return Color.orange.opacity(0.18); case .afterNight: return Color.gray.opacity(0.18); case .off: return Color.gray.opacity(0.1); case .paidLeave: return Color.green.opacity(0.16) }
}
func shiftForeground(_ type: ShiftType) -> Color {
    switch type { case .early: return .blue; case .day: return .teal; case .late: return .purple; case .night: return .orange; case .afterNight: return .secondary; case .off: return .secondary; case .paidLeave: return .green }
}

private extension DateFormatter {
    static let monthKey: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}


private struct RequestDetailSheet: View {
    let request: ShiftRequest
    let staffName: String
    let editConflictingShift: () -> Void
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.dismiss) private var dismiss
    private enum RequestAlert: Identifiable {
        case approvalConflict, success(String), failure(String)
        var id: String {
            switch self {
            case .approvalConflict: return "approvalConflict"
            case .success: return "success"
            case .failure: return "failure"
            }
        }
    }
    @State private var activeRequestAlert: RequestAlert? = nil
    @State private var approvalConfirmationLocationID: UUID? = nil
    @State private var approvalConfirmationRequest: ShiftRequest? = nil
    @State private var approvalConfirmationShift: ShiftAssignment? = nil

    private var currentRequest: ShiftRequest? {
        (store.data.requests ?? []).first {
            $0.id == request.id && $0.locationID == store.selectedLocationID
        }
    }
    private var currentStatus: ShiftRequestStatus { currentRequest?.status ?? request.status }
    private var requestIsCurrent: Bool { currentRequest == request }
    private var conflictingShift: ShiftAssignment? {
        store.data.assignments.first {
            $0.locationID == store.selectedLocationID && $0.staffID == request.staffID &&
            $0.dateKey == request.dateKey && $0.type != .off &&
            $0.type != .paidLeave && $0.type != .afterNight
        }
    }
    private func approveRequest() {
        guard let current = currentRequest else {
            presentApprovalFailure("申請が削除されたか、現在の店舗では確認できません。希望休一覧から開き直してください。")
            return
        }
        guard current == request else {
            presentApprovalFailure("画面を開いたあとに申請状態または内容が変更されました。最新の申請を一覧から開き直してください。")
            return
        }
        if conflictingShift != nil {
            approvalConfirmationLocationID = store.selectedLocationID
            approvalConfirmationRequest = current
            approvalConfirmationShift = conflictingShift
            activeRequestAlert = .approvalConflict
        } else {
            commitRequestStatus(.approved)
        }
    }

    // One outcome path for approval, rejection and resetting to pending.
    // Keep the detail sheet visible until the administrator acknowledges success.
    private func commitRequestStatus(_ status: ShiftRequestStatus) {
        guard let current = currentRequest else {
            presentApprovalFailure("申請が削除または変更されました。希望休一覧から開き直してください。")
            return
        }
        guard current == request else {
            presentApprovalFailure("画面を開いたあとに申請状態または内容が変更されました。最新の申請を一覧から開き直してください。")
            return
        }
        guard store.selectedStaff.contains(where: { $0.id == current.staffID }) else {
            presentApprovalFailure("対象スタッフが現在の店舗に所属していません。スタッフ情報を確認してください。")
            return
        }
        store.setRequestStatus(current, status: status)
        guard currentRequest?.status == status else {
            presentApprovalFailure("変更を保存できませんでした。申請の最新状態を確認してください。")
            return
        }
        activeRequestAlert = .success("希望休の状態を「\(status.rawValue)」に変更しました。")
    }

    private func presentApprovalFailure(_ message: String) {
        activeRequestAlert = .failure(message)
    }

    private func clearApprovalConfirmation() {
        approvalConfirmationLocationID = nil
        approvalConfirmationRequest = nil
        approvalConfirmationShift = nil
    }

    private var requestDate: Date? { Date.keyFormatter.date(from: request.dateKey) }
    private var formattedCreatedAt: String {
        request.createdAt.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: "ja_JP")))
    }
    private var statusColor: Color {
        switch currentStatus {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .gray
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("申請内容") {
                    LabeledContent("スタッフ", value: staffName)
                    LabeledContent("希望日", value: requestDate?.formatted(date: .long, time: .omitted) ?? request.dateKey)
                    LabeledContent("申請種別・理由", value: request.reason.isEmpty ? "記載なし" : request.reason)
                    HStack {
                        Text("ステータス")
                        Spacer()
                        Text(currentStatus.rawValue)
                            .fontWeight(.semibold)
                            .foregroundStyle(statusColor)
                    }
                    LabeledContent("申請日時", value: formattedCreatedAt)
                    LabeledContent("申請番号", value: String(request.id.uuidString.prefix(8)))
                }
                if let shift = conflictingShift {
                    Section {
                        Label("同じ日に勤務シフト（\(shift.type.rawValue)）が登録されています", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        LabeledContent("勤務内容", value: shift.type.rawValue)
                        if let start = shift.customStartMinutes, let end = shift.customEndMinutes {
                            LabeledContent("登録時間", value: String(format: "%02d:%02d〜%02d:%02d", start / 60, start % 60, end / 60, end % 60))
                        }
                        Text("希望休の承認・却下やシフトの変更は自動連動しません。内容を確認してから操作してください。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button {
                            editConflictingShift()
                        } label: {
                            Label("この日のシフトを編集", systemImage: "pencil.circle")
                        }
                    }
                }
                if !requestIsCurrent {
                    Section {
                        Label("申請内容が更新されたか、現在の店舗で確認できません。誤操作防止のため変更ボタンを無効にしました。", systemImage: "arrow.clockwise.circle")
                            .foregroundStyle(.orange)
                        Button { dismiss() } label: {
                            Label("一覧に戻って最新の申請を開く", systemImage: "arrow.uturn.backward.circle")
                        }
                    }
                }
                Section("管理者操作") {
                    if currentStatus == .pending {
                        Button {
                            approveRequest()
                        } label: {
                            Label("この申請を承認", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        Button(role: .destructive) {
                            commitRequestStatus(.rejected)
                        } label: {
                            Label("この申請を却下", systemImage: "xmark.circle.fill")
                        }
                    } else {
                        Button {
                            commitRequestStatus(.pending)
                        } label: {
                            Label("申請中に戻す", systemImage: "arrow.uturn.backward.circle")
                        }
                        Button {
                            if currentStatus == .approved {
                                commitRequestStatus(.rejected)
                            } else {
                                approveRequest()
                            }
                        } label: {
                            Label(currentStatus == .approved ? "却下に変更" : "承認に変更", systemImage: "arrow.left.arrow.right.circle")
                        }
                    }
                    Text("変更内容はこの端末に保存されます。別端末へ反映するには、申請データを書き出して受け渡してください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .disabled(!requestIsCurrent)
            }
            .navigationTitle("希望休の詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert(item: $activeRequestAlert) { alert in
            switch alert {
            case .approvalConflict:
                return Alert(
                    title: Text("勤務シフトとの重複"),
                    message: Text("この日に勤務シフトが登録されています。承認してもシフトは削除されず、競合一覧に表示されます。"),
                    primaryButton: .cancel(Text("キャンセル"), action: { clearApprovalConfirmation() }),
                    secondaryButton: .default(Text("重複を承知で承認"), action: {
                defer { clearApprovalConfirmation() }
                guard approvalConfirmationLocationID == store.selectedLocationID else {
                    presentApprovalFailure("確認中に店舗が変更されました。現在の店舗で申請を開き直してください。")
                    return
                }
                guard let current = currentRequest, let originalRequest = approvalConfirmationRequest else {
                    presentApprovalFailure("申請が削除または変更されました。希望休一覧から開き直してください。")
                    return
                }
                guard current == originalRequest, current.status != .approved else {
                    presentApprovalFailure("確認中に申請内容または承認状態が変更されました。最新の状態を確認してから再操作してください。")
                    return
                }
                guard let originalShift = approvalConfirmationShift,
                      conflictingShift == originalShift else {
                    presentApprovalFailure("確認中に勤務シフトが変更されました。最新の勤務内容を確認してから再操作してください。")
                    return
                }
                guard store.selectedStaff.contains(where: { $0.id == current.staffID }) else {
                    presentApprovalFailure("対象スタッフが現在の店舗に所属していません。スタッフ情報を確認してください。")
                    return
                }
                commitRequestStatus(.approved)
                    })
                )
            case .success(let message):
                return Alert(title: Text("操作が完了しました"), message: Text(message),
                             dismissButton: .default(Text("閉じる"), action: { dismiss() }))
            case .failure(let message):
                return Alert(title: Text("操作を中止しました"), message: Text(message),
                             dismissButton: .default(Text("閉じる")))
            }
        }
        .onChange(of: store.selectedLocationID) { _, _ in
            activeRequestAlert = nil
            clearApprovalConfirmation()
        }
    }
}

struct ShiftPatternManager: View {
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.dismiss) private var dismiss
    let month: Date
    let openConflict: (UUID, String) -> Void
    var managementOnly = false
    @State private var editing: ShiftPattern?
    @State private var applying: ShiftPattern?
    @State private var pendingPatternEditID: UUID?
    @State private var resumeApplyPatternID: UUID?
    @State private var resumeApplyRange: ClosedRange<Date>?
    @State private var confirmation = ""
    @State private var confirmationIsError = false
    var body: some View {
        NavigationStack {
            List {
                let conflicts = managementOnly ? [] : store.approvedLeaveShiftConflictDetails()
                if !conflicts.isEmpty {
                    Section {
                        Label("承認済み希望休と勤務シフトが重複：\(conflicts.count)件", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("既存シフトは自動変更しません。行をタップすると該当日の編集画面を開きます。")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(conflicts) { conflict in
                            Button {
                                openConflict(conflict.staffID, conflict.dateKey)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(conflict.staffName).font(.subheadline.weight(.semibold))
                                        Text("\(conflict.dateKey) ・ \(conflict.shiftType.rawValue)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if managementOnly {
                    Section("標準の勤務時間") {
                        ForEach(store.selectedBasicPatterns) { pattern in
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(pattern.name).font(.headline)
                                    Text("勤務区分：" + (pattern.basicShiftType?.rawValue ?? "")).font(.caption).foregroundStyle(.secondary)
                                    Text(ScheduleGridSupport.patternTimeLines(pattern, type: pattern.basicShiftType ?? .day).joined(separator: " 〜 "))
                                        .font(.subheadline).monospacedDigit()
                                    Text("休憩：\(pattern.customBreakMinutes ?? 60)分").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { editing = pattern } label: { Label("編集", systemImage: "pencil") }
                                    .modifier(AppActionStyle())
                            }.padding(.vertical, 6)
                        }
                        Text("変更後に勤務区分を新しく割り当てる際に使います。登録済みシフトの時刻は変更しません。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(managementOnly ? "追加の曜日別パターン" : "登録済みパターン") {
                    ForEach(store.selectedPatterns) { pattern in
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pattern.name)
                                    .font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(pattern.scope.rawValue + " ・ " + (store.selectedStaff.first(where: { $0.id == pattern.staffID })?.name ?? "全員"))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                SchedulePatternTimes(pattern: pattern)
                            }
                            HStack(spacing: 12) {
                                if !managementOnly {
                                Button { applying = pattern } label: {
                                    Label("適用", systemImage: "checkmark.circle")
                                        .frame(minWidth: 88, minHeight: 36)
                                }
                                .modifier(AppActionStyle(prominent: true))
                                }
                                Button { editing = pattern } label: {
                                    Label("編集", systemImage: "pencil")
                                        .frame(minWidth: 88, minHeight: 36)
                                }
                                .modifier(AppActionStyle())
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(.vertical, 5)
                    }.onDelete { indices in
                        let list = store.selectedPatterns
                        for i in indices { _ = store.deletePatternSafely(list[i]) }
                    }
                }
                Section { Text("スタッフ別に11:00〜19:00などの勤務時間・休憩を登録できます。適用時は既存のシフト・承認済み休暇を上書きしません。期間限定は開始日と終了日の範囲だけ適用します。") .font(.caption).foregroundStyle(.secondary) }
                if !confirmation.isEmpty {
                    Label(confirmation, systemImage: confirmationIsError ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(confirmationIsError ? .red : .green)
                }
            }
            .navigationTitle(managementOnly ? "基本パターン" : "シフトパターン")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { editing = ShiftPattern(name: "新しいパターン", scope: .everyone, locationID: store.selectedLocationID) } label: { Label("新規作成", systemImage: "plus") } }
            }
            .sheet(item: $editing, onDismiss: {
                // After editing a conflicting pattern, reopen a fresh preview.
                // The application range is preserved, but no shifts are written.
                if let id = resumeApplyPatternID {
                    resumeApplyPatternID = nil
                    if let saved = store.selectedPatterns.first(where: { $0.id == id }) {
                        applying = saved
                    } else {
                        resumeApplyRange = nil
                    }
                }
            }) { pattern in ShiftPatternEditor(pattern: pattern).environmentObject(store) }
            .sheet(item: $applying, onDismiss: {
                if let id = pendingPatternEditID {
                    pendingPatternEditID = nil
                    // Resolve the saved pattern again; it may have changed or been deleted.
                    editing = store.selectedPatterns.first(where: { $0.id == id })
                    if editing == nil { resumeApplyPatternID = nil; resumeApplyRange = nil }
                }
            }) { pattern in
                ShiftPatternApply(pattern: pattern, month: month, initialRange: resumeApplyRange, editConflictingPattern: { id, range in
                    resumeApplyPatternID = pattern.id
                    resumeApplyRange = range
                    pendingPatternEditID = id
                    applying = nil
                }) { from, until in
                    let result = store.applyPatternWithReport(pattern, from: from, through: until)
                    confirmationIsError = false
                    let skipped = "既存シフト\(result.existingShifts)件・承認済み希望休\(result.approvedLeave)件・期間限定予約日\(result.reservedSeasonal)件・期間限定重複\(result.overlappingSeasonal)件"
                    if result.added > 0 {
                        confirmation = "\(result.added)件を適用しました（\(skipped)）"
                    } else if result.existingShifts > 0 || result.approvedLeave > 0 || result.reservedSeasonal > 0 || result.overlappingSeasonal > 0 {
                        confirmation = "新しいシフトはありません。\(skipped)を保護・除外しました。"
                    } else {
                        confirmationIsError = true
                        confirmation = "適用件数は0件です。期間・対象スタッフ・パターンの有効期限を確認してください。"
                    }
                    return result
                }
            }
            .onChange(of: store.selectedLocationID) { _, _ in
                applying = nil
                editing = nil
                pendingPatternEditID = nil
                resumeApplyPatternID = nil
                resumeApplyRange = nil
                confirmation = ""
                confirmationIsError = false
            }
        }
    }
}
struct ShiftPatternEditor: View {
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.dismiss) private var dismiss
    @State var pattern: ShiftPattern
    var lockedStaffID: UUID? = nil
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showDiscardConfirmation = false
    @State private var initialPattern: ShiftPattern? = nil
    @State private var wasExistingAtOpen = false
    private var hasUnsavedChanges: Bool {
        guard let initialPattern else { return false }
        return pattern != initialPattern
    }
    private func requestDismissal() {
        if hasUnsavedChanges { showDiscardConfirmation = true }
        else { dismiss() }
    }
    private var validationMessage: String? {
        if pattern.locationID != store.selectedLocationID { return "ホテルが切り替わりました。編集画面を閉じて開き直してください。" }
        if pattern.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "パターン名を入力してください。" }
        if pattern.scope != .everyone && pattern.staffID == nil { return "対象スタッフを選択してください。" }
        if pattern.scope == .seasonal {
            guard let from = pattern.validFrom, let until = pattern.validUntil else { return "開始日と終了日を設定してください。" }
            if Calendar.current.startOfDay(for: from) > Calendar.current.startOfDay(for: until) { return "終了日は開始日以降にしてください。" }
        }
        if let start = pattern.customStartMinutes, let end = pattern.customEndMinutes {
            let duration = end - start
            let rest = pattern.customBreakMinutes ?? 0
            if duration < 15 || rest < 0 || rest > duration { return "勤務時間と休憩時間を確認してください。" }
            if let restStart = pattern.customBreakStartMinutes, (restStart < start || restStart + rest > end) { return "休憩開始は勤務時間内に設定してください。" }
        }
        return nil
    }
    private let days = ["月", "火", "水", "木", "金", "土", "日"]
    private func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
            + (minutes >= 1440 ? "（翌日）" : "")
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("パターン名", text: $pattern.name)
                if lockedStaffID == nil && pattern.basicShiftType == nil {
                    Picker("対象", selection: $pattern.scope) { ForEach(ShiftPatternScope.allCases) { Text($0.rawValue).tag($0) } }
                } else {
                    LabeledContent("対象", value: pattern.basicShiftType?.rawValue ?? "このスタッフ専用")
                }
                if pattern.scope != .everyone && lockedStaffID == nil {
                    Picker("スタッフ", selection: $pattern.staffID) {
                        Text("選択してください").tag(UUID?.none)
                        ForEach(store.selectedStaff.filter(\.isActive)) { staff in Text(staff.name).tag(Optional(staff.id)) }
                    }
                }
                if pattern.scope == .seasonal {
                    DatePicker("開始日", selection: Binding(get: { pattern.validFrom ?? Date() }, set: { pattern.validFrom = $0 }), displayedComponents: .date)
                    DatePicker("終了日", selection: Binding(get: { pattern.validUntil ?? Date() }, set: { pattern.validUntil = $0 }), displayedComponents: .date)
                }
                if let message = validationMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section("オリジナル勤務時間") {
                    Toggle("勤務時間を個別指定", isOn: Binding(
                        get: { pattern.customStartMinutes != nil },
                        set: { enabled in
                            if enabled {
                                pattern.customStartMinutes = 660
                                pattern.customEndMinutes = 1140
                                pattern.customBreakMinutes = 60
                                pattern.customBreakStartMinutes = 900
                            } else {
                                pattern.customStartMinutes = nil
                                pattern.customEndMinutes = nil
                                pattern.customBreakMinutes = nil
                                pattern.customBreakStartMinutes = nil
                            }
                        })).disabled(pattern.basicShiftType != nil)
                    if pattern.customStartMinutes != nil {
                        Stepper("開始：\(clock(pattern.customStartMinutes ?? 660))", value: Binding(
                            get: { pattern.customStartMinutes ?? 660 },
                            set: { pattern.customStartMinutes = min($0, (pattern.customEndMinutes ?? 1140) - 15) }), in: 0...1439, step: 15)
                        Stepper("終了：\(clock(pattern.customEndMinutes ?? 1140))", value: Binding(
                            get: { pattern.customEndMinutes ?? 1140 },
                            set: { pattern.customEndMinutes = max($0, (pattern.customStartMinutes ?? 660) + 15) }), in: 15...2879, step: 15)
                        Stepper("休憩：\(pattern.customBreakMinutes ?? 60)分", value: Binding(
                            get: { pattern.customBreakMinutes ?? 60 },
                            set: { pattern.customBreakMinutes = $0 }), in: 0...180, step: 15)
                        Stepper("休憩開始：\(clock(pattern.customBreakStartMinutes ?? 900))", value: Binding(
                            get: { pattern.customBreakStartMinutes ?? 900 },
                            set: { pattern.customBreakStartMinutes = $0 }), in: 0...2879, step: 15)
                        Text("例：11:00〜19:00。終了時刻は翌日まで設定可能です。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if pattern.basicShiftType == nil {
                Section("曜日ごとの勤務") {
                    SchedulePatternTimes(pattern: pattern)
                    ForEach(0..<7, id: \.self) { i in
                        Picker(days[i], selection: $pattern.weekdays[i]) {
                            ForEach(ShiftType.allCases) { type in Text(type.rawValue).tag(type) }
                        }
                    }
                }
                }
            }
            .navigationTitle(pattern.basicShiftType == nil ? "パターン編集" : "標準勤務時間の編集")
            .onAppear {
                if initialPattern == nil {
                    initialPattern = pattern
                    wasExistingAtOpen = (store.data.patterns ?? []).contains(where: { $0.id == pattern.id })
                }
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .confirmationDialog("未保存の変更があります", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button("変更を破棄", role: .destructive) { dismiss() }
                Button("編集を続ける", role: .cancel) { }
            } message: {
                Text("保存していない勤務パターンの変更は失われます。")
            }
            .alert("保存できません", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: { Text(saveErrorMessage.isEmpty ? (validationMessage ?? "入力内容を確認してください。") : saveErrorMessage) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { requestDismissal() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard validationMessage == nil else {
                            saveErrorMessage = validationMessage ?? "入力内容を確認してください。"
                            showSaveError = true
                            return
                        }
                        // An existing record must still equal the snapshot captured on opening.
                        let original = initialPattern ?? pattern
                        let expected: ShiftPattern? = wasExistingAtOpen ? original : nil
                        guard store.savePatternSafely(pattern, expected: expected) else {
                            saveErrorMessage = "パターンが別の操作で変更されたか、ホテルが切り替わりました。画面を開き直してください。"
                            showSaveError = true
                            return
                        }
                        dismiss()
                    }
                    .disabled(validationMessage != nil)
                }
            }
        }
    }
}
struct ShiftPatternApply: View {
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.dismiss) private var dismiss
    let pattern: ShiftPattern
    let month: Date
    let initialRange: ClosedRange<Date>?
    let editConflictingPattern: (UUID, ClosedRange<Date>) -> Void
    let apply: (Date, Date) -> ShiftStore.PatternApplicationResult
    @State private var expectedReport: ShiftStore.PatternApplicationResult?
    @State private var completedReport: ShiftStore.PatternApplicationResult?
    @State private var from: Date = Date()
    @State private var until: Date = Date()
    // FIXED257: Explicitly confirm a snapshot. Any change to shifts, staff,
    // requests or patterns invalidates the confirmation before batch writes.
    @State private var confirmedSnapshot: Data?
    @State private var applyError: String?
    @State private var comparisonCSVURL: URL?
    @State private var detailCSVURL: URL?
    @State private var filteredDetailCSVURL: URL?
    @State private var filteredDetailCSVGeneratedAt: Date?
    @State private var filteredDetailCSVVerification: (rows: Int, cost: Int, matches: Bool)?
    // FIXED304: Independently verify the unfiltered CSV before enabling sharing.
    @State private var fullDetailCSVVerification: (rows: Int, cost: Int, matches: Bool)?
    // FIXED307: Keep explicit results of user-initiated retries.
    @State private var fullCSVRetryMessage: String?
    @State private var filteredCSVRetryMessage: String?
    // FIXED310: Persist only the last 20 retry summaries (no CSV contents or paths).
    // UserDefaults makes the audit trail available after app relaunch.
    private let csvRetryHistoryKey = "hotelShift.csvRetryHistory.v1"
    @State private var csvRetryHistory: [String] = []
    // FIXED313: A prepared export is invalidated whenever the saved history changes.
    @State private var csvRetryHistoryExportURL: URL?

    private func restoreCSVRetryHistory() {
        csvRetryHistory = Array((UserDefaults.standard.stringArray(forKey: csvRetryHistoryKey) ?? []).prefix(20))
        csvRetryHistoryExportURL = nil
    }

    private func recordCSVRetry(scope: String, success: Bool, details: String) {
        let timestamp = Date().formatted(date: .numeric, time: .standard)
        // Read persisted state first to avoid overwriting entries when a fresh
        // view instance retries before its initial onAppear has completed.
        var history = UserDefaults.standard.stringArray(forKey: csvRetryHistoryKey) ?? []
        history.insert("\(timestamp)｜\(scope)｜\(success ? "成功" : "失敗")｜\(details)", at: 0)
        csvRetryHistory = Array(history.prefix(20))
        csvRetryHistoryExportURL = nil
        UserDefaults.standard.set(csvRetryHistory, forKey: csvRetryHistoryKey)
    }

    // FIXED311: Every mutation updates both the view and persistent storage.
    private func saveCSVRetryHistory(_ entries: [String]) {
        csvRetryHistory = Array(entries.prefix(20))
        csvRetryHistoryExportURL = nil
        UserDefaults.standard.set(csvRetryHistory, forKey: csvRetryHistoryKey)
    }

    private func deleteCSVRetryHistoryEntry(at index: Int) {
        guard csvRetryHistory.indices.contains(index) else { return }
        var entries = csvRetryHistory
        entries.remove(at: index)
        saveCSVRetryHistory(entries)
    }

    private func clearCSVRetryHistory() {
        saveCSVRetryHistory([])
    }

    // FIXED312: Search and filter the locally persisted retry summaries.
    // Existing entries remain unchanged for backward compatibility with FIXED310.
    @State private var csvHistorySearch = ""
    @State private var csvHistoryStatus = "すべて"
    @State private var csvHistoryScope = "すべて"
    @State private var confirmingCSVRetryHistoryClear = false
    // FIXED315: Optional inclusive calendar-day boundaries for retry history.
    @State private var csvHistoryDateFilterEnabled = false
    @State private var csvHistoryStartDate = Calendar.current.startOfDay(for: Date())
    @State private var csvHistoryEndDate = Calendar.current.startOfDay(for: Date())

    // FIXED317: Preset identity is cleared when dates are manually edited.
    @State private var csvHistorySelectedPreset: String? = nil
    // FIXED328: Explain when saved search preferences cannot be restored.
    @State private var csvHistoryRestoreNotice: String? = nil

    // FIXED319: Persist only filter preferences, never exported file URLs.
    private let csvHistoryFiltersKey = "hotelShift.csvHistoryFilters.v1"
    // FIXED334: Timestamp belongs to the last successfully persisted snapshot.
    private let csvHistoryLastSavedKey = "hotelShift.csvHistoryFilters.lastSavedAt.v1"
    @State private var csvHistoryLastSavedAt: Date? = nil
    // FIXED330: Never write a partially restored snapshot over valid preferences.
    @State private var csvHistoryRestoreInProgress = false
    // FIXED332: An invalid interim date edit must not overwrite saved preferences.
    @State private var csvHistorySavePending = false
    // FIXED351: A storage write failure is different from an invalid date range.
    @State private var csvHistoryWriteFailure = false
    // FIXED333: Keep the visible persistence state in sync with successful writes.
    @State private var csvHistoryHasSavedSnapshot = false
    // FIXED337: Require confirmation before discarding edits in favor of the stored filters.
    @State private var confirmingCSVHistoryRevert = false
    // FIXED339: Dismissible feedback for user-triggered save, pending, and revert actions.
    @State private var csvHistoryActionFeedback: String? = nil
    @State private var csvHistoryActionFeedbackSymbol = "checkmark.circle.fill"
    // FIXED343: A notification is valid only for the persistence state that created it.
    @State private var csvHistoryFeedbackState: String? = nil
    // FIXED344: Remember which notification was dismissed within the current save state.
    @State private var csvHistoryDismissedFeedbackKey: String? = nil
    @State private var csvHistoryDismissedState: String? = nil

    // FIXED336: Compare the visible controls against the persisted snapshot,
    // not merely the presence of a save timestamp.
    private var csvHistoryCurrentPreferences: CSVHistoryFilterPreferences {
        CSVHistoryFilterPreferences(
            search: csvHistorySearch, status: csvHistoryStatus, scope: csvHistoryScope,
            dateEnabled: csvHistoryDateFilterEnabled, start: csvHistoryStartDate,
            end: csvHistoryEndDate, preset: csvHistorySelectedPreset,
            startDay: CSVHistoryFilterPreferences.dayKey(csvHistoryStartDate),
            endDay: CSVHistoryFilterPreferences.dayKey(csvHistoryEndDate)
        )
    }

    private var csvHistoryMatchesSavedSnapshot: Bool {
        guard csvHistoryHasSavedSnapshot else { return false }
        return CSVHistorySnapshotComparison.matches(
            current: csvHistoryCurrentPreferences,
            stored: UserDefaults.standard.object(forKey: csvHistoryFiltersKey)
        )
    }

    private var csvHistorySaveStatusText: String {
        if csvHistoryRestoreNotice != nil { return "復元エラー：検索条件を初期化しました" }
        if csvHistoryWriteFailure { return "保存エラー：検索条件を端末に書き込めませんでした" }
        if csvHistorySavePending { return "保存保留：日付などの入力内容を確認してください" }
        if csvHistoryHasSavedSnapshot && !csvHistoryMatchesSavedSnapshot { return "未保存の変更あり：画面の条件は保存済みの条件と異なります" }
        return csvHistoryHasSavedSnapshot ? "保存済み：検索条件は端末に保存されています" : "未保存：検索条件はまだ保存されていません"
    }

    private var csvHistoryLastSavedText: String? {
        guard csvHistoryHasSavedSnapshot, let saved = csvHistoryLastSavedAt else { return nil }
        return "最終保存：" + saved.formatted(date: .numeric, time: .shortened)
    }

    private var csvHistorySaveStatusSymbol: String {
        if csvHistoryRestoreNotice != nil { return "exclamationmark.triangle.fill" }
        if csvHistoryWriteFailure { return "exclamationmark.triangle.fill" }
        if csvHistorySavePending { return "clock.badge.exclamationmark" }
        return csvHistoryMatchesSavedSnapshot ? "checkmark.circle.fill" : "info.circle"
    }

    private func resetCSVHistoryFiltersToDefaults() {
        csvHistorySearch = ""
        csvHistoryStatus = "すべて"
        csvHistoryScope = "すべて"
        csvHistoryDateFilterEnabled = false
        csvHistorySelectedPreset = nil
        let today = Calendar.current.startOfDay(for: Date())
        csvHistoryStartDate = today
        csvHistoryEndDate = today
        csvRetryHistoryExportURL = nil
        csvHistorySavePending = false
        csvHistoryWriteFailure = false
        csvHistoryActionFeedback = nil
        csvHistoryFeedbackState = nil
        csvHistoryDismissedFeedbackKey = nil
        csvHistoryDismissedState = nil
    }

    // FIXED342: Keep the persistent status independent of dismissible action feedback.
    // VoiceOver can still read the current status after a notification is dismissed.
    private var csvHistoryAccessibleStatus: String {
        [csvHistorySaveStatusText, csvHistoryLastSavedText].compactMap { $0 }.joined(separator: "。")
    }

    private func dismissCSVHistoryFeedback(rememberDismissal: Bool = false) {
        if rememberDismissal, let message = csvHistoryActionFeedback {
            csvHistoryDismissedFeedbackKey = message + "|" + csvHistoryActionFeedbackSymbol
            csvHistoryDismissedState = csvHistoryFeedbackState
        }
        csvHistoryActionFeedback = nil
        csvHistoryFeedbackState = nil
    }

    // FIXED341: VoiceOver announces only meaningful action feedback.
    // Routine typing remains silent (FIXED340) to avoid interrupting dictation.
    private func showCSVHistoryFeedback(_ message: String, symbol: String) {
        let state = csvHistorySaveStatusText
        // A change of save state permits new feedback; a dismissed notification
        // is not resurrected by another action in the same state.
        if csvHistoryDismissedState != state {
            csvHistoryDismissedFeedbackKey = nil
            csvHistoryDismissedState = nil
        }
        let decision = CSVHistoryFeedbackDecision.evaluate(
            message: message, symbol: symbol, state: state,
            dismissedKey: csvHistoryDismissedFeedbackKey, dismissedState: csvHistoryDismissedState,
            activeMessage: csvHistoryActionFeedback,
            activeSymbol: csvHistoryActionFeedbackSymbol, activeState: csvHistoryFeedbackState
        )
        guard decision.shouldPresent else { return }
        csvHistoryActionFeedback = message
        csvHistoryActionFeedbackSymbol = symbol
        csvHistoryFeedbackState = state
        if UIAccessibility.isVoiceOverRunning {
            // FIXED342: Include the same current status shown on screen.
            UIAccessibility.post(notification: .announcement,
                                 argument: decision.announcement)
        }
    }

    // FIXED340: Routine edits save silently; notify only on a state transition or explicit retry.
    private func saveCSVHistoryFilters(explicitRetry: Bool = false) {
        guard !csvHistoryRestoreInProgress else { return }
        let wasPending = csvHistorySavePending
        let wasWriteFailure = csvHistoryWriteFailure
        let wasRestoreError = csvHistoryRestoreNotice != nil

        let preferences = csvHistoryCurrentPreferences
        // FIXED331: Never replace a valid saved snapshot with an invalid
        // intermediate state (for example, while editing a date range).
        guard let data = try? JSONEncoder().encode(preferences),
              CSVHistoryFilterPreferences.validated(from: data) != nil else {
            csvHistorySavePending = true
            csvHistoryWriteFailure = false
            // Clear a previous success/revert message as soon as saving becomes invalid.
            if !wasPending { dismissCSVHistoryFeedback() }
            if !wasPending || explicitRetry {
                showCSVHistoryFeedback("保存を保留しました。開始日と終了日を確認してください。", symbol: "clock.badge.exclamationmark")
            }
            csvRetryHistoryExportURL = nil
            return
        }
        // FIXED351: Confirm that the saved bytes can actually be read back before
        // advancing the last-successful-save timestamp or showing success.
        let writeResult = CSVHistoryVerifiedWriter.save(
            data, in: UserDefaults.standard, key: csvHistoryFiltersKey
        )
        guard case .saved = writeResult else {
            csvHistoryWriteFailure = true
            csvHistorySavePending = true
            // FIXED354: The timestamp and saved-state badge must describe the
            // same recoverable snapshot, even if rollback could not complete.
            let recovered = CSVHistoryFailedSaveInspection.inspect(
                defaults: UserDefaults.standard,
                filtersKey: csvHistoryFiltersKey,
                timestampKey: csvHistoryLastSavedKey
            )
            csvHistoryHasSavedSnapshot = recovered.hasSavedSnapshot
            csvHistoryLastSavedAt = recovered.lastSavedAt
            dismissCSVHistoryFeedback()
            showCSVHistoryFeedback("検索条件の保存を確認できませんでした。再保存してください。", symbol: "exclamationmark.triangle.fill")
            csvRetryHistoryExportURL = nil
            return
        }
        csvHistoryWriteFailure = false
        let savedAt = Date()
        csvHistoryLastSavedAt = CSVHistorySavedTimestamp.recordSuccessfulSave(
            in: UserDefaults.standard, key: csvHistoryLastSavedKey, at: savedAt
        )
        csvHistoryHasSavedSnapshot = true
        csvHistorySavePending = false
        // FIXED359: Only a verified save clears the restore warning.
        // Failed attempts leave it intact for the next retry.
        let retryTransition = CSVHistoryRestoreRetryTransition.evaluate(
            previousNotice: csvHistoryRestoreNotice, result: .verified
        )
        csvHistoryRestoreNotice = retryTransition.restoreNotice
        if wasWriteFailure {
            showCSVHistoryFeedback("検索条件を再保存しました。", symbol: "checkmark.circle.fill")
        } else if wasRestoreError, let message = retryTransition.feedback {
            showCSVHistoryFeedback(message, symbol: "checkmark.circle.fill")
        } else if wasPending {
            showCSVHistoryFeedback("検索条件を修正して保存しました。", symbol: "checkmark.circle.fill")
        } else if explicitRetry {
            showCSVHistoryFeedback("検索条件を保存しました。", symbol: "checkmark.circle.fill")
        } else {
            // A previous notification must not linger after another routine edit.
            dismissCSVHistoryFeedback()
        }
        csvRetryHistoryExportURL = nil
    }

    // FIXED337: Restore the stored filters without writing a new snapshot or timestamp.
    // A damaged/missing snapshot is handled by the existing recovery UI instead.
    private func revertCSVHistoryFiltersToSaved() {
        guard case .restored(let preferences, let start, let end) =
                CSVHistoryRevertDecision.evaluate(
                    confirmed: true,
                    stored: UserDefaults.standard.object(forKey: csvHistoryFiltersKey)
                ) else {
            // FIXED356: The stored snapshot may have disappeared or become corrupt
            // while the confirmation sheet was open. Never apply stale UI values.
            restoreCSVHistoryFilters()
            csvHistoryRestoreNotice = "前回の保存内容を確認できませんでした。検索条件を初期化しました。必要に応じて再設定してください。"
            return
        }
        csvHistoryRestoreInProgress = true
        defer { csvHistoryRestoreInProgress = false }
        csvHistorySearch = preferences.search
        csvHistoryStatus = preferences.status
        csvHistoryScope = preferences.scope
        csvHistoryStartDate = start
        csvHistoryEndDate = end
        csvHistoryDateFilterEnabled = preferences.dateEnabled
        csvHistorySelectedPreset = preferences.dateEnabled ? preferences.preset : nil
        csvHistorySavePending = false
        csvHistoryWriteFailure = false
        csvHistoryRestoreNotice = nil
        csvHistoryHasSavedSnapshot = true
        csvHistoryLastSavedAt = CSVHistorySavedTimestamp.read(
            from: UserDefaults.standard, key: csvHistoryLastSavedKey, hasValidSnapshot: true
        )
        showCSVHistoryFeedback("保存済みの検索条件に戻しました。", symbol: "arrow.uturn.backward.circle.fill")
        csvRetryHistoryExportURL = nil
    }

    // FIXED321: Validate persisted preferences before applying any of them.
    // Corrupt or incompatible data is discarded rather than leaving partial state.
    private func restoreCSVHistoryFilters() {
        // Restore is transactional: no UI-triggered write can run mid-restore.
        csvHistoryRestoreInProgress = true
        defer { csvHistoryRestoreInProgress = false }
        csvHistoryRestoreNotice = nil
        dismissCSVHistoryFeedback()
        csvHistorySavePending = false
        csvHistoryWriteFailure = false
        csvHistoryHasSavedSnapshot = false
        csvHistoryLastSavedAt = nil
        switch CSVHistoryFilterRecovery.recover(UserDefaults.standard.object(forKey: csvHistoryFiltersKey)) {
        case .missing:
            // FIXED338: A missing snapshot must not leave stale controls or a pending badge.
            resetCSVHistoryFiltersToDefaults()
            CSVHistorySavedTimestamp.clear(in: UserDefaults.standard, key: csvHistoryLastSavedKey)
            return
        case .invalid:
            resetCSVHistoryFiltersToDefaults()
            UserDefaults.standard.removeObject(forKey: csvHistoryFiltersKey)
            CSVHistorySavedTimestamp.clear(in: UserDefaults.standard, key: csvHistoryLastSavedKey)
            csvHistoryRestoreNotice = "保存された検索条件を復元できなかったため、初期状態に戻しました。検索条件は再設定できます。"
            csvRetryHistoryExportURL = nil
        case .restored(let preferences, let start, let end, let upgraded):
            // FIXED329: Commit only after all validation, migration and date restoration succeed.
            if let upgraded { UserDefaults.standard.set(upgraded, forKey: csvHistoryFiltersKey) }
            csvHistoryHasSavedSnapshot = true
            csvHistoryLastSavedAt = CSVHistorySavedTimestamp.read(
                from: UserDefaults.standard, key: csvHistoryLastSavedKey, hasValidSnapshot: true
            )
            csvHistorySearch = preferences.search
            csvHistoryStatus = preferences.status
            csvHistoryScope = preferences.scope
            csvHistoryStartDate = start
            csvHistoryEndDate = end
            csvHistoryDateFilterEnabled = preferences.dateEnabled
            csvHistorySelectedPreset = preferences.dateEnabled ? preferences.preset : nil
            // FIXED338: Restore the exact saved dates. Recomputing a relative preset
            // would make the screen differ from the saved snapshot on a later day.
            csvRetryHistoryExportURL = nil
        }
    }

    // FIXED316/317: One-tap inclusive calendar-day presets. Preserve other filters.
    private func applyCSVHistoryDatePreset(_ preset: String) {
        setCSVHistoryDatePreset(preset, persist: true)
    }

    private func setCSVHistoryDatePreset(_ preset: String, persist: Bool) {
        guard let range = CSVHistoryDateRange.forPreset(preset) else { return }
        csvHistoryStartDate = range.start
        csvHistoryEndDate = range.end
        csvHistoryDateFilterEnabled = true
        csvHistorySelectedPreset = preset
        if persist { saveCSVHistoryFilters() }
    }

    private func csvRetryDate(from entry: String) -> Date? {
        guard let raw = entry.components(separatedBy: "｜").first else { return nil }
        // Older entries were saved using the user's local numeric date/time format.
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        formatter.isLenient = false
        if let date = formatter.date(from: raw) { return date }
        // Also accept stable ISO-style timestamps for imported/future entries.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }

    private var csvHistoryDateRangeValid: Bool {
        !csvHistoryDateFilterEnabled ||
            Calendar.current.startOfDay(for: csvHistoryStartDate) <= Calendar.current.startOfDay(for: csvHistoryEndDate)
    }


    private var filteredCSVRetryHistory: [(offset: Int, element: String)] {
        Array(csvRetryHistory.enumerated()).filter { item in
            let parts = item.element.components(separatedBy: "｜")
            let scope = parts.count > 1 ? parts[1] : ""
            let status = parts.count > 2 ? parts[2] : ""
            let searchMatches = csvHistorySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                item.element.localizedStandardContains(csvHistorySearch)
            let dateMatches: Bool
            if !csvHistoryDateFilterEnabled {
                dateMatches = true
            } else if csvHistoryDateRangeValid, let date = csvRetryDate(from: item.element) {
                let day = Calendar.current.startOfDay(for: date)
                dateMatches = day >= Calendar.current.startOfDay(for: csvHistoryStartDate) &&
                    day <= Calendar.current.startOfDay(for: csvHistoryEndDate)
            } else {
                dateMatches = false
            }
            return searchMatches && dateMatches &&
                (csvHistoryStatus == "すべて" || status == csvHistoryStatus) &&
                (csvHistoryScope == "すべて" || scope == csvHistoryScope)
        }
    }

    // FIXED313: Export the saved audit trail as UTF-8 with BOM for Excel.
    // Quotes, commas and line breaks are escaped without changing the stored format.
    private func createCSVRetryHistoryExport(filteredOnly: Bool) -> URL? {
        let entries = filteredOnly ? filteredCSVRetryHistory.map(\.element) : csvRetryHistory
        guard !entries.isEmpty else { return nil }
        func cell(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var rows = ["日時,CSV種類,結果,詳細"]
        for entry in entries {
            let parts = entry.components(separatedBy: "｜")
            let fields: [String]
            if parts.count >= 4 {
                fields = [parts[0], parts[1], parts[2], parts.dropFirst(3).joined(separator: "｜")]
            } else {
                // Preserve legacy or malformed entries instead of silently dropping them.
                fields = ["", "", "", entry]
            }
            rows.append(fields.map(cell).joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HOTEL_SHIFT_CSV再試行履歴_\(filteredOnly ? "絞り込み" : "全件")_\(UUID().uuidString).csv")
        do {
            try ("\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n")
                .write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // FIXED450: Avoid mixing distinct ButtonStyle concrete types in a ternary.
    @ViewBuilder
    private func csvHistoryPresetButton(_ preset: String) -> some View {
        let selected = csvHistoryDateFilterEnabled && csvHistorySelectedPreset == preset
        if selected {
            Button(preset) { applyCSVHistoryDatePreset(preset) }
                .frame(maxWidth: .infinity)
                .modifier(AppActionStyle(prominent: true))
                .controlSize(.small)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(preset) { applyCSVHistoryDatePreset(preset) }
                .frame(maxWidth: .infinity)
                .modifier(AppActionStyle())
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var csvRetryHistoryView: some View {
        // FIXED333: Status remains visible even when there are no retry records.
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: csvHistorySaveStatusSymbol)
                .foregroundStyle(csvHistoryRestoreNotice != nil || csvHistorySavePending || csvHistoryWriteFailure ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(csvHistorySaveStatusText)
                    .font(.caption)
                if let csvHistoryLastSavedText {
                    Text(csvHistoryLastSavedText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(csvHistoryAccessibleStatus)
        .accessibilityAddTraits(.isStaticText)
        // FIXED339: Acknowledge a completed action without obscuring the persistent status.
        // FIXED343: Never display feedback from an obsolete save state.
        if let csvHistoryActionFeedback, csvHistoryFeedbackState == csvHistorySaveStatusText {
            HStack(spacing: 8) {
                Image(systemName: csvHistoryActionFeedbackSymbol)
                    .foregroundStyle(csvHistorySavePending ? .orange : .green)
                Text(CSVHistoryFeedbackPresentation.visibleMessage(csvHistoryActionFeedback))
                    .font(.caption)
                    .accessibilityLabel("操作通知：" + CSVHistoryFeedbackPresentation.visibleMessage(csvHistoryActionFeedback))
                Spacer(minLength: 4)
                Button("閉じる") { dismissCSVHistoryFeedback(rememberDismissal: true) }
                    .font(.caption)
                    .accessibilityLabel("検索条件の操作通知を閉じる")
                    .accessibilityHint("通知のみ閉じます。保存状態は引き続き確認できます")
            }
            .padding(8)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            // Keep the dismiss button separately reachable with VoiceOver.
            .accessibilityElement(children: .contain)
        }
        // FIXED337: A pending edit can be discarded explicitly, with confirmation.
        if csvHistoryHasSavedSnapshot &&
           (csvHistorySavePending || csvHistoryWriteFailure || !csvHistoryMatchesSavedSnapshot) &&
           csvHistoryRestoreNotice == nil {
            Button {
                confirmingCSVHistoryRevert = true
            } label: {
                Label("前回の保存内容に戻す", systemImage: "arrow.uturn.backward.circle")
                    .accessibilityHint("編集中の変更を破棄し、前回保存した検索条件を読み込みます。確認画面が開きます")
            }
            .font(.caption)
            .confirmationDialog("編集中の検索条件を破棄しますか？", isPresented: $confirmingCSVHistoryRevert, titleVisibility: .visible) {
                Button("保存済みの条件に戻す", role: .destructive) {
                    revertCSVHistoryFiltersToSaved()
                }
                .accessibilityHint("編集中の検索条件を破棄し、前回の保存内容を復元します。シフトやCSV履歴は変更しません")
                Button("キャンセル", role: .cancel) {
                    // FIXED356: Cancel is intentionally side-effect free.
                    confirmingCSVHistoryRevert = false
                }
                .accessibilityHint("検索条件を変更せず、確認画面を閉じます")
            } message: {
                Text("編集中の検索条件だけを破棄して、前回の保存内容に戻します。再保存は行わず、最終保存日時も変更しません。シフトやCSV履歴は削除されません。")
            }
        }
        if let csvHistoryRestoreNotice {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(csvHistoryRestoreNotice)
                    .font(.caption)
                Spacer(minLength: 4)
                Button("閉じる") { self.csvHistoryRestoreNotice = nil }
                    .font(.caption)
                    .accessibilityLabel("検索条件の復元エラー通知を閉じる")
                    .accessibilityHint("通知のみ閉じます。検索条件の保存状態は変わりません")
            }
            .padding(10)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
        }
        // FIXED332: Surface the pending state and allow an explicit retry.
        if csvHistorySavePending {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(csvHistoryWriteFailure ? "検索条件の保存に失敗しました" : "検索条件の保存を保留しています")
                        .font(.caption).fontWeight(.semibold)
                    Text(csvHistoryWriteFailure
                         ? (csvHistoryHasSavedSnapshot
                            ? "編集内容を残す場合は「現在の条件を再保存」、破棄する場合は「前回の保存内容に戻す」を選んでください。"
                            : "戻せる保存内容はありません。入力内容を確認して「現在の条件を再保存」を選んでください。")
                         : "開始日と終了日を確認してください。正しい期間に修正すると自動で保存します。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button("現在の条件を再保存") { saveCSVHistoryFilters(explicitRetry: true) }
                    .font(.caption)
                    .accessibilityHint("画面に表示されている検索条件を保存します。前回の保存内容に戻す操作とは異なります")
                    .disabled(!csvHistoryDateRangeValid)
            }
            .padding(10)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
        if !csvRetryHistory.isEmpty {
            DisclosureGroup("CSV再試行履歴（\(filteredCSVRetryHistory.count)/\(csvRetryHistory.count)件）") {
                TextField("日時・エラー内容を検索", text: Binding(
                    get: { csvHistorySearch },
                    set: { csvHistorySearch = $0; saveCSVHistoryFilters() }
                ))
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Picker("結果", selection: Binding(
                        get: { csvHistoryStatus },
                        set: { csvHistoryStatus = $0; saveCSVHistoryFilters() }
                    )) {
                        ForEach(["すべて", "成功", "失敗"], id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    Picker("CSV種類", selection: Binding(
                        get: { csvHistoryScope },
                        set: { csvHistoryScope = $0; saveCSVHistoryFilters() }
                    )) {
                        ForEach(["すべて", "全件CSV", "絞り込みCSV"], id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                }
                // FIXED318: Adaptive grid wraps preset buttons on narrow iPad panes
                // instead of shrinking labels into a single unreadable row.
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("期間ショートカット")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        if csvHistoryDateFilterEnabled {
                            Button("期間を解除") {
                                csvHistoryDateFilterEnabled = false
                                csvHistorySelectedPreset = nil
                                saveCSVHistoryFilters()
                            }
                            .font(.caption)
                            .accessibilityLabel("期間指定のみを解除")
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(["今日", "過去7日間", "過去30日間", "今月", "先月"], id: \.self) { preset in
                            csvHistoryPresetButton(preset)
                        }
                    }
                    if csvHistoryDateFilterEnabled {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(csvHistorySelectedPreset ?? "手動指定")
                                .font(.caption).fontWeight(.semibold)
                            Text("\(csvHistoryStartDate.formatted(date: .numeric, time: .omitted)) ～ \(csvHistoryEndDate.formatted(date: .numeric, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Toggle("期間を指定する", isOn: Binding(
                    get: { csvHistoryDateFilterEnabled },
                    set: { enabled in
                        csvHistoryDateFilterEnabled = enabled
                        if !enabled { csvHistorySelectedPreset = nil }
                        saveCSVHistoryFilters()
                    }
                ))
                if csvHistoryDateFilterEnabled {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], alignment: .leading, spacing: 8) {
                        DatePicker("開始日", selection: Binding(get: { csvHistoryStartDate }, set: { csvHistoryStartDate = $0; csvHistorySelectedPreset = nil; saveCSVHistoryFilters() }), displayedComponents: .date)
                        DatePicker("終了日", selection: Binding(get: { csvHistoryEndDate }, set: { csvHistoryEndDate = $0; csvHistorySelectedPreset = nil; saveCSVHistoryFilters() }), displayedComponents: .date)
                    }
                    if !csvHistoryDateRangeValid {
                        Text("終了日は開始日以降を指定してください。")
                            .font(.caption).foregroundStyle(.red)
                    }
                    Text("開始日と終了日を含む期間で検索します。日付を読み取れない古い履歴は対象外です。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if filteredCSVRetryHistory.isEmpty {
                    Text("条件に一致する履歴はありません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(filteredCSVRetryHistory, id: \.offset) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.element)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button(role: .destructive) {
                            deleteCSVRetryHistoryEntry(at: item.offset)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("このCSV再試行履歴を削除")
                    }
                }
                HStack {
                    Button {
                        csvRetryHistoryExportURL = createCSVRetryHistoryExport(filteredOnly: false)
                    } label: {
                        Label("保存履歴のCSVを作成", systemImage: "doc.badge.arrow.up")
                    }
                    .modifier(AppActionStyle())
                    Button {
                        csvRetryHistoryExportURL = createCSVRetryHistoryExport(filteredOnly: true)
                    } label: {
                        Label("検索結果のCSVを作成（\(filteredCSVRetryHistory.count)件）", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .modifier(AppActionStyle())
                    .disabled(filteredCSVRetryHistory.isEmpty)
                    if let csvRetryHistoryExportURL {
                        ShareLink(item: csvRetryHistoryExportURL) {
                            Label("CSVを共有", systemImage: "square.and.arrow.up")
                        }
                        .modifier(AppActionStyle(prominent: true))
                    }
                }
                Text("「保存履歴」は全件、「検索結果」は現在の検索・絞り込み・期間条件に一致する履歴のみを出力します。")
                    .font(.caption2).foregroundStyle(.secondary)
                Button("検索条件を解除") {
                    csvHistorySearch = ""
                    csvHistoryStatus = "すべて"
                    csvHistoryScope = "すべて"
                    csvHistoryDateFilterEnabled = false
                    csvHistorySelectedPreset = nil
                    saveCSVHistoryFilters()
                }
                .font(.caption)
                Button(role: .destructive) {
                    confirmingCSVRetryHistoryClear = true
                } label: {
                    Label("履歴をすべて削除", systemImage: "trash")
                }
                .confirmationDialog(
                    "CSV再試行履歴をすべて削除しますか？",
                    isPresented: $confirmingCSVRetryHistoryClear,
                    titleVisibility: .visible
                ) {
                    Button("すべて削除", role: .destructive) {
                        clearCSVRetryHistory()
                    }
                    Button("キャンセル", role: .cancel) { }
                } message: {
                    Text("検索条件に関係なく、端末内のすべての履歴を削除します。シフトやCSVファイルは削除されません。")
                }
                Text("最新20件を保存。検索中の個別削除は元の履歴に反映されます。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @State private var showingDetailCSVPreview = false
    // FIXED289: Keep detailed CSV comparisons collapsed until requested.
    @State private var showingCSVExportDetails = false
    // FIXED298: Retain the previous matching row count for a visible filter-change comparison.
    // FIXED299: Keep a full snapshot even when a filter edit leaves row count unchanged.
    @State private var previousFilteredExportMetrics: (staff: Int, shifts: Int, cost: Int)?
    @State private var currentFilteredExportMetrics: (staff: Int, shifts: Int, cost: Int)?
    // FIXED272: Filter the preview only; the exported CSV remains complete.
    @State private var detailPreviewStaffQuery = ""
    // FIXED274: An optional shift-type filter is combined with staff-name search.
    @State private var detailPreviewShiftType: ShiftType? = nil
    // FIXED275: Date bounds apply to both the preview and filtered CSV.
    @State private var detailPreviewDateFilterEnabled = false
    @State private var detailPreviewFrom = Date()
    @State private var detailPreviewUntil = Date()

    // FIXED267: Export the same confirmed preview and completed result shown on screen.
    private func createComparisonCSV(expected: ShiftStore.PatternApplicationResult,
                                     actual: ShiftStore.PatternApplicationResult) -> URL? {
        func escape(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var rows = ["スタッフ名,登録予定件数,実際の登録件数,予定概算人件費(円),登録概算人件費(円),差額(円)"]
        for item in actual.staffResults {
            let planned = expected.staffResults.first { $0.staffID == item.staffID }
            let values = [item.staffName, String(planned?.added ?? 0), String(item.added),
                          String(planned?.estimatedCost ?? 0), String(item.estimatedCost),
                          String(item.estimatedCost - (planned?.estimatedCost ?? 0))]
            rows.append(values.map(escape).joined(separator: ","))
        }
        let totalExpected = estimatedTotal(expected)
        let totalActual = estimatedTotal(actual)
        rows.append(["合計", String(expected.added), String(actual.added),
                     String(totalExpected), String(totalActual), String(totalActual - totalExpected)]
            .map(escape).joined(separator: ","))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "勤務パターン適用比較_\(Date().shiftDateKey)_\(UUID().uuidString).csv")
        let csv = "\u{FEFF}" + rows.joined(separator: "\r\n")
        guard let bytes = csv.data(using: .utf8),
              (try? bytes.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    // FIXED302: A single row-selection rule is shared by the CSV writer and
    // the on-screen preview/summary, preventing divergent counts and costs.
    private func detailCSVShifts(
        for staff: ShiftStore.PatternStaffResult,
        shiftType: ShiftType? = nil,
        dateRange: ClosedRange<String>? = nil
    ) -> [ShiftStore.PatternRegisteredShift] {
        staff.registeredShifts.filter { shift in
            (shiftType == nil || shift.type == shiftType) &&
            (dateRange == nil || dateRange!.contains(shift.dateKey))
        }
    }

    // FIXED268: Detail export uses the assignments recorded in the completed report.
    // Missing clock values remain blank rather than being represented as zero hours.
    private func createDetailCSV(actual: ShiftStore.PatternApplicationResult, staffIDs: Set<UUID>? = nil, shiftType: ShiftType? = nil, dateRange: ClosedRange<String>? = nil, exportConditions: [String] = [], generatedAt: Date = Date()) -> URL? {
        func escape(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        // FIXED279: Count the same shifts that will be written below, and record
        // the local export timestamp. Leave the legacy full-export format intact.
        let selectedStaff = actual.staffResults.filter { staffIDs == nil || staffIDs!.contains($0.staffID) }
        var rows: [String] = []
        if !exportConditions.isEmpty {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let shiftCount = selectedStaff.reduce(0) { $0 + detailCSVShifts(for: $1, shiftType: shiftType, dateRange: dateRange).count }
            rows.append(["出力対象", "絞り込み結果"].map(escape).joined(separator: ","))
            rows.append(["出力日時", formatter.string(from: generatedAt)].map(escape).joined(separator: ","))
            rows.append(["対象件数", String(shiftCount)].map(escape).joined(separator: ","))
            for condition in exportConditions {
                rows.append(["検索条件", condition].map(escape).joined(separator: ","))
            }
            rows.append("")
        }
        rows.append("スタッフ名,勤務日,勤務区分,開始時刻,終了時刻,休憩時間(分),概算実働時間(分),適用時給(円),概算人件費(円)")
        for staff in selectedStaff {
            for shift in detailCSVShifts(for: staff, shiftType: shiftType, dateRange: dateRange) {
                let start = shift.startMinutes
                let end = shift.endMinutes
                func clock(_ minutes: Int) -> String {
                    String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
                }
                let validDuration = start != nil && end != nil && end! > start!
                let duration = validDuration ? end! - start! : 0
                let rest = validDuration ? min(duration, max(0, shift.breakMinutes ?? (duration > 480 ? 60 : (duration > 360 ? 45 : 0)))) : 0
                let values = [staff.staffName, shift.dateKey, shift.type.rawValue,
                              start.map(clock) ?? "",
                              end.map { ($0 >= 1440 ? "翌" : "") + clock($0) } ?? "",
                              validDuration ? String(rest) : "",
                              validDuration ? String(duration - rest) : "",
                              String(shift.hourlyWage), String(shift.estimatedCost)]
                rows.append(values.map(escape).joined(separator: ","))
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "勤務パターン登録明細_\(staffIDs == nil ? "全スタッフ" : "検索結果")_\(Date().shiftDateKey)_\(UUID().uuidString).csv")
        let csv = "\u{FEFF}" + rows.joined(separator: "\r\n")
        guard let bytes = csv.data(using: .utf8),
              (try? bytes.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    private var detailPreviewDateRange: ClosedRange<String>? {
        guard detailPreviewDateFilterEnabled else { return nil }
        let start = detailPreviewFrom.shiftDateKey
        let end = detailPreviewUntil.shiftDateKey
        guard start <= end else { return nil }
        return start...end
    }

    private var detailPreviewValidRange: Bool {
        !detailPreviewDateFilterEnabled || detailPreviewFrom.shiftDateKey <= detailPreviewUntil.shiftDateKey
    }

    private func matchesDetailPreview(_ shift: ShiftStore.PatternRegisteredShift) -> Bool {
        guard detailPreviewValidRange else { return false }
        return (detailPreviewShiftType == nil || shift.type == detailPreviewShiftType) &&
        (detailPreviewDateRange == nil || detailPreviewDateRange!.contains(shift.dateKey))
    }

    // FIXED302: The preview uses exactly the CSV export's shift selector.
    private func previewDetailShifts(for staff: ShiftStore.PatternStaffResult) -> [ShiftStore.PatternRegisteredShift] {
        guard detailPreviewValidRange else { return [] }
        return detailCSVShifts(for: staff, shiftType: detailPreviewShiftType, dateRange: detailPreviewDateRange)
    }

    private func previewStaffResults(_ report: ShiftStore.PatternApplicationResult) -> [ShiftStore.PatternStaffResult] {
        let query = detailPreviewStaffQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return report.staffResults.filter { staff in
            (query.isEmpty || staff.staffName.localizedStandardContains(query)) &&
            !previewDetailShifts(for: staff).isEmpty
        }
    }

    // FIXED277: Keep the active search criteria visible above the preview results.
    private var detailPreviewActiveConditions: [String] {
        var conditions: [String] = []
        let name = detailPreviewStaffQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { conditions.append("スタッフ名：\(name)") }
        if let type = detailPreviewShiftType { conditions.append("勤務区分：\(type.rawValue)") }
        if detailPreviewDateFilterEnabled {
            conditions.append("勤務日：\(detailPreviewFrom.shiftDateKey) 〜 \(detailPreviewUntil.shiftDateKey)")
        }
        return conditions
    }

    // FIXED292: One shared reset action for the filter section and the empty-result shortcut.
    private func resetDetailPreviewFilters() {
        detailPreviewStaffQuery = ""
        detailPreviewShiftType = nil
        detailPreviewDateFilterEnabled = false
        refreshFilteredDetailCSV()
    }

    // FIXED273: Rebuild the filtered file when the search changes; the original export remains untouched.
    private func refreshFilteredDetailCSV() {
        filteredCSVRetryMessage = nil
        guard let completedReport, detailPreviewValidRange else {
            filteredDetailCSVURL = nil
            filteredDetailCSVGeneratedAt = nil
            filteredDetailCSVVerification = nil
            return
        }
        let ids = Set(previewStaffResults(completedReport).map(\.staffID))
        let generatedAt = Date()
        filteredDetailCSVURL = ids.isEmpty ? nil : createDetailCSV(actual: completedReport, staffIDs: ids, shiftType: detailPreviewShiftType, dateRange: detailPreviewDateRange, exportConditions: detailPreviewActiveConditions.isEmpty ? ["検索条件なし（全件表示）"] : detailPreviewActiveConditions, generatedAt: generatedAt)
        filteredDetailCSVGeneratedAt = filteredDetailCSVURL == nil ? nil : generatedAt
        if let url = filteredDetailCSVURL {
            let selected = previewStaffResults(completedReport)
            let expectedRows = selected.reduce(0) { $0 + previewDetailShifts(for: $1).count }
            let expectedCost = selected.reduce(0) { $0 + previewDetailShifts(for: $1).reduce(0) { $0 + $1.estimatedCost } }
            filteredDetailCSVVerification = verifyDetailCSVFile(url, expectedRows: expectedRows, expectedCost: expectedCost)
        } else {
            filteredDetailCSVVerification = nil
        }
    }

    // FIXED307: A retry is distinct from automatic regeneration on filter edits.
    private func retryFilteredDetailCSV() {
        filteredCSVRetryMessage = nil
        refreshFilteredDetailCSV()
        if let verification = filteredDetailCSVVerification {
            filteredCSVRetryMessage = verification.matches
                ? "再照合成功：\(verification.rows)件・¥\(verification.cost.formatted())。共有できます。"
                : "再照合不一致：" + csvVerificationFailureReasons(verification,
                    expectedRows: completedReport.map { previewStaffResults($0).reduce(0) { $0 + previewDetailShifts(for: $1).count } } ?? 0,
                    expectedCost: completedReport.map { previewStaffResults($0).reduce(0) { $0 + previewDetailShifts(for: $1).reduce(0) { $0 + $1.estimatedCost } } } ?? 0
                  ).joined(separator: "／")
        } else {
            filteredCSVRetryMessage = "再生成または再照合に失敗しました。検索条件と保存先を確認してください。"
        }
        recordCSVRetry(scope: "絞り込みCSV", success: filteredDetailCSVVerification?.matches == true,
                       details: filteredCSVRetryMessage ?? "結果不明")
    }

    // FIXED306: Recreate the original full-detail export and verify its bytes again.
    // Keep sharing disabled until the regenerated file passes verification.
    private func retryFullDetailCSV() {
        fullCSVRetryMessage = nil
        detailCSVURL = nil
        fullDetailCSVVerification = nil
        guard let completedReport else {
            fullCSVRetryMessage = "再試行できません：適用結果がありません。"
            recordCSVRetry(scope: "全件CSV", success: false, details: fullCSVRetryMessage ?? "適用結果なし")
            return
        }
        let expectedRows = completedReport.staffResults.reduce(0) {
            $0 + detailCSVShifts(for: $1, shiftType: nil, dateRange: nil).count
        }
        let expectedCost = completedReport.staffResults.reduce(0) { total, staff in
            total + detailCSVShifts(for: staff, shiftType: nil, dateRange: nil).reduce(0) { $0 + $1.estimatedCost }
        }
        guard let url = createDetailCSV(actual: completedReport) else {
            fullCSVRetryMessage = "再生成に失敗しました。保存先と空き容量を確認してください。"
            recordCSVRetry(scope: "全件CSV", success: false, details: fullCSVRetryMessage ?? "生成失敗")
            return
        }
        let result = verifyDetailCSVFile(url, expectedRows: expectedRows, expectedCost: expectedCost)
        fullDetailCSVVerification = result
        if result?.matches == true {
            detailCSVURL = url
            fullCSVRetryMessage = "再照合成功：\(expectedRows)件・¥\(expectedCost.formatted())。共有できます。"
        } else {
            fullCSVRetryMessage = result == nil
                ? "再照合に失敗しました。CSVを読み取れませんでした。"
                : "再照合不一致：" + csvVerificationFailureReasons(result, expectedRows: expectedRows, expectedCost: expectedCost).joined(separator: "／") + "。共有は停止中です。"
        }
        recordCSVRetry(scope: "全件CSV", success: result?.matches == true,
                       details: fullCSVRetryMessage ?? "結果不明")
    }

    // FIXED303: Inspect the actual UTF-8 CSV bytes rather than trusting the
    // preview totals. All detail CSV data cells are quoted; doubled quotes
    // inside staff names are decoded before checking the last cost column.
    private func verifyDetailCSVFile(_ url: URL, expectedRows: Int, expectedCost: Int) -> (rows: Int, cost: Int, matches: Bool)? {
        guard let data = try? Data(contentsOf: url),
              let contents = String(data: data, encoding: .utf8) else { return nil }
        let header = "スタッフ名,勤務日,勤務区分,開始時刻,終了時刻,休憩時間(分),概算実働時間(分),適用時給(円),概算人件費(円)"
        let lines = contents.replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .newlines) }
        guard let headerIndex = lines.firstIndex(of: header) else { return nil }
        var rows = 0
        var cost = 0
        for line in lines.dropFirst(headerIndex + 1) where !line.isEmpty {
            var cells: [String] = []
            var field = ""
            var quoted = false
            let chars = Array(line)
            var index = 0
            while index < chars.count {
                let character = chars[index]
                if character == "\"" {
                    if quoted && index + 1 < chars.count && chars[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        quoted.toggle()
                    }
                } else if character == "," && !quoted {
                    cells.append(field)
                    field = ""
                } else {
                    field.append(character)
                }
                index += 1
            }
            cells.append(field)
            guard !quoted, cells.count == 9, let rowCost = Int(cells[8]) else { return nil }
            rows += 1
            cost += rowCost
        }
        return (rows, cost, rows == expectedRows && cost == expectedCost)
    }

    // FIXED308: Classify the failure independently for full and filtered exports.
    // A nil result means the file could not be read or parsed; generation failures
    // are reported separately by the retry actions before verification begins.
    private func csvVerificationFailureReasons(
        _ verification: (rows: Int, cost: Int, matches: Bool)?,
        expectedRows: Int,
        expectedCost: Int
    ) -> [String] {
        guard let verification else { return ["CSV読み取り・解析失敗：ファイルを読み取れないか、列形式が不正です。"] }
        var reasons: [String] = []
        if verification.rows != expectedRows {
            reasons.append("勤務件数不一致：予定\(expectedRows)件 / CSV\(verification.rows)件")
        }
        if verification.cost != expectedCost {
            reasons.append("概算人件費不一致：予定¥\(expectedCost.formatted()) / CSV¥\(verification.cost.formatted())")
        }
        return reasons
    }

    // FIXED305: Display both sides of a failed CSV verification, not only the
    // observed values. The expected values are computed from the same shift
    // selection used by the CSV writer, and a failed verification blocks sharing.
    @ViewBuilder
    private func csvVerificationDetails(
        _ verification: (rows: Int, cost: Int, matches: Bool)?,
        expectedRows: Int,
        expectedCost: Int,
        title: String
    ) -> some View {
        if let verification, !verification.matches {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(title)：照合不一致", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                ForEach(csvVerificationFailureReasons(verification, expectedRows: expectedRows, expectedCost: expectedCost), id: \.self) { reason in
                    Text(reason).fontWeight(.semibold)
                }
                LabeledContent("勤務件数（予定 / CSV）", value: "\(expectedRows)件 / \(verification.rows)件")
                LabeledContent("勤務件数の差", value: "\(verification.rows - expectedRows)件")
                LabeledContent("概算人件費（予定 / CSV）", value: "¥\(expectedCost.formatted()) / ¥\(verification.cost.formatted())")
                LabeledContent("概算人件費の差", value: "\(verification.cost - expectedCost)円")
                Text("出力ファイルの内容が画面集計と一致しないため、共有を停止しています。")
            }
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityElement(children: .combine)
        }
    }

    // FIXED269: Use the same clock formatting as the detail CSV export.
    private func csvPreviewClock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    private func snapshot() -> Data? {
        guard store.selectedLocationID == pattern.locationID,
              store.selectedPatterns.contains(where: { $0.id == pattern.id && $0 == pattern }),
              validRange else { return nil }
        // Every data mutation advances this generation, including photos, rates and leave.
        // Keep the exact same stale-preview protection without serializing every photo.
        let value = "\(store.selectedLocationID.uuidString)|\(store.pdfRevision)|\(from.timeIntervalSinceReferenceDate)|\(until.timeIntervalSinceReferenceDate)"
        return Data(value.utf8)
    }
    // FIXED265: Use the same registered-shift estimates for preview and result.
    private func estimatedTotal(_ report: ShiftStore.PatternApplicationResult) -> Int {
        report.staffResults.reduce(0) { $0 + $1.estimatedCost }
    }
    private func costDifference(_ actual: Int, expected: Int) -> String {
        let delta = actual - expected
        return delta == 0 ? "¥0" : "\(delta > 0 ? "+" : "−")¥\(abs(delta).formatted())"
    }
    private var validRange: Bool {
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: from)
        let last = calendar.startOfDay(for: until)
        guard first <= last, let days = calendar.dateComponents([.day], from: first, to: last).day else { return false }
        return days < 366
    }
    var body: some View {
        NavigationStack {
            Form {
                Text(pattern.name).font(.headline)
                SchedulePatternTimes(pattern: pattern)
                DatePicker("適用開始", selection: $from, displayedComponents: .date)
                DatePicker("適用終了", selection: $until, in: from..., displayedComponents: .date)
                Text("既存の勤務・承認済み休暇は変更しません。空欄のみ登録します。") .font(.caption).foregroundStyle(.secondary)
                if validRange {
                    let report = store.applyPatternWithReport(pattern, from: from, through: until, previewOnly: true)
                    Section("適用前の確認（データは変更されません）") {
                        LabeledContent("新規登録予定", value: "\(report.added)件")
                        LabeledContent("予定概算人件費", value: "¥\(estimatedTotal(report).formatted())")
                        Text("新規登録予定のシフトのみを集計します。既存シフトや希望休は含みません。")
                            .font(.caption).foregroundStyle(.secondary)
                        LabeledContent("既存シフト保護", value: "\(report.existingShifts)件")
                        LabeledContent("承認済み希望休", value: "\(report.approvedLeave)件")
                        LabeledContent("期間限定予約日", value: "\(report.reservedSeasonal)件")
                        LabeledContent("期間限定パターン重複", value: "\(report.overlappingSeasonal)件")
                        if report.overlappingSeasonal > 0 {
                            Label("期間限定パターンの重複日は登録されません。パターンの期間を確認してください。", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange).font(.caption)
                        }
                        if !report.seasonalConflictDetails.isEmpty {
                            DisclosureGroup("重複の詳細（最大100件）") {
                                ForEach(report.seasonalConflictDetails) { conflict in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("\(conflict.staffName) ・ \(conflict.dateKey)")
                                            .font(.subheadline.weight(.semibold))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text("競合パターン：\(conflict.otherPatternName)")
                                            .font(.caption).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Button {
                                            editConflictingPattern(conflict.otherPatternID, from...until)
                                        } label: {
                                            Label("競合パターンを編集", systemImage: "pencil")
                                                .frame(minHeight: 36)
                                        }
                                        .modifier(AppActionStyle())
                                        .disabled(!store.selectedPatterns.contains(where: { $0.id == conflict.otherPatternID }))
                                    }
                                    .padding(.vertical, 6)
                                }
                                if report.overlappingSeasonal > report.seasonalConflictDetails.count {
                                    Text("残りの競合は表示を省略しています。期間を短くして確認してください。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if let completedReport {
                    Section("適用結果") {
                        LabeledContent("実際に登録", value: "\(completedReport.added)件")
                        LabeledContent("登録分の概算人件費", value: "¥\(estimatedTotal(completedReport).formatted())")
                        if let expectedReport {
                            LabeledContent("確認時の予定人件費", value: "¥\(estimatedTotal(expectedReport).formatted())")
                            LabeledContent("予定との差額", value: costDifference(estimatedTotal(completedReport), expected: estimatedTotal(expectedReport)))
                        }
                        LabeledContent("既存シフト保護", value: "\(completedReport.existingShifts)件")
                        LabeledContent("承認済み希望休", value: "\(completedReport.approvedLeave)件")
                        LabeledContent("期間限定予約日", value: "\(completedReport.reservedSeasonal)件")
                        LabeledContent("期間限定重複", value: "\(completedReport.overlappingSeasonal)件")
                        if let comparisonCSVURL {
                            ShareLink(item: comparisonCSVURL) {
                                Label("スタッフ別比較CSVを共有", systemImage: "square.and.arrow.up")
                            }
                            Text("UTF-8（BOM付き）・Excel対応。登録予定と実際の登録結果を出力します。")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if expectedReport != nil {
                            Label("比較CSVを作成できませんでした。", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if let detailCSVURL {
                            Button {
                                refreshFilteredDetailCSV()
                                detailPreviewFrom = from
                                detailPreviewUntil = until
                                showingDetailCSVPreview = true
                            } label: {
                                Label("勤務日別明細CSVをプレビュー", systemImage: "doc.text.magnifyingglass")
                            }
                            if fullDetailCSVVerification?.matches == true {
                                ShareLink(item: detailCSVURL) {
                                    Label("勤務日別明細CSVを共有", systemImage: "square.and.arrow.up")
                                }
                            } else {
                                Label("CSV照合未完了・不一致のため共有できません", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                            Text("勤務日・区分・時刻・休憩・実働・時給・概算人件費を出力します（UTF-8 BOM付き）。")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Label("明細CSVを作成できませんでした。", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        // FIXED306: Offer a retry from the application result too.
                        if fullDetailCSVVerification?.matches != true {
                            Button {
                                retryFullDetailCSV()
                            } label: {
                                Label("勤務日別明細CSVを再生成・再照合", systemImage: "arrow.clockwise")
                            }
                        }
                        csvRetryHistoryView
                        if let fullCSVRetryMessage {
                            Label(fullCSVRetryMessage, systemImage: fullDetailCSVVerification?.matches == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(fullDetailCSVVerification?.matches == true ? Color.green : Color.orange)
                        }
                        if !completedReport.staffResults.isEmpty {
                            DisclosureGroup("スタッフ別の登録件数（\(completedReport.staffResults.count)名）") {
                                ForEach(completedReport.staffResults) { item in
                                    DisclosureGroup {
                                        // FIXED266: Compare each staff member against the confirmed preview.
                                        if let expectedItem = expectedReport?.staffResults.first(where: { $0.staffID == item.staffID }) {
                                            LabeledContent("登録予定", value: "\(expectedItem.added)件")
                                            LabeledContent("実際の登録", value: "\(item.added)件")
                                            LabeledContent("予定人件費", value: "¥\(expectedItem.estimatedCost.formatted())")
                                            LabeledContent("登録人件費", value: "¥\(item.estimatedCost.formatted())")
                                            LabeledContent("予定との差額", value: costDifference(item.estimatedCost, expected: expectedItem.estimatedCost))
                                            if expectedItem.added != item.added || expectedItem.estimatedCost != item.estimatedCost {
                                                Label("確認時の予定と登録結果が異なります。", systemImage: "exclamationmark.triangle.fill")
                                                    .font(.caption).foregroundStyle(.orange)
                                            }
                                        }
                                        if item.registeredShifts.isEmpty {
                                            Text("登録された勤務日はありません。")
                                                .font(.caption).foregroundStyle(.secondary)
                                        } else {
                                            ForEach(item.registeredShifts) { shift in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    HStack(spacing: 12) {
                                                        Text(shift.dateKey)
                                                            .font(.subheadline.monospacedDigit())
                                                        Spacer(minLength: 8)
                                                        Text(shift.type.rawValue)
                                                            .font(.subheadline.weight(.medium))
                                                    }
                                                    Text(shift.timeLabel)
                                                        .font(.caption.monospacedDigit())
                                                        .foregroundStyle(.secondary)
                                                    Text(shift.breakAndWorkLabel)
                                                        .font(.caption.monospacedDigit())
                                                        .foregroundStyle(.secondary)
                                                    Text("適用時給 ¥\(shift.hourlyWage.formatted()) ・ 概算人件費 ¥\(shift.estimatedCost.formatted())")
                                                        .font(.caption.monospacedDigit())
                                                        .foregroundStyle(.secondary)
                                                }
                                                .accessibilityElement(children: .combine)
                                            }
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.staffName)
                                            Text("概算人件費 ¥\(item.estimatedCost.formatted())")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("\(item.added)件")
                                    }
                                }
                                Text("0件のスタッフも表示します。登録漏れの確認に利用できます。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Label("適用は完了しています。再適用するには画面を閉じて開き直してください。", systemImage: "checkmark.circle")
                            .foregroundStyle(.green).font(.caption)
                    }
                }
                if let applyError {
                    Label(applyError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                Section {
                    Button("この内容で適用対象を確認") {
                        confirmedSnapshot = snapshot()
                        expectedReport = confirmedSnapshot == nil ? nil : store.applyPatternWithReport(pattern, from: from, through: until, previewOnly: true)
                        applyError = confirmedSnapshot == nil
                            ? "ホテルまたはパターンが変更されています。画面を閉じて開き直してください。"
                            : nil
                    }
                    .disabled(!validRange || completedReport != nil)
                    if confirmedSnapshot != nil && completedReport == nil {
                        Label("確認済みです。適用直前に変更がないか再検証します。", systemImage: "checkmark.shield")
                            .foregroundStyle(.green)
                    }
                }
                if !validRange {
                    Label("適用期間は366日以内にしてください。", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("パターン適用")
            .onAppear {
                restoreCSVRetryHistory()
                restoreCSVHistoryFilters()
                if let range = initialRange {
                    from = range.lowerBound
                    until = range.upperBound
                } else {
                    from = Calendar.current.startOfMonth(for: month)
                    until = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: from) ?? from
                }
            }
            .sheet(isPresented: $showingDetailCSVPreview) {
                NavigationStack {
                    Group {
                        if let completedReport {
                            List {
                                Section {
                                    LabeledContent("登録シフト数", value: "\(completedReport.added)件")
                                    LabeledContent("全体の概算人件費", value: "¥\(estimatedTotal(completedReport).formatted())")
                                } header: {
                                    Text("全体集計")
                                } footer: {
                                    Text("今回のパターン適用で登録されたシフトのみの概算です。")
                                }
                                let visibleStaff = previewStaffResults(completedReport)
                                Section {
                                    // FIXED294: Persistent count makes remaining filters obvious after individual removal.
                                    LabeledContent("適用中の検索条件", value: "\(detailPreviewActiveConditions.count)件")
                                    if detailPreviewActiveConditions.isEmpty {
                                        Label("検索条件なし（全件表示）", systemImage: "line.3.horizontal.decrease.circle")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        // FIXED297: Semantic tints distinguish staff (blue), shift (teal), and date (orange)
                                        // in both light and dark appearance; text uses system adaptive colors.
                                        // FIXED296: Each chip has a distinct category icon and a trailing remove icon.
                                        // FIXED295: Horizontal, individually removable chips use less
                                        // vertical space on iPad while keeping 44pt touch targets.
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                let staffName = detailPreviewStaffQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                                                if !staffName.isEmpty {
                                                    Button {
                                                        detailPreviewStaffQuery = ""
                                                    } label: {
                                                        HStack(spacing: 6) {
                                                            Label("スタッフ名：\(staffName)", systemImage: "person.fill")
                                                                .labelStyle(.titleAndIcon)
                                                            Image(systemName: "xmark.circle.fill")
                                                                .foregroundStyle(.secondary)
                                                        }
                                                        .lineLimit(1)
                                                        .padding(.horizontal, 12)
                                                        .frame(minHeight: 44)
                                                    }
                                                    .modifier(AppActionStyle())
                                                    .tint(.blue)
                                                    .accessibilityLabel("スタッフ名：\(staffName) の条件を解除")
                                                }
                                                if let selectedType = detailPreviewShiftType {
                                                    Button {
                                                        detailPreviewShiftType = nil
                                                    } label: {
                                                        HStack(spacing: 6) {
                                                            Label("勤務区分：\(selectedType.rawValue)", systemImage: "clock.fill")
                                                                .labelStyle(.titleAndIcon)
                                                            Image(systemName: "xmark.circle.fill")
                                                                .foregroundStyle(.secondary)
                                                        }
                                                        .lineLimit(1)
                                                        .padding(.horizontal, 12)
                                                        .frame(minHeight: 44)
                                                    }
                                                    .modifier(AppActionStyle())
                                                    .tint(.teal)
                                                    .accessibilityLabel("勤務区分：\(selectedType.rawValue) の条件を解除")
                                                }
                                                if detailPreviewDateFilterEnabled {
                                                    Button {
                                                        detailPreviewDateFilterEnabled = false
                                                    } label: {
                                                        HStack(spacing: 6) {
                                                            Label("勤務日：\(detailPreviewFrom.shiftDateKey) 〜 \(detailPreviewUntil.shiftDateKey)", systemImage: "calendar")
                                                                .labelStyle(.titleAndIcon)
                                                            Image(systemName: "xmark.circle.fill")
                                                                .foregroundStyle(.secondary)
                                                        }
                                                        .lineLimit(1)
                                                        .padding(.horizontal, 12)
                                                        .frame(minHeight: 44)
                                                    }
                                                    .modifier(AppActionStyle())
                                                    .tint(.orange)
                                                    .accessibilityLabel("勤務日の条件を解除")
                                                }
                                            }
                                            .padding(.vertical, 2)
                                        }

                                    }
                                    if !detailPreviewValidRange {
                                        Label("日付範囲が無効です。終了日を開始日以降にしてください。", systemImage: "exclamationmark.triangle")
                                            .foregroundStyle(.red)
                                    }
                                } header: { Text("現在の検索条件") }
                                // FIXED300: Keep filter editing in one compact section instead of
                                // spreading related controls across three sections.
                                Section {
                                    Picker("勤務区分", selection: $detailPreviewShiftType) {
                                        Text("すべて").tag(ShiftType?.none)
                                        ForEach(ShiftType.allCases) { type in
                                            Text(type.rawValue).tag(Optional(type))
                                        }
                                    }
                                    Toggle("勤務日を指定", isOn: $detailPreviewDateFilterEnabled)
                                    if detailPreviewDateFilterEnabled {
                                        DatePicker("開始日", selection: $detailPreviewFrom, displayedComponents: .date)
                                        DatePicker("終了日", selection: $detailPreviewUntil, displayedComponents: .date)
                                        if !detailPreviewValidRange {
                                            Label("終了日は開始日以降にしてください。", systemImage: "exclamationmark.triangle")
                                                .foregroundStyle(.red)
                                        }
                                    }
                                    Button(action: resetDetailPreviewFilters) {
                                        Label("すべての検索条件を解除", systemImage: "arrow.counterclockwise")
                                    }
                                    .disabled(detailPreviewActiveConditions.isEmpty)
                                } header: {
                                    Label("絞り込み条件を編集", systemImage: "line.3.horizontal.decrease.circle")
                                } footer: {
                                    Text("スタッフ名は画面上部の検索欄で指定します。適用中の条件は上のチップから個別に解除できます。")
                                }
                                // FIXED290: Keep a compact live summary visible even when details are collapsed.
                                let exportCount = visibleStaff.reduce(0) { total, staff in
                                    total + previewDetailShifts(for: staff).count
                                }
                                let exportCost = visibleStaff.reduce(0) { total, staff in
                                    total + previewDetailShifts(for: staff).reduce(0) { $0 + $1.estimatedCost }
                                }
                                Section {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("絞り込みCSV出力予定")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("\(exportCount)件・\(visibleStaff.count)名")
                                                .font(.headline)
                                        }
                                        Spacer(minLength: 12)
                                        VStack(alignment: .trailing, spacing: 3) {
                                            Text("概算人件費")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("¥\(exportCost.formatted())")
                                                .font(.headline)
                                                .monospacedDigit()
                                        }
                                    }
                                    .accessibilityElement(children: .combine)
                                    // FIXED299: Observe the criteria, not the count. A different
                                    // filter may return the same number of rows but different costs.
                                    // FIXED301: Compare only effective, user-visible filters.
                                    // An inactive date picker changing must not create a false
                                    // "previous search" comparison; reopening starts fresh.
                                    .onAppear {
                                        previousFilteredExportMetrics = nil
                                        currentFilteredExportMetrics = (visibleStaff.count, exportCount, exportCost)
                                    }
                                    .onChange(of: detailPreviewActiveConditions) { _, _ in
                                        previousFilteredExportMetrics = currentFilteredExportMetrics
                                        currentFilteredExportMetrics = (visibleStaff.count, exportCount, exportCost)
                                    }
                                    if let previous = previousFilteredExportMetrics {
                                        let staffDelta = visibleStaff.count - previous.staff
                                        let shiftDelta = exportCount - previous.shifts
                                        let costDelta = exportCost - previous.cost
                                        VStack(alignment: .leading, spacing: 4) {
                                            Label("勤務件数：\(shiftDelta > 0 ? "+" : "")\(shiftDelta)件（前回\(previous.shifts)件 → 現在\(exportCount)件）", systemImage: shiftDelta > 0 ? "arrow.up.right" : (shiftDelta < 0 ? "arrow.down.right" : "equal"))
                                            Text("スタッフ数：\(staffDelta > 0 ? "+" : "")\(staffDelta)名（前回\(previous.staff)名 → 現在\(visibleStaff.count)名）")
                                            Text("概算人件費：\(costDelta > 0 ? "+" : (costDelta < 0 ? "−" : ""))¥\(abs(costDelta).formatted())（前回¥\(previous.cost.formatted()) → 現在¥\(exportCost.formatted())）")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .accessibilityElement(children: .combine)
                                    }
                                    // FIXED300: Put the primary export action beside the live
                                    // summary; the toolbar menu remains available as before.
                                    if let detailCSVURL {
                                        HStack(spacing: 12) {
                                            if fullDetailCSVVerification?.matches == true {
                                            ShareLink(item: detailCSVURL) {
                                                Label("全件CSV", systemImage: "square.and.arrow.up")
                                            }
                                            .modifier(AppActionStyle())
                                            }
                                            if let filteredDetailCSVURL, exportCount > 0, filteredDetailCSVVerification?.matches == true {
                                                ShareLink(item: filteredDetailCSVURL) {
                                                    Label("絞り込みCSV（\(exportCount)件）", systemImage: "line.3.horizontal.decrease.circle")
                                                }
                                                .modifier(AppActionStyle(prominent: true))
                                            }
                                        }
                                    }
                                    // FIXED304: Show independent verification for the full export.
                                    if let verification = fullDetailCSVVerification {
                                        Label(verification.matches
                                              ? "全件CSV照合済み：\(verification.rows)件・¥\(verification.cost.formatted())"
                                              : "全件CSV照合不一致：共有を停止しました（\(verification.rows)件・¥\(verification.cost.formatted())）",
                                              systemImage: verification.matches ? "checkmark.shield" : "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(verification.matches ? Color.green : Color.orange)
                                    } else {
                                        Label("全件CSV照合未完了：共有できません", systemImage: "exclamationmark.triangle")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                    // FIXED303: Compare the generated file's real rows and cost
                                    // against the preview before allowing filtered sharing.
                                    if let verification = filteredDetailCSVVerification {
                                        Label(verification.matches
                                              ? "CSV照合済み：\(verification.rows)件・¥\(verification.cost.formatted())"
                                              : "CSV照合不一致：共有を停止しました（\(verification.rows)件・¥\(verification.cost.formatted())）",
                                              systemImage: verification.matches ? "checkmark.shield" : "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(verification.matches ? Color.green : Color.orange)
                                    } else if exportCount > 0 {
                                        Label("CSV照合未完了：絞り込みCSVを共有できません", systemImage: "exclamationmark.triangle")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                    // FIXED306: Retry from the preview without dismissing it.
                                    if fullDetailCSVVerification?.matches != true {
                                        Button {
                                            retryFullDetailCSV()
                                        } label: {
                                            Label("全件CSVを再生成・再照合", systemImage: "arrow.clockwise")
                                        }
                                        .modifier(AppActionStyle())
                                    }
                                    if exportCount > 0 && filteredDetailCSVVerification?.matches != true {
                                        Button {
                                            retryFilteredDetailCSV()
                                        } label: {
                                            Label("絞り込みCSVを再生成・再照合", systemImage: "arrow.clockwise")
                                        }
                                        .modifier(AppActionStyle())
                                    }
                                    // FIXED309: Show retry timestamps and outcomes in the preview.
                                    csvRetryHistoryView
                                    // FIXED307: Keep retry outcome visible until the next retry/filter change.
                                    if let fullCSVRetryMessage {
                                        Label(fullCSVRetryMessage, systemImage: fullDetailCSVVerification?.matches == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(fullDetailCSVVerification?.matches == true ? Color.green : Color.orange)
                                    }
                                    if let filteredCSVRetryMessage {
                                        Label(filteredCSVRetryMessage, systemImage: filteredDetailCSVVerification?.matches == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(filteredDetailCSVVerification?.matches == true ? Color.green : Color.orange)
                                    }
                                    // FIXED305: Explain which metric failed and by how much.
                                    let fullExpectedRows = completedReport.staffResults.reduce(0) { $0 + detailCSVShifts(for: $1, shiftType: nil, dateRange: nil).count }
                                    let fullExpectedCost = completedReport.staffResults.reduce(0) { total, staff in
                                        total + detailCSVShifts(for: staff, shiftType: nil, dateRange: nil).reduce(0) { $0 + $1.estimatedCost }
                                    }
                                    csvVerificationDetails(fullDetailCSVVerification, expectedRows: fullExpectedRows, expectedCost: fullExpectedCost, title: "全件CSV")
                                    csvVerificationDetails(filteredDetailCSVVerification, expectedRows: exportCount, expectedCost: exportCost, title: "絞り込みCSV")
                                    // FIXED291: Explicitly warn when the filtered export has no rows.
                                    if exportCount == 0 {
                                        Label("検索条件に一致する勤務が0件です。絞り込みCSVは出力できません。", systemImage: "exclamationmark.triangle.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(.orange)
                                            .accessibilityAddTraits(.isStaticText)
                                    }
                                    DisclosureGroup(isExpanded: $showingCSVExportDetails) {
                                    LabeledContent("絞り込みCSV出力予定件数", value: "\(exportCount)件")
                                    LabeledContent("出力対象スタッフ数", value: "\(visibleStaff.count)名")
                                    LabeledContent("出力対象の概算人件費合計", value: "¥\(exportCost.formatted())")
                                    if let filteredDetailCSVGeneratedAt, filteredDetailCSVURL != nil {
                                        LabeledContent("絞り込みCSV作成日時", value: filteredDetailCSVGeneratedAt.formatted(date: .numeric, time: .standard))
                                    } else {
                                        Text("絞り込みCSVは現在の条件では作成できません。")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    // FIXED282: Compare the complete export against the current filtered selection.
                                    let allStaffCount = completedReport.staffResults.filter { !$0.registeredShifts.isEmpty }.count
                                    let allCost = completedReport.staffResults.reduce(0) { $0 + $1.estimatedCost }
                                    Divider()
                                    Text("全件出力と絞り込み出力の比較")
                                        .font(.subheadline.weight(.semibold))
                                    LabeledContent("対象スタッフ（全件 / 絞り込み）", value: "\(allStaffCount)名 / \(visibleStaff.count)名")
                                    LabeledContent("勤務明細（全件 / 絞り込み）", value: "\(completedReport.added)件 / \(exportCount)件")
                                    LabeledContent("概算人件費（全件 / 絞り込み）", value: "¥\(allCost.formatted()) / ¥\(exportCost.formatted())")
                                    // FIXED283: Show the rows, staff, and estimated cost excluded by the active filters.
                                    // Staff excluded means staff with no matching exported shift.
                                    let excludedStaffCount = max(0, allStaffCount - visibleStaff.count)
                                    let excludedShiftCount = max(0, completedReport.added - exportCount)
                                    let excludedCost = allCost - exportCost
                                    Divider()
                                    Text("絞り込みで除外される内容")
                                        .font(.subheadline.weight(.semibold))
                                    LabeledContent("除外スタッフ数", value: "\(excludedStaffCount)名")
                                    LabeledContent("除外勤務明細", value: "\(excludedShiftCount)件")
                                    LabeledContent("除外概算人件費", value: "¥\(excludedCost.formatted())")
                                    // FIXED284: Use the full export as the denominator; avoid division by zero.
                                    let excludedShiftRate = completedReport.added > 0
                                        ? Double(excludedShiftCount) / Double(completedReport.added) * 100
                                        : 0.0
                                    let excludedCostRate = allCost > 0
                                        ? Double(excludedCost) / Double(allCost) * 100
                                        : 0.0
                                    // FIXED286: Also show the percentage retained for CSV export.
                                    // Derive retained rates from actual selected rows, not rounded excluded rates.
                                    let retainedShiftRate = completedReport.added > 0
                                        ? Double(exportCount) / Double(completedReport.added) * 100
                                        : 0.0
                                    let retainedCostRate = allCost > 0
                                        ? Double(exportCost) / Double(allCost) * 100
                                        : 0.0
                                    Divider()
                                    // FIXED288: Retain one accessible comparison visualization instead of four duplicate progress bars.
                                    Text("出力・除外の割合比較")
                                        .font(.subheadline.weight(.semibold))
                                    // FIXED287: A single stacked bar compares exported (green) and excluded (orange) portions.
                                    // Use the full total as denominator; empty totals show a neutral track.
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text("勤務明細：出力 \(retainedShiftRate.formatted(.number.precision(.fractionLength(1))))% / 除外 \(excludedShiftRate.formatted(.number.precision(.fractionLength(1))))%")
                                            .font(.caption.weight(.semibold))
                                        GeometryReader { geometry in
                                            HStack(spacing: 0) {
                                                Color.green.frame(width: geometry.size.width * min(1, max(0, retainedShiftRate / 100)))
                                                Color.orange.opacity(completedReport.added > 0 ? 1 : 0).frame(maxWidth: .infinity)
                                            }
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(Capsule())
                                        }
                                        .frame(height: 12)
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel("勤務明細の出力と除外の割合")
                                        .accessibilityValue("出力\(retainedShiftRate.formatted(.number.precision(.fractionLength(1))))パーセント、除外\(excludedShiftRate.formatted(.number.precision(.fractionLength(1))))パーセント")
                                        HStack {
                                            Label("出力 \(exportCount)件", systemImage: "circle.fill").foregroundStyle(.green)
                                            Spacer()
                                            Label("除外 \(excludedShiftCount)件", systemImage: "circle.fill").foregroundStyle(.orange)
                                        }
                                        .font(.caption2)
                                    }
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text("概算人件費：出力 \(retainedCostRate.formatted(.number.precision(.fractionLength(1))))% / 除外 \(excludedCostRate.formatted(.number.precision(.fractionLength(1))))%")
                                            .font(.caption.weight(.semibold))
                                        GeometryReader { geometry in
                                            HStack(spacing: 0) {
                                                Color.green.frame(width: geometry.size.width * min(1, max(0, retainedCostRate / 100)))
                                                Color.orange.opacity(allCost > 0 ? 1 : 0).frame(maxWidth: .infinity)
                                            }
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(Capsule())
                                        }
                                        .frame(height: 12)
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel("概算人件費の出力と除外の割合")
                                        .accessibilityValue("出力\(retainedCostRate.formatted(.number.precision(.fractionLength(1))))パーセント、除外\(excludedCostRate.formatted(.number.precision(.fractionLength(1))))パーセント")
                                        HStack {
                                            Label("出力 ¥\(exportCost.formatted())", systemImage: "circle.fill").foregroundStyle(.green)
                                            Spacer()
                                            Label("除外 ¥\(excludedCost.formatted())", systemImage: "circle.fill").foregroundStyle(.orange)
                                        }
                                        .font(.caption2)
                                    }
                                    Text("緑はCSV出力対象、オレンジは除外対象です。全件が0件・0円の場合は0.0%として表示します。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("除外スタッフ数は、今回の出力対象となる勤務が1件も残らないスタッフの人数です。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("全件出力は検索条件の影響を受けません。絞り込み出力は現在の検索条件を反映します。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    } label: {
                                        Label("出力件数・人件費の詳細を確認", systemImage: "chart.bar.xaxis")
                                            .font(.subheadline.weight(.medium))
                                    }
                                } header: { Text("CSV出力前の確認") } footer: {
                                    Text("閉じた状態でも出力予定件数・スタッフ数・概算人件費を確認できます。詳細を開くと全件・除外との比較を表示します。")
                                }
                                Section {
                                    LabeledContent("表示スタッフ数", value: "\(visibleStaff.count) / \(completedReport.staffResults.count)名")
                                    if !detailPreviewStaffQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || detailPreviewShiftType != nil || detailPreviewDateFilterEnabled {
                                        Text("共有時に「全スタッフ」または「絞り込み結果のみ」を選択できます。")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } header: { Text("絞り込み結果") }
                                if visibleStaff.isEmpty {
                                    VStack(spacing: 12) {
                                        ContentUnavailableView(
                                            "該当する勤務がありません",
                                            systemImage: "calendar.badge.exclamationmark",
                                            description: Text("スタッフ名・勤務区分・日付範囲を見直してください。絞り込みCSVの共有はできません。")
                                        )
                                        // FIXED292: Return to all results directly from the empty state.
                                        if !detailPreviewActiveConditions.isEmpty {
                                            Button(action: resetDetailPreviewFilters) {
                                                Label("検索条件を解除して全件表示", systemImage: "arrow.counterclockwise")
                                            }
                                            .modifier(AppActionStyle(prominent: true))
                                            .accessibilityHint("スタッフ名・勤務区分・日付範囲の絞り込みを解除します")
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                ForEach(visibleStaff) { staff in
                                    Section {
                                        LabeledContent("表示件数", value: "\(previewDetailShifts(for: staff).count)件")
                                        LabeledContent("表示分の概算人件費", value: "¥\(previewDetailShifts(for: staff).reduce(0) { $0 + $1.estimatedCost }.formatted())")
                                        ForEach(previewDetailShifts(for: staff)) { shift in
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text("\(shift.dateKey) · \(shift.type.rawValue)")
                                                    .font(.headline)
                                                HStack {
                                                    Text("開始: \(shift.startMinutes.map { csvPreviewClock($0) } ?? "—")")
                                                    Text("終了: \(shift.endMinutes.map { ($0 >= 1440 ? "翌" : "") + csvPreviewClock($0) } ?? "—")")
                                                }
                                                .font(.subheadline.monospacedDigit())
                                                if let start = shift.startMinutes, let end = shift.endMinutes, end > start {
                                                    let duration = end - start
                                                    let rest = min(duration, max(0, shift.breakMinutes ?? (duration > 480 ? 60 : (duration > 360 ? 45 : 0))))
                                                    Text("休憩 \(rest)分 · 概算実働 \(duration - rest)分")
                                                        .font(.caption)
                                                }
                                                Text("時給 ¥\(shift.hourlyWage.formatted()) · 概算人件費 ¥\(shift.estimatedCost.formatted())")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(.vertical, 3)
                                        }
                                    } header: {
                                        Text(staff.staffName)
                                    }
                                }
                            }
                            .searchable(text: $detailPreviewStaffQuery, prompt: "スタッフ名で検索")
                        } else {
                            ContentUnavailableView("明細がありません", systemImage: "doc.text")
                        }
                    }
                    .onChange(of: detailPreviewStaffQuery) { _, _ in refreshFilteredDetailCSV() }
                    .onChange(of: detailPreviewShiftType) { _, _ in refreshFilteredDetailCSV() }
                    .onChange(of: detailPreviewDateFilterEnabled) { _, _ in refreshFilteredDetailCSV() }
                    .onChange(of: detailPreviewFrom) { _, _ in refreshFilteredDetailCSV() }
                    .onChange(of: detailPreviewUntil) { _, _ in refreshFilteredDetailCSV() }
                    .navigationTitle("勤務日別CSVプレビュー")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("閉じる") { showingDetailCSVPreview = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            if let detailCSVURL, let completedReport {
                                Menu {
                                    if fullDetailCSVVerification?.matches == true {
                                        ShareLink(item: detailCSVURL) {
                                            Label("全スタッフを出力", systemImage: "person.3")
                                        }
                                    } else {
                                        Label("全件CSVの照合未完了・不一致のため出力できません", systemImage: "exclamationmark.triangle")
                                    }
                                    if let filteredDetailCSVURL, !previewStaffResults(completedReport).isEmpty, filteredDetailCSVVerification?.matches == true {
                                        ShareLink(item: filteredDetailCSVURL) {
                                            Label("絞り込み結果のみ出力（\(previewStaffResults(completedReport).count)名）", systemImage: "line.3.horizontal.decrease.circle")
                                        }
                                    } else {
                                        Label("絞り込み結果が0件のため出力できません", systemImage: "exclamationmark.triangle")
                                    }
                                } label: {
                                    Label("CSVを共有", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                    }
                }
            }
            .onChange(of: from) { _, _ in confirmedSnapshot = nil; expectedReport = nil; applyError = nil }
            .onChange(of: until) { _, _ in confirmedSnapshot = nil; expectedReport = nil; applyError = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if completedReport != nil {
                        Button("閉じる") { dismiss() }
                    } else {
                        Button("適用") {
                            guard let confirmedSnapshot, let current = snapshot(),
                                  current == confirmedSnapshot, let expectedReport else {
                                self.confirmedSnapshot = nil
                                self.expectedReport = nil
                                applyError = "確認後にシフト・スタッフ・パターン・ホテル・期間のいずれかが変更されました。内容を確認し直してください。"
                                return
                            }
                            let result = apply(from, until)
                            completedReport = result
                            comparisonCSVURL = createComparisonCSV(expected: expectedReport, actual: result)
                            detailCSVURL = createDetailCSV(actual: result)
                            if let url = detailCSVURL {
                                let expectedRows = result.staffResults.reduce(0) { $0 + detailCSVShifts(for: $1, shiftType: nil, dateRange: nil).count }
                                let expectedCost = result.staffResults.reduce(0) { total, staff in
                                    total + detailCSVShifts(for: staff, shiftType: nil, dateRange: nil).reduce(0) { $0 + $1.estimatedCost }
                                }
                                fullDetailCSVVerification = verifyDetailCSVFile(url, expectedRows: expectedRows, expectedCost: expectedCost)
                            } else {
                                fullDetailCSVVerification = nil
                            }
                            refreshFilteredDetailCSV()
                            self.confirmedSnapshot = nil
                            if result.added != expectedReport.added ||
                                result.existingShifts != expectedReport.existingShifts ||
                                result.approvedLeave != expectedReport.approvedLeave ||
                                result.reservedSeasonal != expectedReport.reservedSeasonal ||
                                result.overlappingSeasonal != expectedReport.overlappingSeasonal ||
                                estimatedTotal(result) != estimatedTotal(expectedReport) {
                                applyError = "確認時と実際の適用件数または概算人件費が異なりました。登録結果を確認してください。"
                            } else {
                                applyError = nil
                            }
                        }
                        .disabled(!validRange || confirmedSnapshot == nil)
                    }
                }
            }
        }
    }
}
