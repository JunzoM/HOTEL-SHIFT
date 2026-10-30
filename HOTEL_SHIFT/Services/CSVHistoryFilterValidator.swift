import Foundation

// FIXED322: Pure, testable validation of persisted history-search preferences.
struct CSVHistoryFilterPreferences: Codable {
    var search: String
    var status: String
    var scope: String
    var dateEnabled: Bool
    var start: Date
    var end: Date
    var preset: String?
    // FIXED325: Stable local calendar dates survive a device timezone change.
    var startDay: String? = nil
    var endDay: String? = nil

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func dateForDayKey(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              dayKey(date, calendar: calendar) == key else { return nil }
        return calendar.startOfDay(for: date)
    }

    // FIXED327: Reject malformed keys even when a permissive parser could normalize them.
    // Persisted calendar days must be exactly four ASCII year digits, a hyphen,
    // two ASCII month digits, a hyphen and two ASCII day digits.
    static func isCanonicalDayKey(_ key: String, calendar: Calendar = .current) -> Bool {
        let bytes = Array(key.utf8)
        guard bytes.count == 10,
              bytes[4] == 45, bytes[7] == 45,
              [0, 1, 2, 3, 5, 6, 8, 9].allSatisfy({ (48...57).contains(bytes[$0]) }) else { return false }
        return dateForDayKey(key, calendar: calendar) != nil
    }

    func restoredDates(calendar: Calendar = .current) -> (start: Date, end: Date)? {
        if let startDay, let endDay {
            guard Self.isCanonicalDayKey(startDay, calendar: calendar),
                  Self.isCanonicalDayKey(endDay, calendar: calendar),
                  let start = Self.dateForDayKey(startDay, calendar: calendar),
                  let end = Self.dateForDayKey(endDay, calendar: calendar) else { return nil }
            return (start, end)
        }
        // Legacy records have absolute Date values only; preserve compatibility.
        guard start.timeIntervalSince1970.isFinite,
              end.timeIntervalSince1970.isFinite else { return nil }
        return (start, end)
    }

    // FIXED326: Upgrade legacy Date-only preferences to stable day keys once.
    // Keep the original absolute dates for decoding older app versions.
    func migratedToDayKeys(calendar: Calendar = .current) -> Self? {
        guard let dates = restoredDates(calendar: calendar) else { return nil }
        var copy = self
        copy.startDay = Self.dayKey(dates.start, calendar: calendar)
        copy.endDay = Self.dayKey(dates.end, calendar: calendar)
        return copy
    }

    static func validated(from data: Data, calendar: Calendar = .current) -> Self? {
        guard let value = try? JSONDecoder().decode(Self.self, from: data),
              ["すべて", "成功", "失敗"].contains(value.status),
              ["すべて", "全件CSV", "絞り込みCSV"].contains(value.scope),
              value.search.count <= 1000,
              value.start.timeIntervalSince1970.isFinite,
              value.end.timeIntervalSince1970.isFinite,
              (value.preset == nil || ["今日", "過去7日間", "過去30日間", "今月", "先月"].contains(value.preset!)),
              ((value.startDay == nil && value.endDay == nil) ||
               (value.startDay != nil && value.endDay != nil)),
              let restored = value.restoredDates(calendar: calendar),
              (!value.dateEnabled || value.preset != nil ||
               calendar.startOfDay(for: restored.start) <= calendar.startOfDay(for: restored.end)) else {
            return nil
        }
        return value
    }
}

// FIXED323: Calendar-aware inclusive date boundaries shared by UI and tests.
struct CSVHistoryDateRange {
    let start: Date
    let end: Date

    static func forPreset(_ preset: String, now: Date = Date(), calendar: Calendar = .current) -> Self? {
        let today = calendar.startOfDay(for: now)
        let start: Date
        let end: Date
        switch preset {
        case "今日": start = today; end = today
        case "過去7日間":
            guard let value = calendar.date(byAdding: .day, value: -6, to: today) else { return nil }
            start = value; end = today
        case "過去30日間":
            guard let value = calendar.date(byAdding: .day, value: -29, to: today) else { return nil }
            start = value; end = today
        case "今月":
            guard let month = calendar.dateInterval(of: .month, for: today) else { return nil }
            start = month.start; end = today
        case "先月":
            guard let thisMonth = calendar.dateInterval(of: .month, for: today),
                  let previousDay = calendar.date(byAdding: .day, value: -1, to: thisMonth.start),
                  let previousMonth = calendar.dateInterval(of: .month, for: previousDay) else { return nil }
            start = previousMonth.start; end = calendar.startOfDay(for: previousDay)
        default: return nil
        }
        return Self(start: start, end: end)
    }
}

// FIXED329: Restore as one validated snapshot, without partially applying UI state.
struct CSVHistoryFilterRecovery {
    enum Outcome {
        case missing
        case invalid
        case restored(CSVHistoryFilterPreferences, Date, Date, Data?)
    }

    static func recover(_ stored: Any?, calendar: Calendar = .current) -> Outcome {
        guard let stored else { return .missing }
        guard let data = stored as? Data,
              let original = CSVHistoryFilterPreferences.validated(from: data, calendar: calendar),
              let migrated = original.migratedToDayKeys(calendar: calendar),
              let dates = migrated.restoredDates(calendar: calendar) else { return .invalid }
        let upgrade = original.startDay == nil ? try? JSONEncoder().encode(migrated) : nil
        return .restored(migrated, dates.start, dates.end, upgrade)
    }
}


