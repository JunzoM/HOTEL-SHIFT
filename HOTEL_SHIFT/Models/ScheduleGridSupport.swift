import Foundation

struct ScheduleGridKey: Hashable {
    let staffID: UUID
    let dateKey: String
}
struct ScheduleGridEdit {
    let key: ScheduleGridKey
    let before: ShiftAssignment?
    let after: ShiftAssignment?
}
struct ScheduleGridChange {
    let locationID: UUID
    let edits: [ScheduleGridEdit]
}
enum ScheduleGridSupport {
    static func dateLabel(_ date: Date, calendar: Calendar = .current) -> String {
        "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
    }
    static func label(_ assignment: ShiftAssignment) -> String {
        let name = assignment.patternNameSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? assignment.type.rawValue : name
    }
    static func timeLines(_ assignment: ShiftAssignment?) -> [String] {
        guard let span = DayTimelineMath.span(assignment) else { return [] }
        return [DayTimelineMath.label(span.start), DayTimelineMath.label(span.end)]
    }
    static func patternTimeLines(_ pattern: ShiftPattern, type: ShiftType) -> [String] {
        timeLines(ShiftAssignment(staffID: pattern.staffID ?? pattern.id, dateKey: "", type: type,
                                 customStartMinutes: pattern.customStartMinutes,
                                 customEndMinutes: pattern.customEndMinutes))
    }
    static func summary(_ assignments: [ShiftAssignment]) -> (days: Int, hours: Double) {
        let working = assignments.filter { DayTimelineMath.span($0) != nil }
        return (working.count, working.reduce(0) { $0 + ShiftLaborEstimate.paidHours($1) })
    }
    static func replacing(_ current: ShiftAssignment?, type: ShiftType, staff: StaffMember, dateKey: String, locationID: UUID, preset: ShiftPattern? = nil) -> ShiftAssignment {
        var next = current ?? ShiftAssignment(staffID: staff.id, dateKey: dateKey, type: type, locationID: locationID, hourlyWageSnapshot: staff.hourlyWage)
        if next.type != type {
            next.customStartMinutes = nil; next.customEndMinutes = nil
            next.customBreakMinutes = nil; next.customBreakStartMinutes = nil
            next.patternNameSnapshot = nil
        }
        if current == nil || current?.type != type {
            next.customStartMinutes = preset?.customStartMinutes
            next.customEndMinutes = preset?.customEndMinutes
            next.customBreakMinutes = preset?.customBreakMinutes
            next.customBreakStartMinutes = preset?.customBreakStartMinutes
        }
        next.type = type
        if next.hourlyWageSnapshot == nil { next.hourlyWageSnapshot = staff.hourlyWage }
        return next
    }
}
