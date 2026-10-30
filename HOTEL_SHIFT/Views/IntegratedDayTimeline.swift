import SwiftUI
import UIKit

// Daily bar workflow adapted from EldiaShift DayTimelineView; uses HOTEL_SHIFT storage.
struct IntegratedDayTimeline: View {
    @EnvironmentObject private var store: ShiftStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var workspace: ShiftWorkspaceControls
    let day: Date
    @Binding var minuteStep: Int
    private var isEditing: Bool { workspace.editing }
    private var department: String { workspace.department }
    @State private var renderCache = ShiftRenderCache()
    @State private var drag: BarDrag?
    @State private var profileStaff: StaffMember?
    @State private var editing: StaffMember?
    @State private var timeEditing: StaffMember?
    @State private var pending: PendingEdit?
    @State private var error: String?
    @State private var undoStack: [DayShiftChange] = []
    @State private var redoStack: [DayShiftChange] = []

    private struct BarDrag {
        let staffID: UUID
        let mode: DayTimelineMath.Mode
        let initial: DayTimelineMath.Span
        let expected: ShiftAssignment?
        let locationID: UUID
        var live: DayTimelineMath.Span
    }
    private struct PendingEdit {
        let staffID: UUID
        let date: Date
        let span: DayTimelineMath.Span
        let locationID: UUID
        let expected: ShiftAssignment?
    }
    private var roster: [StaffMember] {
        store.selectedStaff.filter { $0.isActive && (department == "すべて" || $0.department == department) }
            .sorted { ($0.department, $0.name) < ($1.department, $1.name) }
    }
    private var assignments: [UUID: ShiftAssignment] {
        Dictionary(store.selectedAssignments(on: [day.shiftDateKey]).map { ($0.staffID, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private struct RenderData { let people: [StaffMember]; let shifts: [UUID: ShiftAssignment] }
    private var renderData: RenderData {
        let key = ShiftRenderKey(revision: store.pdfRevision, location: store.selectedLocationID, scope: "day|\(day.shiftDateKey)|\(department)")
        return renderCache.value(for: key) { RenderData(people: roster, shifts: assignments) }
    }
    var body: some View {
        let snapshot = renderData
        let people = snapshot.people
        let shifts = snapshot.shifts
        let spans = people.compactMap { DayTimelineMath.span(shifts[$0.id]) }
        let firstMinute = min(300, (spans.map(\.start).min() ?? 300) / 60 * 60)
        let lastMinute = max(2040, Int(ceil(Double(spans.map(\.end).max() ?? 2040) / 60)) * 60)
        let groups = Array(Set(people.map(\.department))).sorted()
        VStack(spacing: 8) {
            GeometryReader { geometry in
                if geometry.size.width < 600 || dynamicTypeSize.isAccessibilitySize {
                    mobileDayList(people: people, shifts: shifts, groups: groups)
                } else {
                let nameWidth: CGFloat = geometry.size.width < 600 ? 90 : 120
                let trackWidth = max(100, geometry.size.width - nameWidth - 4)
                let perMinute = trackWidth / CGFloat(lastMinute - firstMinute)
                VStack(spacing: 0) {
                    hourHeader(nameWidth: nameWidth, trackWidth: trackWidth, first: firstMinute, last: lastMinute)
                    countRow("勤務帯人数", scope: "all", spans: spans, nameWidth: nameWidth, trackWidth: trackWidth, first: firstMinute, last: lastMinute)
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            if people.isEmpty { ContentUnavailableView("スタッフがいません", systemImage: "person.2", description: Text("スタッフ管理で勤務可能なスタッフを登録してください。")) }
                            ForEach(groups, id: \.self) { group in
                                let members = people.filter { $0.department == group }
                                let groupSpans = members.compactMap { DayTimelineMath.span(shifts[$0.id]) }
                                countRow(group, scope: "department:" + group, spans: groupSpans, nameWidth: nameWidth, trackWidth: trackWidth, first: firstMinute, last: lastMinute)
                                    .background(Color.gray.opacity(0.08))
                                ForEach(members) { person in
                                    staffRow(person, assignment: shifts[person.id], nameWidth: nameWidth,
                                             trackWidth: trackWidth, first: firstMinute, last: lastMinute, perMinute: perMinute)
                                }
                            }
                        }
                    }
                }
                }
            }.frame(minHeight: 280)

        }
        .padding(.horizontal, 6)
        .onAppear { updateHistoryControls() }
        .onChange(of: undoStack.count) { _, _ in updateHistoryControls() }
        .onChange(of: redoStack.count) { _, _ in updateHistoryControls() }
        .onChange(of: workspace.request) { _, request in
            guard isEditing, let request else { return }
            switch request.command {
            case .undo: restore(undo: true)
            case .redo: restore(undo: false)
            case .toggleSelection, .copyWeek: break
            }
        }
        .sheet(item: $profileStaff) { person in
            ScheduleStaffProfileSheet(staffID: person.id, locationID: person.locationID,
                                      referenceDate: day).environmentObject(store)
        }
        .sheet(item: $editing) { person in ShiftEditSheet(staff: person, date: day).environmentObject(store) }
        .sheet(item: $timeEditing) { person in
            NavigationStack {
                ScrollView {
                    DayShiftTimeEditor(staff: person, date: day, assignment: store.assignment(staffID: person.id, date: day),
                                       hasApprovedLeave: hasLeave(person.id), minuteStep: $minuteStep) { start, end, rest, restStart in
                        store.setShiftTimes(staffID: person.id, date: day, startMinutes: start, endMinutes: end,
                                            breakMinutes: rest, breakStartMinutes: restStart)
                    }.padding()
                }
                .navigationTitle("時刻・休憩の調整")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { timeEditing = nil } } }
            }.environmentObject(store)
        }
        .confirmationDialog("承認済みの希望休があります", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("希望休との重複を承知で保存", role: .destructive) {
                if let edit = pending { commit(edit, allowLeave: true) }; pending = nil
            }
            Button("キャンセル", role: .cancel) { pending = nil }
        } message: { Text("勤務を登録すると承認済みの希望休と重複します。") }
        .alert("変更できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onChange(of: isEditing) { _, _ in drag = nil }
        .onChange(of: minuteStep) { _, _ in drag = nil }
        .onChange(of: day) { _, _ in resetHistory() }
        .onChange(of: store.selectedLocationID) { _, _ in
            resetHistory(); workspace.department = "すべて"
            profileStaff = nil; editing = nil; timeEditing = nil; pending = nil
        }
    }

    private func mobileDayList(people: [StaffMember], shifts: [UUID: ShiftAssignment], groups: [String]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(isEditing ? "勤務区分や時刻をボタンから編集できます" : "「編集する」で勤務を変更できます")
                    .font(.subheadline).foregroundStyle(.secondary)
                if people.isEmpty {
                    ContentUnavailableView("スタッフがいません", systemImage: "person.2", description: Text("勤務可能なスタッフと部署の絞り込みを確認してください。"))
                }
                ForEach(groups, id: \.self) { group in
                    Text(group).font(.headline)
                    ForEach(people.filter { $0.department == group }) { person in
                        let assignment = shifts[person.id]
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 12) {
                                Button { profileStaff = person } label: {
                                    VStack(spacing: 6) {
                                        if let data = person.photoData {
                                            AsyncStaffPortrait(data: data).frame(width: 52, height: 52).clipShape(Circle())
                                        } else { Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).foregroundStyle(.secondary) }
                                        Text(person.name).font(.subheadline.bold()).multilineTextAlignment(.center)
                                    }.frame(width: 92).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityHint("スタッフ詳細を開きます")
                                VStack(alignment: .leading, spacing: 8) {
                                    if let assignment {
                                        Text(assignment.type.rawValue).font(.headline)
                                        if let span = DayTimelineMath.span(assignment) {
                                            Text("\(DayTimelineMath.label(span.start))〜\(DayTimelineMath.label(span.end))")
                                                .font(.subheadline).monospacedDigit()
                                        }
                                    } else { Text("勤務未登録").foregroundStyle(.secondary) }
                                    if hasLeave(person.id) {
                                        Label("承認済みの希望休", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if isEditing {
                                ViewThatFits(in: .horizontal) {
                                    HStack { mobileEditButtons(person) }
                                    VStack(alignment: .leading) { mobileEditButtons(person) }
                                }
                            }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(UIDevice.current.userInterfaceIdiom == .phone ? Color(.secondarySystemBackground) : Color.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15)))
                    }
                }
            }.padding(.vertical, 8)
        }
    }
    @ViewBuilder private func mobileEditButtons(_ person: StaffMember) -> some View {
        Button("勤務区分・メモ") { editing = person }.frame(minHeight: 44).modifier(AppActionStyle())
        Button("時刻・休憩") { timeEditing = person }.frame(minHeight: 44).modifier(AppActionStyle())
    }

