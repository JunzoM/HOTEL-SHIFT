import Foundation

func require(_ ok: @autoclosure () -> Bool, _ label: String) {
    guard ok() else { fatalError("FAIL: \(label)") }
    print("PASS: \(label)")
}
func cal(_ zone: String) -> Calendar {
    var result = Calendar(identifier: .gregorian)
    result.timeZone = TimeZone(identifier: zone)!
    return result
}
func date(_ c: Calendar, _ y: Int, _ m: Int, _ d: Int, _ hour: Int = 12) -> Date {
    c.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
}
func check(_ zone: String, _ preset: String, _ now: (Int,Int,Int,Int), _ first: (Int,Int,Int), _ last: (Int,Int,Int)) {
    let c = cal(zone)
    let r = CSVHistoryDateRange.forPreset(preset, now: date(c, now.0, now.1, now.2, now.3), calendar: c)!
    let expectedStart = date(c, first.0, first.1, first.2, 0)
    let expectedEnd = date(c, last.0, last.1, last.2, 0)
    require(r.start == expectedStart && r.end == expectedEnd, "\(zone): \(preset) \(now)")
}
// DST starts March 8, 2026 in New York; ends November 1.
check("America/New_York", "過去7日間", (2026,3,10,12), (2026,3,4), (2026,3,10))
check("America/New_York", "過去30日間", (2026,3,15,12), (2026,2,14), (2026,3,15))
check("America/New_York", "過去7日間", (2026,11,3,12), (2026,10,28), (2026,11,3))
check("America/New_York", "先月", (2026,11,2,12), (2026,10,1), (2026,10,31))
check("Europe/Berlin", "過去7日間", (2026,3,30,12), (2026,3,24), (2026,3,30))
check("Europe/Berlin", "過去30日間", (2026,10,27,12), (2026,9,28), (2026,10,27))
check("Asia/Tokyo", "過去7日間", (2026,1,2,12), (2025,12,27), (2026,1,2))
check("Asia/Tokyo", "先月", (2024,3,1,12), (2024,2,1), (2024,2,29))
check("Pacific/Auckland", "過去7日間", (2026,4,6,12), (2026,3,31), (2026,4,6))
check("Pacific/Auckland", "今月", (2026,10,1,12), (2026,10,1), (2026,10,1))
// During repeated 01:30 at fall-back, startOfDay must remain stable.
let ny = cal("America/New_York")
let repeatedDay = date(ny, 2026, 11, 1, 1)
let result = CSVHistoryDateRange.forPreset("今日", now: repeatedDay, calendar: ny)!
require(result.start == date(ny, 2026, 11, 1, 0), "repeated local hour retains calendar day")
print("FIXED324: 11 timezone/DST tests passed")
