import Foundation

func assertDate(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fatalError("FAIL: \(name)") }
    print("PASS: \(name)")
}
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
}
func verify(_ preset: String, _ now: Date, _ start: Date, _ end: Date, _ label: String) {
    let result = CSVHistoryDateRange.forPreset(preset, now: now, calendar: calendar)
    assertDate(result?.start == start && result?.end == end, label)
}
verify("今日", day(2026, 1, 1), day(2026, 1, 1), day(2026, 1, 1), "today at new year")
verify("過去7日間", day(2026, 1, 1), day(2025, 12, 26), day(2026, 1, 1), "seven days across year")
verify("過去30日間", day(2026, 3, 1), day(2026, 1, 31), day(2026, 3, 1), "30 days across short February")
verify("今月", day(2026, 12, 31), day(2026, 12, 1), day(2026, 12, 31), "current month at year end")
verify("先月", day(2026, 1, 1), day(2025, 12, 1), day(2025, 12, 31), "previous month across year")
verify("先月", day(2024, 3, 31), day(2024, 2, 1), day(2024, 2, 29), "leap February")
verify("先月", day(2025, 3, 1), day(2025, 2, 1), day(2025, 2, 28), "non-leap February")
verify("今月", day(2024, 2, 29), day(2024, 2, 1), day(2024, 2, 29), "current month leap day")
verify("過去30日間", day(2024, 3, 1), day(2024, 2, 1), day(2024, 3, 1), "30 days leap February")
verify("過去7日間", day(2026, 5, 1), day(2026, 4, 25), day(2026, 5, 1), "seven days across month")
assertDate(CSVHistoryDateRange.forPreset("invalid", now: day(2026, 1, 1), calendar: calendar) == nil, "unknown preset rejected")
print("FIXED323: 11 date boundary tests passed")
