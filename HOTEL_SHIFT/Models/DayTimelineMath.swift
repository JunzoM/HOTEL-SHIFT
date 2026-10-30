import Foundation

// Adapted from EldiaShift TimelineMath for this app's minute-based assignments.
enum DayTimelineMath {
    struct Span: Equatable, Sendable { var start: Int; var end: Int }
    enum Mode { case move, start, end }
    static func span(_ assignment: ShiftAssignment?) -> Span? {
        guard let assignment else { return nil }
        let defaults: Span
        switch assignment.type {
        case .early: defaults = Span(start: 360, end: 900)
        case .day: defaults = Span(start: 540, end: 1080)
        case .late: defaults = Span(start: 780, end: 1320)
        case .night: defaults = Span(start: 1260, end: 1980)
        default: return nil
        }
        let start = assignment.customStartMinutes ?? defaults.start
        let end = assignment.customEndMinutes ?? defaults.end
        guard end > start else { return nil }
        return Span(start: start, end: end)
    }
    static func snap(_ minutes: Double, step: Int) -> Int {
        Int((minutes / Double(max(1, step))).rounded()) * max(1, step)
    }
    static func changed(_ span: Span, mode: Mode, delta: Int, step: Int) -> Span {
        let step = max(1, step)
        guard delta != 0 else { return span }
        switch mode {
        case .move:
            let length = span.end - span.start
            let start = min(max(0, span.start + delta), min(1440 - step, 2879 - length))
            return Span(start: start, end: start + length)
        case .start:
            return Span(start: max(0, min(span.start + delta, span.end - step, 1440 - step)), end: span.end)
        case .end:
            return Span(start: span.start, end: max(span.start + step, min(span.end + delta, 2879, span.start + max(1440, span.end - span.start))))
        }
    }
    static func newSpan(at minutes: Int, step: Int) -> Span? {
        let start = max(0, snap(Double(minutes), step: step))
        guard start < 1440 else { return nil }
        return Span(start: start, end: min(start + 480, 2879))
    }
    static func headcount(_ spans: [Span], hour: Int) -> Int {
        spans.filter { $0.start < (hour + 1) * 60 && $0.end > hour * 60 }.count
    }
    static func label(_ minutes: Int) -> String {
        let clock = String(format: "%d:%02d", (minutes / 60) % 24, minutes % 60)
        return minutes >= 1440 ? "翌" + clock : clock
    }
}

struct DayShiftChange {
    let locationID: UUID
    let staffID: UUID
    let dateKey: String
    let before: ShiftAssignment?
    let after: ShiftAssignment
}

enum DayShiftEditError: LocalizedError {
    case changed, unavailable, leave, storage, invalid
    var errorDescription: String? {
        switch self {
        case .changed: return "シフトや店舗が変更されました。最新の内容を確認して再操作してください。"
        case .unavailable: return "この店舗で有効なスタッフを選択してください。"
        case .leave: return "承認済みの希望休があります。内容を確認してください。"
        case .storage: return "データ保存が保護されています。保存に関する警告を確認してください。"
        case .invalid: return "勤務時刻の範囲を確認してください。"
        }
    }
}