    private func updateHistoryControls() {
        workspace.canUndo = !undoStack.isEmpty
        workspace.canRedo = !redoStack.isEmpty
    }
    private func hourHeader(nameWidth: CGFloat, trackWidth: CGFloat, first: Int, last: Int) -> some View {
        HStack(spacing: 0) {
            Text("スタッフ").font(.caption.bold()).frame(width: nameWidth, alignment: .leading)
            ZStack(alignment: .topLeading) {
                ForEach(Array(stride(from: first, through: last, by: trackWidth < 450 ? 240 : 120)), id: \.self) { minute in
                    Text(DayTimelineMath.label(minute)).font(.system(size: 9)).monospacedDigit()
                        .position(x: max(15, min(trackWidth - 15, CGFloat(minute - first) / CGFloat(last - first) * trackWidth)), y: 12)
                }
            }.frame(width: trackWidth, height: 26)
        }
    }
    private func countRow(_ label: String, scope: String, spans: [DayTimelineMath.Span], nameWidth: CGFloat, trackWidth: CGFloat, first: Int, last: Int) -> some View {
        let hours = Array(first / 60 ..< last / 60)
        let key = ShiftRenderKey(revision: store.pdfRevision, location: store.selectedLocationID, scope: "headcounts|\(day.shiftDateKey)|\(department)|\(scope)|\(first)|\(last)")
        let counts: [Int] = renderCache.value(for: key) { hours.map { DayTimelineMath.headcount(spans, hour: $0) } }
        return HStack(spacing: 0) {
            Text(label).font(.caption2.bold()).lineLimit(2).frame(width: nameWidth, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(hours, id: \.self) { hour in
                    let count = counts[hour - first / 60]
                    Text(count == 0 ? "" : "\(count)").font(.system(size: 9, weight: .semibold)).minimumScaleFactor(0.6)
                        .frame(width: trackWidth / CGFloat(hours.count), height: 24)
                        .background(Color.blue.opacity(min(0.4, Double(count) * 0.07)))
                        .accessibilityLabel("\(DayTimelineMath.label(hour * 60))、\(count)人")
                }
            }
        }.overlay(alignment: .bottom) { Divider() }
    }
    private func staffRow(_ person: StaffMember, assignment: ShiftAssignment?, nameWidth: CGFloat, trackWidth: CGFloat,
                          first: Int, last: Int, perMinute: CGFloat) -> some View {
        let span = drag?.staffID == person.id ? drag?.live : DayTimelineMath.span(assignment)
        return HStack(spacing: 0) {
            Button { profileStaff = person } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name).font(.caption.weight(.semibold)).lineLimit(2)
                    if hasLeave(person.id) { Label("希望休", systemImage: "checkmark.circle").font(.system(size: 9)).foregroundStyle(.orange) }
                }.frame(width: nameWidth - 6, height: 50, alignment: .leading)
            }.buttonStyle(.plain).accessibilityLabel("\(person.name)のスタッフ詳細")
            ZStack(alignment: .leading) {
                grid(first: first, last: last, trackWidth: trackWidth)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        guard isEditing, assignment == nil else { return }
                        let minute = first + DayTimelineMath.snap(Double(value.location.x / perMinute), step: minuteStep)
                        if let span = DayTimelineMath.newSpan(at: minute, step: minuteStep) { requestSave(person.id, span: span, expected: nil) }
                    })
                if let span {
                    shiftBar(person, assignment: assignment, span: span, first: first, perMinute: perMinute)
                } else if let assignment {
                    Text(assignment.type == .off ? "-" : assignment.type.rawValue)
                        .font(.caption.bold()).padding(.horizontal, 12)
                        .onTapGesture { if isEditing { editing = person } }
                }
            }.frame(width: trackWidth, height: 50).clipped()
        }.overlay(alignment: .bottom) { Divider() }
    }
    private func grid(first: Int, last: Int, trackWidth: CGFloat) -> some View {
        Canvas { context, size in
            for minute in stride(from: first, through: last, by: 60) {
                let x = CGFloat(minute - first) / CGFloat(last - first) * trackWidth
                var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.gray.opacity(minute == 1440 ? 0.8 : 0.22)), lineWidth: minute == 1440 ? 1.5 : 0.5)
            }
        }
    }
    private func shiftBar(_ person: StaffMember, assignment: ShiftAssignment?, span: DayTimelineMath.Span,
                          first: Int, perMinute: CGFloat) -> some View {
        let width = max(8, CGFloat(span.end - span.start) * perMinute)
        let handleWidth = min(20, width / 3)
        return ZStack {
            RoundedRectangle(cornerRadius: 6).fill(hasLeave(person.id) ? Color.orange : Color.blue)
            Text("\(DayTimelineMath.label(span.start))〜\(DayTimelineMath.label(span.end))")
                .font(.caption2.bold()).monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, isEditing ? handleWidth : 3)
            if isEditing {
                HStack(spacing: 0) {
                    handle(person, assignment: assignment, mode: .start, span: span, perMinute: perMinute, width: handleWidth)
                    Spacer(minLength: 0)
                    handle(person, assignment: assignment, mode: .end, span: span, perMinute: perMinute, width: handleWidth)
                }
            }
        }
        .frame(width: width, height: 34)
        .contentShape(Rectangle())
        .gesture(barGesture(person, assignment: assignment, mode: .move, span: span, perMinute: perMinute), including: isEditing ? .all : .subviews)
        .onTapGesture { if isEditing { timeEditing = person } }
        .contextMenu {
            Button("スタッフ詳細") { profileStaff = person }
            if isEditing {
                Button("勤務区分・メモ") { editing = person }
                Button("時刻・休憩") { timeEditing = person }
            }
        }
        .offset(x: CGFloat(span.start - first) * perMinute)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(person.name)、\(DayTimelineMath.label(span.start))から\(DayTimelineMath.label(span.end))")
        .accessibilityHint("編集時はダブルタップで時刻・休憩を調整できます")
        .accessibilityAdjustableAction { direction in
            guard isEditing else { return }
            let updated = DayTimelineMath.changed(span, mode: .move, delta: direction == .increment ? minuteStep : -minuteStep, step: minuteStep)
            requestSave(person.id, span: updated, expected: assignment)
        }
    }
    private func handle(_ person: StaffMember, assignment: ShiftAssignment?, mode: DayTimelineMath.Mode,
                        span: DayTimelineMath.Span, perMinute: CGFloat, width: CGFloat) -> some View {
        Capsule().fill(.white.opacity(0.9)).frame(width: 3, height: 18)
            .frame(width: width, height: 34).contentShape(Rectangle())
            .highPriorityGesture(barGesture(person, assignment: assignment, mode: mode, span: span, perMinute: perMinute))
    }
    private func barGesture(_ person: StaffMember, assignment: ShiftAssignment?, mode: DayTimelineMath.Mode,
                            span: DayTimelineMath.Span, perMinute: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard isEditing else { return }
                var state = drag ?? BarDrag(staffID: person.id, mode: mode, initial: span, expected: assignment,
                                            locationID: store.selectedLocationID, live: span)
                guard state.staffID == person.id else { return }
                let delta = DayTimelineMath.snap(Double(value.translation.width / perMinute), step: minuteStep)
                let live = DayTimelineMath.changed(state.initial, mode: state.mode, delta: delta, step: minuteStep)
                guard drag == nil || state.live != live else { return }
                state.live = live
                drag = state
            }
            .onEnded { _ in
                guard isEditing, let state = drag, state.staffID == person.id else { drag = nil; return }
                drag = nil
                guard state.live != state.initial else { return }
                let edit = PendingEdit(staffID: state.staffID, date: day, span: state.live,
                                       locationID: state.locationID, expected: state.expected)
                submit(edit)
            }
    }
    private func hasLeave(_ staffID: UUID) -> Bool {
        store.hasApprovedLeave(staffID: staffID, dateKey: day.shiftDateKey)
    }
    private func requestSave(_ staffID: UUID, span: DayTimelineMath.Span, expected: ShiftAssignment?) {
        submit(PendingEdit(staffID: staffID, date: day, span: span, locationID: store.selectedLocationID, expected: expected))
    }
    private func submit(_ edit: PendingEdit) {
        if hasLeave(edit.staffID) { pending = edit } else { commit(edit) }
    }
    private func commit(_ edit: PendingEdit, allowLeave: Bool = false) {
        do {
            if let change = try store.applyDayTimeline(staffID: edit.staffID, date: edit.date, span: edit.span,
                                                      locationID: edit.locationID, expected: edit.expected, allowLeave: allowLeave) {
                undoStack.append(change); if undoStack.count > 50 { undoStack.removeFirst() }; redoStack = []
            }
        } catch { self.error = error.localizedDescription }
    }
    private func restore(undo: Bool) {
        guard let change = undo ? undoStack.last : redoStack.last else { return }
        do {
            try store.restoreDayTimeline(change, undo: undo)
            if undo { undoStack.removeLast(); redoStack.append(change) }
            else { redoStack.removeLast(); undoStack.append(change) }
        } catch { self.error = error.localizedDescription }
    }
    private func resetHistory() { drag = nil; pending = nil; profileStaff = nil; editing = nil; timeEditing = nil; undoStack = []; redoStack = [] }
}
