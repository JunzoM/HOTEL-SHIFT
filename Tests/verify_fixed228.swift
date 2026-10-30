import Foundation

// FIXED228 regression checks (compile alongside Models/ShiftModels.swift).
@main struct VerifyFixed228 {
    static func main() throws {
        let staff = UUID()
        let original = ShiftAssignment(staffID: staff, dateKey: "2026-10-01", type: .day)
        let oldJSON = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(ShiftAssignment.self, from: oldJSON)
        precondition(restored.hourlyWageSnapshot == nil)
        var frozen = restored
        frozen.hourlyWageSnapshot = 1200
        precondition(ShiftLaborEstimate.cost(frozen, hourlyWage: 1500) == ShiftLaborEstimate.cost(frozen, hourlyWage: 1200))
        let saved = try JSONEncoder().encode(frozen)
        let roundtrip = try JSONDecoder().decode(ShiftAssignment.self, from: saved)
        precondition(roundtrip.hourlyWageSnapshot == 1200)
        print("FIXED228 snapshot and legacy JSON checks passed")
    }
}
