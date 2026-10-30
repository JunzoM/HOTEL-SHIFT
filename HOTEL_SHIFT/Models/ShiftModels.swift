import Foundation

enum ShiftType: String, CaseIterable, Codable, Identifiable, Sendable {
    case early = "早番", day = "日勤", late = "遅番", night = "夜勤", afterNight = "明け", off = "休み", paidLeave = "有給"
    var id: String { rawValue }
    var start: String {
        switch self { case .early: return "6:00"; case .day: return "9:00"; case .late: return "13:00"; case .night: return "21:00"; default: return "—" }
    }
    var end: String {
        switch self { case .early: return "15:00"; case .day: return "18:00"; case .late: return "22:00"; case .night: return "翌9:00"; default: return "—" }
    }
}

struct StaffMember: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var department: String
    var employment: String
    var hourlyWage: Int
    var isActive: Bool = true
    var locationID: UUID? = nil
    var photoData: Data? = nil
    // FIXED484: Optional employment-date records preserve older backups.
    var joinDate: String? = nil
    var leaveDate: String? = nil
}

struct ShiftAssignment: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var staffID: UUID
    var dateKey: String
    var type: ShiftType
    var note: String = ""
    var locationID: UUID? = nil
    var customStartMinutes: Int? = nil
    var customEndMinutes: Int? = nil
    var customBreakMinutes: Int? = nil
    var customBreakStartMinutes: Int? = nil
    // FIXED228: Optional for compatibility with older JSON backups.
    var hourlyWageSnapshot: Int? = nil
    // FIXED478: Optional provenance; older backups decode without this label.
    var patternNameSnapshot: String? = nil
}

// Planning estimate only. Daily overtime and night premiums are included; weekly overtime, statutory holidays and monthly thresholds are not.
enum ShiftLaborEstimate {
    static func breakdown(_ shift: ShiftAssignment) -> (paid: Double, overtime: Double, night: Double) {
        let defaults: (Int, Int)
        switch shift.type {
        case .early: defaults = (360, 900)
        case .day: defaults = (540, 1080)
        case .late: defaults = (780, 1320)
        case .night: defaults = (1260, 1980)
        default: return (0, 0, 0)
        }
        let start = shift.customStartMinutes ?? defaults.0
        let end = shift.customEndMinutes ?? defaults.1
        guard end > start else { return (0, 0, 0) }
        let duration = end - start
        let breakLength = min(duration, max(0, shift.customBreakMinutes ?? (duration > 480 ? 60 : (duration > 360 ? 45 : 0))))
        let breakStart = min(max(start, shift.customBreakStartMinutes ?? (start + (duration - breakLength) / 2)), end - breakLength)
        // Compute from contiguous paid intervals instead of iterating every minute.
        // Night intervals repeat at 22:00–05:00 across midnight.
        func nightMinutes(_ from: Int, _ to: Int) -> Int {
            guard to > from else { return 0 }
            var total = 0
            for day in -1...2 {
                let midnight = day * 1440
                let earlyStart = midnight
                let earlyEnd = midnight + 300
                let lateStart = midnight + 1320
                let lateEnd = midnight + 1440
                total += max(0, min(to, earlyEnd) - max(from, earlyStart))
                total += max(0, min(to, lateEnd) - max(from, lateStart))
            }
            return total
        }
        let segments = [(start, breakStart), (breakStart + breakLength, end)]
        var paidMinutes = 0
        var overtimeMinutes = 0
        var nightPaidMinutes = 0
        for (segmentStart, segmentEnd) in segments where segmentEnd > segmentStart {
            let length = segmentEnd - segmentStart
            let regularRemaining = max(0, 480 - paidMinutes)
            overtimeMinutes += max(0, length - regularRemaining)
            nightPaidMinutes += nightMinutes(segmentStart, segmentEnd)
            paidMinutes += length
        }
        return (Double(paidMinutes) / 60, Double(overtimeMinutes) / 60, Double(nightPaidMinutes) / 60)
    }
    static func paidHours(_ shift: ShiftAssignment) -> Double { breakdown(shift).paid }
    static func cost(_ shift: ShiftAssignment, hourlyWage: Int) -> Int {
        let b = breakdown(shift)
        return Int(ceil(Double(shift.hourlyWageSnapshot ?? hourlyWage) * (b.paid + 0.25 * b.overtime + 0.25 * b.night)))
    }
}

