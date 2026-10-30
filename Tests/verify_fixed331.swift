import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    precondition(condition(), "FAILED: \(name)")
    print("PASS: \(name)")
}
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
let start = CSVHistoryFilterPreferences.dateForDayKey("2024-02-29", calendar: calendar)!
let end = CSVHistoryFilterPreferences.dateForDayKey("2024-03-03", calendar: calendar)!
let suiteName = "HOTEL_SHIFT_FIXED331_TEST_\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suiteName)!
let key = "csvHistoryFilters"
defer { defaults.removePersistentDomain(forName: suiteName) }

func saveIfValid(_ prefs: CSVHistoryFilterPreferences) -> Bool {
    guard let data = try? JSONEncoder().encode(prefs),
          CSVHistoryFilterPreferences.validated(from: data, calendar: calendar) != nil else { return false }
    defaults.set(data, forKey: key)
    return true
}
func load() -> CSVHistoryFilterRecovery.Outcome {
    CSVHistoryFilterRecovery.recover(defaults.object(forKey: key), calendar: calendar)
}
func preferences(_ search: String) -> CSVHistoryFilterPreferences {
    CSVHistoryFilterPreferences(search: search, status: "失敗", scope: "絞り込みCSV", dateEnabled: true,
        start: start, end: end, preset: nil,
        startDay: "2024-02-29", endDay: "2024-03-03")
}

if case .missing = load() { expect(true, "fresh installation has no saved filter") } else { preconditionFailure("missing") }
defaults.set(Data("broken-json".utf8), forKey: key)
if case .invalid = load() { expect(true, "corrupt persisted JSON is detected") } else { preconditionFailure("invalid") }
defaults.removeObject(forKey: key)
if case .missing = load() { expect(true, "corrupt saved data is cleared") } else { preconditionFailure("clear") }

var fresh = preferences("再設定")
expect(saveIfValid(fresh), "new settings can be saved after corruption")
if case .restored(let p, let s, let e, _) = load() {
    expect(p.search == "再設定", "restarted app restores new keyword")
    expect(p.status == "失敗", "restarted app restores status")
    expect(p.scope == "絞り込みCSV", "restarted app restores CSV scope")
    expect(p.dateEnabled, "restarted app restores date-enabled flag")
    expect(CSVHistoryFilterPreferences.dayKey(s, calendar: calendar) == "2024-02-29", "start day restored")
    expect(CSVHistoryFilterPreferences.dayKey(e, calendar: calendar) == "2024-03-03", "end day restored")
} else { preconditionFailure("restore after reset") }
let goodSnapshot = defaults.data(forKey: key)!

fresh.startDay = "2024-03-04" // intermediate date picker state, end before start
expect(!saveIfValid(fresh), "invalid intermediate date range cannot overwrite saved state")
expect(defaults.data(forKey: key) == goodSnapshot, "last valid snapshot preserved")
fresh = preferences("変更後")
expect(saveIfValid(fresh), "later valid edit can be saved")
if case .restored(let p, _, _, _) = load() { expect(p.search == "変更後", "valid edit survives restart") }
else { preconditionFailure("later valid edit") }

var invalidScope = fresh
invalidScope.scope = "unknown"
expect(!saveIfValid(invalidScope), "unknown CSV scope cannot overwrite preferences")
var invalidPreset = fresh
invalidPreset.preset = "unknown"
expect(!saveIfValid(invalidPreset), "unknown date preset cannot overwrite preferences")

// A legacy Date-only payload must migrate only once, without changing its filter selections.
var legacy = preferences("旧設定")
legacy.startDay = nil
legacy.endDay = nil
defaults.set(try! JSONEncoder().encode(legacy), forKey: key)
if case .restored(let migrated, _, _, let upgrade) = load() {
    expect(upgrade != nil, "legacy data supplies upgraded snapshot")
    expect(migrated.search == "旧設定", "legacy keyword preserved")
    defaults.set(upgrade!, forKey: key)
    if case .restored(_, _, _, let nextUpgrade) = load() {
        expect(nextUpgrade == nil, "migration is idempotent after restart")
    } else { preconditionFailure("migration reload") }
} else { preconditionFailure("legacy migration") }
print("FIXED331 recovery-save-restart integration checks completed")
