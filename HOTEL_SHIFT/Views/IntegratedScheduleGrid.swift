import SwiftUI
import UIKit

// EldiaShift-style week/month grid, backed by the same assignments as the daily timeline.
struct IntegratedScheduleGrid: View {
    @EnvironmentObject private var store: ShiftStore
    @ObservedObject var workspace: ShiftWorkspaceControls
    let month: Date
    @Binding var selectedDay: Date
    let isWeek: Bool
    let edit: (StaffMember, Date) -> Void
    let inspectRequest: (ShiftRequest) -> Void
    let openDay: (Date) -> Void
    private var editing: Bool { workspace.editing }
    private var selecting: Bool { workspace.selecting }
    @State private var scrollLink = ScheduleScrollLink()
    @State private var renderCache = ShiftRenderCache()
    @State private var viewportWidth: CGFloat = 0
    @State private var selected: Set<ScheduleGridKey> = []
    private var department: String { workspace.department }
    @State private var bulkType: ShiftType? = .day
    @State private var pending: PendingBatch?
    @State private var message: String?
    @State private var undoStack: [ScheduleGridChange] = []
    @State private var redoStack: [ScheduleGridChange] = []
    @State private var profileStaff: StaffMember?
    @State private var timeEdit: TimeEdit?
    @State private var minuteStep = 15
    private let calendar = Calendar.current
    private var cellWidth: CGFloat { isWeek ? max(80, (viewportWidth - nameWidth - summaryWidth) / 7) : 74 }
    private var rowHeight: CGFloat { isWeek ? 54 : 64 }
    private var nameWidth: CGFloat { UIDevice.current.userInterfaceIdiom == .phone ? 92 : 138 }
    private var summaryWidth: CGFloat { UIDevice.current.userInterfaceIdiom == .phone ? 52 : 68 }
    private let headerHeight: CGFloat = 36
    private let countHeight: CGFloat = 22
    private let departmentHeight: CGFloat = 20
    private struct PendingBatch {
        let title: String
        let edits: [ScheduleGridEdit]
        let locationID: UUID
        let revision: UInt64
        let allowLeave: Bool
    }
    private struct TimeEdit: Identifiable {
        let staff: StaffMember
        let date: Date
        var id: String { staff.id.uuidString + date.shiftDateKey }
    }
    private var visibleDates: [Date] {
        let start = isWeek ? (calendar.dateInterval(of: .weekOfYear, for: selectedDay)?.start ?? selectedDay)
            : (calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month)
        let count = isWeek ? 7 : (calendar.range(of: .day, in: .month, for: start)?.count ?? 0)
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    private var people: [StaffMember] {
        store.selectedStaff.filter { $0.isActive && (department == "すべて" || $0.department == department) }
            .sorted { ($0.department, $0.name) < ($1.department, $1.name) }
    }
    private struct RenderData {
        let dates: [Date]
        let roster: [StaffMember]
        let groups: [String]
        let shifts: [ScheduleGridKey: ShiftAssignment]
        let requests: [ScheduleGridKey: ShiftRequest]
        let counts: [String: Int]
        let labels: [UUID: String]
        let summaries: [UUID: (days: Int, hours: Double)]
    }
    private struct ContentRevision: Hashable {
        let revision: UInt64; let location: UUID; let dates: [Date]; let selectedDay: Date
        let selected: Set<ScheduleGridKey>; let department: String
        let editing: Bool; let selecting: Bool; let width: CGFloat; let isWeek: Bool
    }
    private var renderData: RenderData {
        let start = isWeek ? (calendar.dateInterval(of: .weekOfYear, for: selectedDay)?.start ?? selectedDay) : calendar.startOfMonth(for: month)
        let key = ShiftRenderKey(revision: store.pdfRevision, location: store.selectedLocationID,
                                 scope: "grid|\(start.timeIntervalSince1970)|\(isWeek)|\(department)")
        return renderCache.value(for: key) {
            let dates = visibleDates, roster = people
            let keys = Set(dates.map(\.shiftDateKey))
            let shifts = Dictionary(store.selectedAssignments(on: keys).map { (ScheduleGridKey(staffID: $0.staffID, dateKey: $0.dateKey), $0) }, uniquingKeysWith: { first, _ in first })
            let requests = Dictionary(store.selectedRequestsUnsorted.filter { keys.contains($0.dateKey) }.map { (ScheduleGridKey(staffID: $0.staffID, dateKey: $0.dateKey), $0) }, uniquingKeysWith: { first, _ in first })
            var counts: [String: Int] = [:], labels: [UUID: String] = [:]
            var summaries: [UUID: (days: Int, hours: Double)] = [:]
            for person in roster {
                let rows = dates.compactMap { shifts[ScheduleGridKey(staffID: person.id, dateKey: $0.shiftDateKey)] }
                labels[person.id] = Array(Set(rows.compactMap(\.patternNameSnapshot))).sorted().joined(separator: "・")
                summaries[person.id] = ScheduleGridSupport.summary(rows)
                for row in rows where DayTimelineMath.span(row) != nil { counts[row.dateKey, default: 0] += 1 }
            }
            return RenderData(dates: dates, roster: roster, groups: Array(Set(roster.map(\.department))).sorted(),
                              shifts: shifts, requests: requests, counts: counts, labels: labels, summaries: summaries)
        }
    }
    var body: some View {
        let snapshot = renderData
        let dates = snapshot.dates, roster = snapshot.roster, groups = snapshot.groups
        let shifts = snapshot.shifts, requests = snapshot.requests
        let contentHeight = CGFloat(groups.count) * departmentHeight + CGFloat(roster.count) * rowHeight
        VStack(spacing: 8) {
            if UIDevice.current.userInterfaceIdiom == .phone {
                Text("日付は左右にスクロールできます").font(.caption).foregroundStyle(.secondary)
            }
            if roster.isEmpty {
                ContentUnavailableView("スタッフがいません", systemImage: "person.2")
            } else {
                GeometryReader { geometry in
                    let rightWidth = max(80, geometry.size.width - nameWidth)
                    VStack(spacing: 0) {
                        // FIXED480: This header is outside the vertical scroll area.
                        HStack(spacing: 0) {
                            VStack(spacing: 0) {
                                Text("スタッフ").font(.system(size: 11, weight: .bold))
                                    .frame(width: nameWidth, height: headerHeight).background(Color.blue.opacity(0.08))
                                Text("勤務人数").font(.system(size: 10))
                                    .frame(width: nameWidth, height: countHeight).background(Color.white)
                            }
                            ScheduleLinkedHeader(link: scrollLink, contentWidth: CGFloat(dates.count) * cellWidth + summaryWidth, height: headerHeight + countHeight) {
                                dateHeader(dates, counts: snapshot.counts)
                            }.frame(width: rightWidth, height: headerHeight + countHeight)
                        }.frame(height: headerHeight + countHeight).background(Color.white).zIndex(2)
                        ScrollView(.vertical) {
                            HStack(alignment: .top, spacing: 0) {
                                leftColumn(roster, groups: groups, labels: snapshot.labels)
                                ScheduleLinkedHorizontalScroll(
                                    contentWidth: CGFloat(dates.count) * cellWidth + summaryWidth,
                                    contentHeight: contentHeight,
                                    resetKey: dates.map(\.shiftDateKey).joined(separator: "|"),
                                    contentRevision: ContentRevision(revision: store.pdfRevision, location: store.selectedLocationID, dates: dates, selectedDay: selectedDay, selected: selected, department: department, editing: editing, selecting: selecting, width: cellWidth, isWeek: isWeek),
                                    link: scrollLink) {
                                        rightGrid(dates, people: roster, groups: groups, shifts: shifts, requests: requests, summaries: snapshot.summaries)
                                    }
                                    .frame(width: rightWidth, height: contentHeight)
                            }
                        }
                    }
                    .onAppear { viewportWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in viewportWidth = width }
                }.frame(minHeight: 220)
            }
        }.padding(.horizontal, 6)
        .safeAreaInset(edge: .bottom, spacing: 4) {
            if editing { selectionBar }
        }
        .onAppear { updateHistoryControls() }
        .onChange(of: undoStack.count) { _, _ in updateHistoryControls() }
        .onChange(of: redoStack.count) { _, _ in updateHistoryControls() }
        .onChange(of: workspace.request) { _, request in
            guard let request else { return }
            switch request.command {
            case .undo: if editing { restore(undo: true) }
            case .redo: if editing { restore(undo: false) }
            case .toggleSelection: if editing { workspace.selecting = true; selected = [] }
            case .copyWeek: if editing && isWeek { prepareCopyWeek() }
            }
        }
        .confirmationDialog("変更内容の確認", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button(pending?.allowLeave == true ? "希望休との重複を承知で適用" : "適用する", role: pending?.allowLeave == true ? .destructive : nil) {
                if let batch = pending { commit(batch) }; pending = nil
            }
            Button("キャンセル", role: .cancel) { pending = nil }
        } message: { Text(pending?.title ?? "") }
        .alert("シフト操作", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
        .sheet(item: $profileStaff) { person in
            ScheduleStaffProfileSheet(staffID: person.id, locationID: person.locationID,
                                      referenceDate: selectedDay).environmentObject(store)
        }
        .sheet(item: $timeEdit) { selection in
            NavigationStack {
                ScrollView {
                    DayShiftTimeEditor(staff: selection.staff, date: selection.date,
                                       assignment: store.assignment(staffID: selection.staff.id, date: selection.date),
                                       hasApprovedLeave: hasLeave(selection.staff.id, date: selection.date), minuteStep: $minuteStep) { start, end, rest, restStart in
                        store.setShiftTimes(staffID: selection.staff.id, date: selection.date, startMinutes: start,
                                            endMinutes: end, breakMinutes: rest, breakStartMinutes: restStart)
                    }.padding()
                }.navigationTitle("時刻・休憩の調整")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { timeEdit = nil } } }
            }.environmentObject(store)
        }
        .onChange(of: editing) { _, enabled in workspace.selecting = enabled; selected = [] }
        .onChange(of: department) { _, _ in selected = []; pending = nil }
        .onChange(of: visibleDates.map(\.shiftDateKey)) { _, _ in resetHistory() }
        .onChange(of: store.selectedLocationID) { _, _ in resetHistory(); workspace.editing = false; workspace.department = "すべて"; timeEdit = nil; profileStaff = nil }
    }
    private func updateHistoryControls() {
        workspace.canUndo = !undoStack.isEmpty
        workspace.canRedo = !redoStack.isEmpty
    }
    private var selectionBar: some View {
        GeometryReader { geometry in
        ScrollView(.horizontal) {
            HStack(spacing: 16.8) {
                Text(selected.isEmpty ? "セルをタップで選択" : "\(selected.count)セル選択").fontWeight(.semibold)
                Menu {
                    ForEach(ShiftType.allCases) { type in Button(type.rawValue) { bulkType = type } }
                    Button("空欄に戻す", role: .destructive) { bulkType = nil }
                } label: { Label(bulkType?.rawValue ?? "空欄", systemImage: "chevron.down") }.disabled(selected.isEmpty)
                Button("時刻・休憩") { openSelectedTime() }.disabled(selected.count != 1)
                Button("コピー") { prepareCopyWeek() }.disabled(selected.isEmpty).help("選択セルを7日後の空欄へコピー")
                Button("選択解除") { selected = []; workspace.selecting = true }.disabled(selected.isEmpty)
                Button("適用") { prepareBulk(bulkType) }.buttonStyle(ScheduleToolbarButtonStyle(prominent: true, scale: 1.4)).disabled(selected.isEmpty)
            }.font(.system(size: 16.8)).buttonStyle(ScheduleToolbarButtonStyle(scale: 1.4))
                .frame(minWidth: max(0, geometry.size.width - 22.4), alignment: .center).padding(11.2)
        }.scrollIndicators(.visible)
        }.frame(height: 64.4)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 16.8).stroke(Color.gray.opacity(0.2)))
        .frame(maxWidth: 1064).padding(.horizontal, 14).padding(.bottom, 5.6)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    private func openSelectedTime() {
        guard let key = selected.first, selected.count == 1,
              let person = people.first(where: { $0.id == key.staffID }),
              let date = Date.keyFormatter.date(from: key.dateKey) else { return }
        timeEdit = TimeEdit(staff: person, date: date)
    }
    private func leftColumn(_ people: [StaffMember], groups: [String], labels: [UUID: String]) -> some View {
        VStack(spacing: 0) {
            ForEach(groups, id: \.self) { group in
                Text(group).font(.caption.bold()).frame(width: nameWidth, height: departmentHeight, alignment: .leading).background(Color.blue.opacity(0.08))
                ForEach(people.filter { $0.department == group }) { person in
                    let label = labels[person.id] ?? ""
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                        Text(label.isEmpty ? "勤務区分／登録時刻" : label)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }.padding(.horizontal, 6).frame(width: nameWidth, height: rowHeight, alignment: .leading)
                        .contentShape(Rectangle()).onTapGesture { profileStaff = person }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("\(person.name)のスタッフ詳細")
                        .overlay(alignment: .bottom) { Divider() }
                }
            }
        }.frame(width: nameWidth)
    }
    private func dateHeader(_ dates: [Date], counts: [String: Int]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(dates, id: \.shiftDateKey) { date in
                    VStack(spacing: 2) {
                        Text(ScheduleGridSupport.dateLabel(date)).font(.caption.bold())
                        Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2)
                    }.foregroundStyle(weekdayColor(date)).frame(width: cellWidth, height: headerHeight)
                        .background(calendar.isDate(date, inSameDayAs: selectedDay) ? Color.yellow.opacity(0.22) : Color.blue.opacity(0.08))
                        .contentShape(Rectangle()).onTapGesture { selectedDay = date }
                }
                Text("勤務／実働").font(.caption2.bold()).frame(width: summaryWidth, height: headerHeight)
            }
            HStack(spacing: 0) {
                ForEach(dates, id: \.shiftDateKey) { date in
                    let count = counts[date.shiftDateKey] ?? 0
                    Text("\(count)人").font(.caption2).frame(width: cellWidth, height: countHeight)
                }
                Color.clear.frame(width: summaryWidth, height: countHeight)
            }
        }.frame(width: CGFloat(dates.count) * cellWidth + summaryWidth)
    }
    private func rightGrid(_ dates: [Date], people: [StaffMember], groups: [String], shifts: [ScheduleGridKey: ShiftAssignment], requests: [ScheduleGridKey: ShiftRequest], summaries: [UUID: (days: Int, hours: Double)]) -> some View {
        VStack(spacing: 0) {
            ForEach(groups, id: \.self) { group in
                Color.blue.opacity(0.08).frame(height: departmentHeight)
                ForEach(people.filter { $0.department == group }) { person in
                    HStack(spacing: 0) {
                        ForEach(dates, id: \.shiftDateKey) { date in
                            let key = ScheduleGridKey(staffID: person.id, dateKey: date.shiftDateKey)
                            scheduleCell(person, date: date, key: key, assignment: shifts[key], request: requests[key])
                        }
                        let summary = summaries[person.id] ?? (days: 0, hours: 0)
                        VStack(spacing: 4) {
                            Text("\(summary.days)日")
                            Text(String(format: "%.1fh", summary.hours))
                        }.font(.caption).monospacedDigit().frame(width: summaryWidth, height: rowHeight)
                    }.overlay(alignment: .bottom) { Divider() }
                }
            }
        }.frame(width: CGFloat(dates.count) * cellWidth + summaryWidth)
    }
    private func scheduleCell(_ person: StaffMember, date: Date, key: ScheduleGridKey, assignment: ShiftAssignment?, request: ShiftRequest?) -> some View {
        let times = ScheduleGridSupport.timeLines(assignment)
        let conflict = request?.status == .approved && !times.isEmpty
        return VStack(spacing: 3) {
            if let assignment {
                Text(assignment.type == .off ? "-" : ScheduleGridSupport.label(assignment))
                    .font(.system(size: isWeek ? 12 : 11, weight: .semibold)).lineLimit(2)
                    .padding(.horizontal, 4).padding(.vertical, 3)
                    .background(shiftBackground(assignment.type), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(shiftForeground(assignment.type))
                if !times.isEmpty {
                    if isWeek {
                        Text(times.joined(separator: "〜")).font(.system(size: 12, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    } else {
                        VStack(spacing: 0) {
                            Text(times[0]); Text("〜" + times[1])
                        }.font(.system(size: 10, weight: .medium)).monospacedDigit().lineLimit(1)
                    }
                }
                if isWeek, !assignment.note.isEmpty { Text(assignment.note).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1) }
            } else { Text("＋").foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 3).frame(width: cellWidth, height: rowHeight)
        .background(selected.contains(key) ? Color.blue.opacity(0.2) : cellBackground(date))
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(selected.contains(key) ? Color.blue : Color.gray.opacity(0.15)))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDay = date
            guard editing else { return }
            workspace.selecting = true
            if selected.contains(key) { selected.remove(key) } else { selected.insert(key) }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 1) {
                if selected.contains(key) { Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.blue).padding(2) }
            if let request {
                Button { inspectRequest(request) } label: {
                    Circle().fill(request.status == .approved ? Color.green : (request.status == .pending ? Color.orange : Color.gray)).frame(width: 8, height: 8).padding(3)
                }.buttonStyle(.plain).accessibilityLabel("\(request.status.rawValue)の希望休を表示")
            }
        }
        }
        .overlay(alignment: .bottomLeading) {
            if conflict { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(.orange).padding(2).accessibilityLabel("承認済み希望休と勤務が重複") }
        }
        .contextMenu {
            Button("日シフトを開く") { openDay(date) }
            if editing {
                Button("勤務区分・メモ") { edit(person, date) }
                Button("時刻・休憩") { timeEdit = TimeEdit(staff: person, date: date) }
            }
        }
        .frame(width: cellWidth, height: rowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(person.name)、\(date.formatted(date: .abbreviated, time: .omitted))、\(assignment.map { ScheduleGridSupport.label($0) } ?? "未設定")、\(times.joined(separator: "から"))")
    }
    private func weekdayColor(_ date: Date) -> Color {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? .red : (weekday == 7 ? .blue : .primary)
    }
    private func cellBackground(_ date: Date) -> Color {
        if calendar.isDate(date, inSameDayAs: selectedDay) { return Color.yellow.opacity(0.1) }
        return [1,7].contains(calendar.component(.weekday, from: date)) ? Color.gray.opacity(0.07) : Color.white
    }
    private func hasLeave(_ staffID: UUID, date: Date) -> Bool {
        store.hasApprovedLeave(staffID: staffID, dateKey: date.shiftDateKey)
    }
    private func prepareBulk(_ type: ShiftType?) {
        let peopleByID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        var edits: [ScheduleGridEdit] = []
        for key in selected {
            guard let person = peopleByID[key.staffID], let date = Date.keyFormatter.date(from: key.dateKey) else { continue }
            let before = store.assignment(staffID: key.staffID, date: date)
            let after = type.map { shiftType in ScheduleGridSupport.replacing(before, type: shiftType, staff: person, dateKey: key.dateKey, locationID: store.selectedLocationID, preset: store.selectedBasicPatterns.first(where: { $0.basicShiftType == shiftType })) }
            if before != after { edits.append(ScheduleGridEdit(key: key, before: before, after: after)) }
        }
        guard !edits.isEmpty else { message = "変更するセルがありません。"; return }
        let leave = edits.contains { edit in
            guard DayTimelineMath.span(edit.after) != nil, let date = Date.keyFormatter.date(from: edit.key.dateKey) else { return false }
            return hasLeave(edit.key.staffID, date: date)
        }
        pending = PendingBatch(title: "\(edits.count)セルを\(type?.rawValue ?? "空欄")に変更します。" + (leave ? "承認済みの希望休との重複を含みます。" : ""), edits: edits, locationID: store.selectedLocationID, revision: store.pdfRevision, allowLeave: leave)
    }
    private func prepareCopyWeek() {
        var edits: [ScheduleGridEdit] = []
        var occupied = 0, leave = 0
        for person in people {
            for date in visibleDates {
                let sourceKey = ScheduleGridKey(staffID: person.id, dateKey: date.shiftDateKey)
                if selecting && !selected.isEmpty && !selected.contains(sourceKey) { continue }
                guard let current = store.assignment(staffID: person.id, date: date), let target = calendar.date(byAdding: .day, value: 7, to: date) else { continue }
                if store.assignment(staffID: person.id, date: target) != nil { occupied += 1; continue }
                if DayTimelineMath.span(current) != nil && hasLeave(person.id, date: target) { leave += 1; continue }
                var next = current
                next.id = UUID(); next.dateKey = target.shiftDateKey; next.hourlyWageSnapshot = person.hourlyWage
                edits.append(ScheduleGridEdit(key: ScheduleGridKey(staffID: person.id, dateKey: target.shiftDateKey), before: nil, after: next))
            }
        }
        guard !edits.isEmpty else { message = "コピー対象がありません。登録済み\(occupied)件、希望休\(leave)件を除外しました。"; return }
        pending = PendingBatch(title: "対象シフトを7日後の空欄へ\(edits.count)件コピーします。登録済み\(occupied)件と承認済み希望休\(leave)件は上書きしません。", edits: edits, locationID: store.selectedLocationID, revision: store.pdfRevision, allowLeave: false)
    }
    private func commit(_ batch: PendingBatch) {
        do {
            if let change = try store.applyScheduleGrid(batch.edits, locationID: batch.locationID, revision: batch.revision, allowLeave: batch.allowLeave) {
                undoStack.append(change); if undoStack.count > 30 { undoStack.removeFirst() }; redoStack = []
            }
            selected = []
        } catch { message = error.localizedDescription }
    }
    private func restore(undo: Bool) {
        guard let change = undo ? undoStack.last : redoStack.last else { return }
        do {
            try store.restoreScheduleGrid(change, undo: undo)
            if undo { undoStack.removeLast(); redoStack.append(change) } else { redoStack.removeLast(); undoStack.append(change) }
        } catch { message = error.localizedDescription }
    }
    private func resetHistory() { selected = []; pending = nil; undoStack = []; redoStack = []; scrollLink.reset() }
}

// Time preview directly below pattern names in the manager, editor and apply sheet.
struct SchedulePatternTimes: View {
    let pattern: ShiftPattern
    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(pattern.weekdays.enumerated()), id: \.offset) { index, type in
                    let times = ScheduleGridSupport.patternTimeLines(pattern, type: type)
                    VStack(spacing: 3) {
                        Text(["日", "月", "火", "水", "木", "金", "土"][index % 7]).font(.caption2).foregroundStyle(.secondary)
                        Text(type == .off ? "-" : type.rawValue).font(.system(size: 10, weight: .semibold)).foregroundStyle(shiftForeground(type))
                        if !times.isEmpty {
                            Text(times[0]); Text("〜" + times[1])
                        }
                    }.font(.system(size: 10)).monospacedDigit().lineLimit(1)
                        .frame(width: 62, height: 72).background(shiftBackground(type), in: RoundedRectangle(cornerRadius: 2))
                }
            }
        }
    }
}