struct HotelLocation: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    // Optional facility profile fields keep older local backups compatible.
    var address: String? = nil
    var phone: String? = nil
    var roomCount: Int? = nil
    var floorCount: Int? = nil
    var photoData: Data? = nil
}

enum ShiftRequestStatus: String, Codable, CaseIterable, Identifiable {
    case pending = "申請中", approved = "承認", rejected = "却下"
    var id: String { rawValue }
}

struct ShiftRequest: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var staffID: UUID
    var dateKey: String
    var reason: String
    var status: ShiftRequestStatus = .pending
    var createdAt: Date = Date()
    // Updated whenever the request status changes; optional for older saved files.
    var updatedAt: Date? = nil
    var locationID: UUID
}


struct RequestTransferPacket: Codable {
    var formatVersion: Int = 1
    var facilityName: String
    var requests: [RequestTransferItem]
}

struct RequestTransferItem: Codable {
    var id: UUID
    var staffID: UUID
    var staffName: String
    var dateKey: String
    var reason: String
    var status: ShiftRequestStatus
    var createdAt: Date
    // Optional keeps compatibility with transfer files exported by older versions.
    var updatedAt: Date? = nil
}

enum ShiftPatternScope: String, Codable, CaseIterable, Identifiable {
    case everyone = "全従業員", individual = "個人", seasonal = "期間限定"
    var id: String { rawValue }
}
struct ShiftPattern: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var scope: ShiftPatternScope
    var locationID: UUID
    var staffID: UUID? = nil
    var basicShiftType: ShiftType? = nil
    var weekdays: [ShiftType] = Array(repeating: .off, count: 7)
    var validFrom: Date? = nil
    var validUntil: Date? = nil
    // Optional fields preserve decoding of FIXED87 backups.
    var customStartMinutes: Int? = nil
    var customEndMinutes: Int? = nil
    var customBreakMinutes: Int? = nil
    var customBreakStartMinutes: Int? = nil
}
// Standard presets are visible even before the first custom save; no migration writes.
extension ShiftPattern {
    static func basicDefaults(locationID: UUID) -> [ShiftPattern] {
        let types: [ShiftType] = [.early, .day, .late, .night]
        let starts = [360, 540, 780, 1260], ends = [900, 1080, 1320, 1980]
        return types.enumerated().map { index, type in
            var bytes = locationID.uuid
            bytes.15 ^= UInt8(index + 1)
            var pattern = ShiftPattern(id: UUID(uuid: bytes), name: type.rawValue, scope: .everyone, locationID: locationID)
            pattern.basicShiftType = type
            pattern.weekdays = Array(repeating: type, count: 7)
            pattern.customStartMinutes = starts[index]
            pattern.customEndMinutes = ends[index]
            pattern.customBreakMinutes = 60
            pattern.customBreakStartMinutes = starts[index] + (ends[index] - starts[index] - 60) / 2
            return pattern
        }
    }
}
// FIXED207: Staff-specific reusable time slots; optional in ShiftData for old backups.
struct PersonalWorkTime: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var staffID: UUID
    var locationID: UUID
    var name: String
    var startMinutes: Int = 540
    var endMinutes: Int = 1080
    var breakMinutes: Int = 60
}
// FIXED229: Historical audit entries; previous backups decode without this optional field.
struct StaffWageChange: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var staffID: UUID
    var locationID: UUID
    var changedAt: Date
    var previousHourlyWage: Int
    var newHourlyWage: Int
}

struct ShiftData: Codable {
    var locations: [HotelLocation]
    var staff: [StaffMember]
    var wageChanges: [StaffWageChange]? = []
    var assignments: [ShiftAssignment]
    // Optional so backups created by earlier versions still decode.
    var requests: [ShiftRequest]? = []
    var patterns: [ShiftPattern]? = []
    var personalWorkTimes: [PersonalWorkTime]? = []
}

extension Date {
    var shiftDateKey: String { Date.keyFormatter.string(from: self) }
    static let keyFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let japaneseMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()
    var japaneseMonth: String { Date.japaneseMonthFormatter.string(from: self) }
}

