import Foundation

func shift(_ type: ShiftType, _ start: Int? = nil, _ end: Int? = nil, _ rest: Int? = nil, _ restStart: Int? = nil) -> ShiftAssignment {
    ShiftAssignment(staffID: UUID(), dateKey: "2026-10-24", type: type, customStartMinutes: start, customEndMinutes: end, customBreakMinutes: rest, customBreakStartMinutes: restStart)
}
func check(_ actual: Double, _ expected: Double, _ label: String) {
    precondition(abs(actual - expected) < 0.00001, "\(label): expected \(expected), got \(actual)")
}
@main struct VerifyFixed191 {
 static func main() {
    let day = ShiftLaborEstimate.breakdown(shift(.day, 540, 1260, 60, 1080))
    check(day.paid, 11, "day paid")
    check(day.overtime, 3, "day overtime")
    check(day.night, 0, "day night")
    let night = ShiftLaborEstimate.breakdown(shift(.night, 1260, 1980, 60, 1560))
    check(night.paid, 11, "night paid")
    check(night.overtime, 3, "night overtime")
    check(night.night, 6, "night premium with break")
    let overlap = shift(.night, 1260, 1980, 60, 1560)
    precondition(ShiftLaborEstimate.cost(overlap, hourlyWage: 1200) == 15900)
    let boundary = ShiftLaborEstimate.breakdown(shift(.late, 1260, 1380, 0))
    check(boundary.night, 1, "22:00 boundary")
    let zero = ShiftLaborEstimate.breakdown(shift(.day, 540, 540, 0))
    check(zero.paid, 0, "zero duration")
    print("FIXED191: 11 assertions passed")
 }
}