// FIXED357: Model the confirmation decision separately from SwiftUI.
// Cancellation must never read or mutate persisted preferences.
struct CSVHistoryRevertDecision {
    enum Outcome {
        case cancelled
        case missing
        case invalid
        case restored(CSVHistoryFilterPreferences, Date, Date)
    }

    static func evaluate(confirmed: Bool, stored: @autoclosure () -> Any?,
                         calendar: Calendar = .current) -> Outcome {
        guard confirmed else { return .cancelled }
        switch CSVHistoryFilterRecovery.recover(stored(), calendar: calendar) {
        case .missing: return .missing
        case .invalid: return .invalid
        case .restored(let preferences, let start, let end, _):
            return .restored(preferences, start, end)
        }
    }
}

// FIXED335: Timestamp lifecycle is independent of SwiftUI and testable on Linux.
struct CSVHistorySavedTimestamp {
    static func read(from defaults: UserDefaults, key: String, hasValidSnapshot: Bool) -> Date? {
        guard hasValidSnapshot, let value = defaults.object(forKey: key) as? Date,
              value.timeIntervalSince1970.isFinite else { return nil }
        return value
    }

    @discardableResult
    static func recordSuccessfulSave(in defaults: UserDefaults, key: String, at date: Date = Date()) -> Date? {
        guard date.timeIntervalSince1970.isFinite else { return nil }
        defaults.set(date, forKey: key)
        return date
    }

    static func clear(in defaults: UserDefaults, key: String) {
        defaults.removeObject(forKey: key)
    }
}

// FIXED336: Determine whether the on-screen filters match the last saved snapshot.
// Compare canonical day keys instead of absolute Date values to avoid timezone drift.
struct CSVHistorySnapshotComparison {
    static func matches(current: CSVHistoryFilterPreferences, stored: Any?, calendar: Calendar = .current) -> Bool {
        guard case .restored(let saved, _, _, _) = CSVHistoryFilterRecovery.recover(stored, calendar: calendar),
              let currentData = try? JSONEncoder().encode(current),
              CSVHistoryFilterPreferences.validated(from: currentData, calendar: calendar) != nil,
              let currentDays = current.migratedToDayKeys(calendar: calendar),
              let savedDays = saved.migratedToDayKeys(calendar: calendar) else { return false }
        return currentDays.search == savedDays.search &&
            currentDays.status == savedDays.status &&
            currentDays.scope == savedDays.scope &&
            currentDays.dateEnabled == savedDays.dateEnabled &&
            (!currentDays.dateEnabled || (
                currentDays.startDay == savedDays.startDay &&
                currentDays.endDay == savedDays.endDay &&
                currentDays.preset == savedDays.preset
            ))
    }
}

// FIXED352: A failed read-back must not destroy the previous valid snapshot.
// The injected writer permits deterministic failure-path tests without iOS UI.
struct CSVHistoryVerifiedWriter {
    enum Result { case saved, failed(restoredPrevious: Bool) }

    static func save(_ data: Data, in defaults: UserDefaults, key: String,
                     write: (UserDefaults, String, Data) -> Void = { $0.set($2, forKey: $1) }) -> Result {
        let previous = defaults.object(forKey: key)
        write(defaults, key, data)
        if defaults.data(forKey: key) == data { return .saved }
        // Restore only a previously valid snapshot. Never resurrect corrupt data.
        if case .restored = CSVHistoryFilterRecovery.recover(previous), let old = previous as? Data {
            defaults.set(old, forKey: key)
            return .failed(restoredPrevious: defaults.data(forKey: key) == old)
        }
        defaults.removeObject(forKey: key)
        return .failed(restoredPrevious: false)
    }
}

// FIXED354: Derive recovery UI state from the actual stored snapshot after a failed write.
// Never present a stale last-saved timestamp when the snapshot cannot be recovered.
struct CSVHistoryFailedSaveInspection {
    let hasSavedSnapshot: Bool
    let lastSavedAt: Date?

    static func inspect(defaults: UserDefaults, filtersKey: String, timestampKey: String) -> Self {
        let valid: Bool
        if case .restored = CSVHistoryFilterRecovery.recover(defaults.object(forKey: filtersKey)) {
            valid = true
        } else {
            valid = false
        }
        return Self(hasSavedSnapshot: valid,
                    lastSavedAt: CSVHistorySavedTimestamp.read(from: defaults,
                                                                key: timestampKey,
                                                                hasValidSnapshot: valid))
    }
}

// FIXED359: A restore warning survives unsuccessful retries and is cleared only
// after the new snapshot has been verified. This policy is UI-independent.
struct CSVHistoryRestoreRetryTransition {
    enum SaveResult { case invalidInput, writeFailed, verified }
    struct Outcome {
        let restoreNotice: String?
        let feedback: String?
        let saved: Bool
    }

    static func evaluate(previousNotice: String?, result: SaveResult) -> Outcome {
        switch result {
        case .invalidInput, .writeFailed:
            return Outcome(restoreNotice: previousNotice, feedback: nil, saved: false)
        case .verified:
            return Outcome(restoreNotice: nil,
                           feedback: previousNotice == nil ? nil : "検索条件を再設定して保存しました。",
                           saved: true)
        }
    }
}