// Calendar-date records use the same local yyyy-MM-dd convention as assignments.
enum StaffProfileValidation {
    static func normalized(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
    static func validDates(join: String?, leave: String?) -> Bool {
        let join = normalized(join), leave = normalized(leave)
        for value in [join, leave].compactMap({ $0 }) {
            guard value.count == 10, let date = Date.keyFormatter.date(from: value), date.shiftDateKey == value else { return false }
        }
        if let join, let leave, join > leave { return false }
        return true
    }
}

// Adapted from EldiaShift LeaveRequestInbox / OffRequestParser.
enum RequestInboxTools {
    struct Fields { var name: String; var dates: String; var reason: String }
    static func fields(_ text: String) -> Fields? {
        var values: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            for key in ["名前", "休みたい日", "理由"] {
                for separator in ["：", ":"] where line.hasPrefix(key + separator) {
                    values[key] = String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        guard let name = values["名前"], !name.isEmpty, let dates = values["休みたい日"], !dates.isEmpty else { return nil }
        return Fields(name: name, dates: dates, reason: values["理由"] ?? "")
    }
    static func normalize(_ value: String) -> String {
        (value.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? value).components(separatedBy: .whitespacesAndNewlines).joined()
    }
    static func detect(_ text: String, staff: [StaffMember]) -> UUID? {
        let body = normalize(text)
        let matches = staff.filter { normalize($0.name).count >= 2 && body.contains(normalize($0.name)) }
        let longest = matches.map { normalize($0.name).count }.max() ?? 0
        let best = matches.filter { normalize($0.name).count == longest }
        if best.count == 1 { return best[0].id }
        if !matches.isEmpty { return nil }
        let partial = staff.filter { person in
            person.name.split(whereSeparator: { $0.isWhitespace }).contains { $0.count >= 2 && body.contains(normalize(String($0))) }
        }
        return partial.count == 1 ? partial[0].id : nil
    }
    static func dates(_ text: String, month: Date) -> [String] {
        let cal = Calendar(identifier: .gregorian)
        let baseYear = cal.component(.year, from: month), baseMonth = cal.component(.month, from: month)
        var s = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        for (a,b) in [("〜","~"),("～","~"),("−","-"),("―","-"),("から","~")] { s = s.replacingOccurrences(of:a,with:b) }
        s = s.replacingOccurrences(of: #"\d{1,2}:\d{2}"#, with: " ", options: .regularExpression)
        let re = try! NSRegularExpression(pattern: #"(?<![\d/])(?:(\d{4})\s*(?:年|/)\s*)?(?:(\d{1,2})\s*(?:/|月)\s*)?(\d{1,2})(?!\d)\s*日?"#)
        let ns = s as NSString
        var year = baseYear, mo = baseMonth, result = Set<String>()
        var previous: (date: Date, end: Int)?
        for match in re.matches(in:s,range:NSRange(location:0,length:ns.length)) {
            func number(_ i:Int) -> Int? { match.range(at:i).location == NSNotFound ? nil : Int(ns.substring(with:match.range(at:i))) }
            if let m = number(2) {
                guard (1...12).contains(m) else { previous = nil; continue }
                mo = m
                if let y = number(1) { year = y }
                else { year = [baseYear-1,baseYear,baseYear+1].min { abs(($0*12+m)-(baseYear*12+baseMonth)) < abs(($1*12+m)-(baseYear*12+baseMonth)) }! }
            }
            guard let d = number(3), (1900...2200).contains(year),
                  let date = cal.date(from:DateComponents(year:year,month:mo,day:d)),
                  cal.component(.month,from:date) == mo, cal.component(.day,from:date) == d, d > 0 else { previous = nil; continue }
            if let p = previous {
                let between = ns.substring(with:NSRange(location:p.end,length:match.range.location-p.end)).trimmingCharacters(in:.whitespaces)
                if ["~","-"].contains(between), date > p.date,
                   let span = cal.dateComponents([.day],from:p.date,to:date).day, span <= 62 {
                    for offset in 1..<max(1,span) { if let day = cal.date(byAdding:.day,value:offset,to:p.date) { result.insert(day.shiftDateKey) } }
                }
            }
            result.insert(date.shiftDateKey)
            previous = (date,match.range.location+match.range.length)
        }
        return result.sorted()
    }
    static func reply(staff: [StaffMember], requests: [ShiftRequest]) -> String {
        let groups = Dictionary(grouping:requests.filter { $0.status != .pending },by:\.staffID)
        return groups.keys.sorted { $0.uuidString < $1.uuidString }.map { id in
            let rows = groups[id]!, name = staff.first { $0.id == id }?.name ?? "スタッフ"
            var lines = ["\(name)さん", "希望休の申請の結果です。"]
            for status in [ShiftRequestStatus.approved,.rejected] {
                let days = Set(rows.filter { $0.status == status }.map(\.dateKey)).sorted().joined(separator:"、")
                if !days.isEmpty { lines.append((status == .approved ? "○ お休みOK：" : "× 難しい日：") + days) }
            }
            if rows.contains(where:{ $0.status == .rejected }) { lines.append("難しい日は、ほかの日にできないか相談させてください。") }
            return lines.joined(separator:"\n")
        }.joined(separator:"\n\n")
    }
}

struct RequestWorkflowError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// FIXED490: Compatible with the user's existing mobile form and EldiaShift links.
struct IncomingLeaveLink: Identifiable, Equatable {
    let id: String
    let name: String
    let storeName: String
    let dateKeys: [String]
    let reason: String
    var firstMonth: Date { Date.keyFormatter.date(from: dateKeys[0]) ?? Date() }
    var formText: String {
        (["【希望休の申請】", "名前：\(name)"] + (storeName.isEmpty ? [] : ["店舗：\(storeName)"]) + ["休みたい日：" + dateKeys.joined(separator: "、")] + (reason.isEmpty ? [] : ["理由：\(reason)"])).joined(separator: "\n")
    }
    private struct Payload: Decodable { var v: Int; var n: String; var s: String?; var d: [String]; var r: String? }
    static func decode(_ url: URL) -> IncomingLeaveLink? {
        let web = url.scheme?.lowercased() == "https" && url.host?.lowercased() == "facility-manager-phi.vercel.app" && ["/hotel-shift/r", "/hotel-shift/r/"].contains(url.path) && url.port == nil
        let app = ["hotelshift", "eldiashift"].contains(url.scheme?.lowercased() ?? "") && url.host?.lowercased() == "request" && ["", "/"].contains(url.path)
        guard web || app, url.user == nil, url.password == nil, let token = url.fragment,
              !token.isEmpty, token.count <= 4000,
              token.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
        var b64 = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let bytes = Data(base64Encoded: b64), let p = try? JSONDecoder().decode(Payload.self, from: bytes), p.v == 1 else { return nil }
        let name = p.n.trimmingCharacters(in: .whitespacesAndNewlines)
        let storeName = (p.s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = (p.r ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40, storeName.count <= 80, reason.count <= 200,
              !p.d.isEmpty, p.d.count <= 62, p.d.allSatisfy(validDay) else { return nil }
        return IncomingLeaveLink(id: token, name: name, storeName: storeName, dateKeys: Array(Set(p.d)).sorted(), reason: reason)
    }
    static func validDay(_ key: String) -> Bool {
        guard key.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil,
              let year = Int(key.prefix(4)), (1900...2200).contains(year),
              let date = Date.keyFormatter.date(from: key) else { return false }
        return date.shiftDateKey == key
    }
    static func fromText(_ text: String) -> IncomingLeaveLink? {
        guard text.utf8.count <= 20000 else { return nil }
        let candidates = text.components(separatedBy: .whitespacesAndNewlines)
        for value in candidates {
            if let url = URL(string: value.trimmingCharacters(in: CharacterSet(charactersIn: "<>（）「」\""))), let link = decode(url) { return link }
        }
        return nil
    }
    static func storeField(_ text: String) -> String {
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            for separator in ["：", ":"] where line.hasPrefix("店舗" + separator) {
                return String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }
    static func matchingLocations(_ name: String, locations: [HotelLocation]) -> [HotelLocation] {
        guard !name.isEmpty else { return [] }
        let normalized = RequestInboxTools.normalize(name)
        let exact = locations.filter { RequestInboxTools.normalize($0.name) == normalized }
        if !exact.isEmpty { return exact }
        // The existing mobile form caps its store label at 30 characters.
        return locations.filter { RequestInboxTools.normalize(String($0.name.prefix(30))) == normalized }
    }
}

enum RequestFormLink {
    static let page = "https://facility-manager-phi.vercel.app/hotel-shift/request"
    static func url(storeName: String) -> URL {
        var parts = URLComponents(string: page)!
        let name = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { parts.queryItems = [URLQueryItem(name: "s", value: name)] }
        return parts.url!
    }
}

// Deterministic demo IDs make re-adding the same four stores detectable.
enum SampleShiftData {
    private static func id(_ shop: Int, _ item: Int) -> UUID {
        UUID(uuidString: String(format: "D5030000-0000-4000-8000-%04X%08X", shop, item))!
    }
    static var locationIDs: Set<UUID> { Set((1...4).map { id($0, 0) }) }
    static func make(anchor: Date = Date(), calendar: Calendar = .current) -> ShiftData {
        let cities = ["東京", "大阪", "名古屋", "福岡"]
        let surnames = ["佐藤","鈴木","高橋","田中","伊藤","渡辺","山本","中村","小林","加藤","吉田","山田","佐々木","山口","松本","井上","木村","林","清水","山崎","森","池田","橋本","阿部","石川"]
        let givenNames = ["太郎","花子","大輔","美咲","健太","さくら","翔太","結衣","直樹","彩香","悠人","陽菜","拓也","真由","誠","愛","涼介","優子","亮","恵","和也","千尋","駿","葵","明"]
        let departments = ["フロント","レストラン","キッチン","ハウスキーピング","清掃"]
        let rotation: [ShiftType] = [.early, .day, .late, .off, .night, .afterNight, .off]
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor))!
        let end = calendar.date(byAdding: .month, value: 2, to: month)!
        let dayCount = calendar.dateComponents([.day], from: month, to: end).day!
        var result = ShiftData(locations: [], staff: [], assignments: [])
        for shop in 1...4 {
            let location = HotelLocation(id: id(shop, 0), name: "サンプル\(cities[shop - 1])店", roomCount: 80 + shop * 20, floorCount: 5 + shop)
            result.locations.append(location)
            result.patterns?.append(contentsOf: ShiftPattern.basicDefaults(locationID: location.id))
            var weekly = ShiftPattern(id: id(shop, 1000), name: "サンプル平日日勤", scope: .everyone, locationID: location.id)
            weekly.weekdays = [.day, .day, .day, .day, .day, .off, .off]
            result.patterns?.append(weekly)
            for index in 0..<25 {
                let person = StaffMember(id: id(shop, 100 + index), name: "\(surnames[index]) \(givenNames[(index + (shop - 1) * 6) % 25])", department: departments[index / 5], employment: ["正社員","パート","アルバイト"][index % 3], hourlyWage: 1200 + (index % 5) * 50, locationID: location.id)
                result.staff.append(person)
                result.personalWorkTimes?.append(PersonalWorkTime(id: id(shop, 2000 + index), staffID: person.id, locationID: location.id, name: "サンプル通常勤務", startMinutes: 540, endMinutes: 1080, breakMinutes: 60))
                let approvedDay = (index + shop) % dayCount
                let pendingDay = (approvedDay + 14) % dayCount
                for offset in 0..<dayCount {
                    let date = calendar.date(byAdding: .day, value: offset, to: month)!
                    let type: ShiftType = offset == approvedDay ? .off : rotation[(offset + index + shop) % rotation.count]
                    result.assignments.append(ShiftAssignment(id: id(shop, 100000 + index * 100 + offset), staffID: person.id, dateKey: date.shiftDateKey, type: type, note: "サンプル", locationID: location.id, hourlyWageSnapshot: person.hourlyWage))
                }
                for (number, day, status) in [(0, approvedDay, ShiftRequestStatus.approved), (1, pendingDay, .pending)] {
                    let date = calendar.date(byAdding: .day, value: day, to: month)!
                    result.requests?.append(ShiftRequest(id: id(shop, 10000 + index * 10 + number), staffID: person.id, dateKey: date.shiftDateKey, reason: "サンプル希望休", status: status, createdAt: month, locationID: location.id))
                }
            }
        }
        return result
    }
}

// Per-location budget values; retain the former shared value as a migration fallback.
enum LaborBudgetSettings {
    static func value(for locationID: UUID, data: Data, legacy: Int) -> Int {
        let budgets = (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
        return max(0, budgets[locationID.uuidString] ?? legacy)
    }
    static func updating(_ value: Int, for locationID: UUID, data: Data) -> Data? {
        guard value >= 0 else { return nil }
        var budgets = (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
        budgets[locationID.uuidString] = value
        return try? JSONEncoder().encode(budgets)
    }
    static func parse(_ draft: String) -> Int? {
        var text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("¥") || text.hasPrefix("￥") { text.removeFirst() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "，", with: ",")
        guard !text.isEmpty, text.utf8.count <= 128 else { return nil }
        let groups = text.split(separator: ",", omittingEmptySubsequences: false)
        if groups.count > 1 {
            guard let first = groups.first, (1...3).contains(first.count),
                  groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        var digits = ""
        for character in text where character != "," {
            guard character.unicodeScalars.count == 1,
                  let scalar = character.unicodeScalars.first,
                  CharacterSet.decimalDigits.contains(scalar),
                  let digit = character.wholeNumberValue, (0...9).contains(digit) else { return nil }
            digits.append(String(digit))
        }
        return Int(digits)
    }
}

// Leave room for the generated date/UUID suffix under filesystem byte limits.
enum ExportFilename {
    static func component(_ raw: String) -> String {
        let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:?%*|\"<>"))
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: invalid).filter { !$0.isEmpty }.joined(separator: "_")
        var result = ""
        var bytes = 0
        for character in cleaned {
            let size = String(character).utf8.count
            guard bytes + size <= 120 else { break }
            result.append(character)
            bytes += size
        }
        return result.isEmpty || result == "." || result == ".." ? "施設" : result
    }
}

// Check bounds before subtracting/adding imported minute values.
enum ShiftMinuteValidation {
    static func valid(_ assignment: ShiftAssignment) -> Bool {
        guard valid(start: assignment.customStartMinutes, end: assignment.customEndMinutes,
                    rest: assignment.customBreakMinutes, restStart: assignment.customBreakStartMinutes) else { return false }
        let defaults: (Int, Int)
        switch assignment.type {
        case .early: defaults = (360, 900)
        case .day: defaults = (540, 1080)
        case .late: defaults = (780, 1320)
        case .night: defaults = (1260, 1980)
        default: return true
        }
        return valid(start: assignment.customStartMinutes ?? defaults.0,
                     end: assignment.customEndMinutes ?? defaults.1,
                     rest: assignment.customBreakMinutes, restStart: assignment.customBreakStartMinutes)
    }
    static func valid(start: Int?, end: Int?, rest: Int?, restStart: Int?) -> Bool {
        if let start, !(0...1439).contains(start) { return false }
        if let end, !(1...2879).contains(end) { return false }
        if let rest, !(0...2879).contains(rest) { return false }
        if let restStart, !(0...2879).contains(restStart) { return false }
        if let start, let end {
            guard end > start else { return false }
            if let rest {
                guard rest <= end - start else { return false }
                if let restStart, !(start...(end - rest)).contains(restStart) { return false }
            }
        }
        return true
    }
}

// Date/label work is per visible day/week, not per historical assignment.
enum WeeklyLaborSummary {
    struct Week {
        let start: Date
        let label: String
    }
    struct Key: Hashable {
        let staffID: UUID
        let weekStart: Date
    }
    struct Alert: Equatable {
        let name: String
        let week: String
        let hours: Double
    }
    static func weeks(overlapping month: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> [String: Week] {
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: month),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: month),
              let lastWeek = calendar.dateInterval(of: .weekOfYear, for: monthEnd) else { return [:] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M/d"
        var result: [String: Week] = [:]
        var start = firstWeek.start
        while start < lastWeek.end {
            guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: start),
                  let next = calendar.date(byAdding: .day, value: 7, to: start), next > start else { break }
            if start < monthEnd && weekEnd >= month {
                let week = Week(start: start, label: formatter.string(from: start) + "〜" + formatter.string(from: weekEnd))
                for offset in 0..<7 {
                    if let day = calendar.date(byAdding: .day, value: offset, to: start) { result[day.shiftDateKey] = week }
                }
            }
            start = next
        }
        return result
    }
    static func alerts(assignments: [ShiftAssignment], staff: [StaffMember], weeks: [String: Week]) -> [Alert] {
        let names = Dictionary(staff.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var totals: [Key: Double] = [:]
        var labels: [Date: String] = [:]
        for row in assignments {
            guard let week = weeks[row.dateKey], names[row.staffID] != nil else { continue }
            let key = Key(staffID: row.staffID, weekStart: week.start)
            totals[key, default: 0] += ShiftLaborEstimate.paidHours(row)
            labels[week.start] = week.label
        }
        return totals.compactMap { key, hours in
            guard hours > 40, let name = names[key.staffID], let label = labels[key.weekStart] else { return nil }
            return Alert(name: name, week: label, hours: hours)
        }.sorted { $0.hours > $1.hours }
    }
}
