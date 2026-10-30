import Foundation

let suite = "hotel.shift.fixed351.test.\(UUID().uuidString)"
guard let defaults = UserDefaults(suiteName: suite) else { fatalError("suite unavailable") }
defer { defaults.removePersistentDomain(forName: suite) }
let key = "history.preferences"
let timeKey = "history.savedAt"
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    precondition(condition(), name)
    checks += 1
}
check(defaults.data(forKey: key) == nil, "initially empty")
let first = Data("first snapshot".utf8)
defaults.set(first, forKey: key)
check(defaults.data(forKey: key) == first, "write readback")
let original = Date(timeIntervalSince1970: 1_700_000_000)
defaults.set(original, forKey: timeKey)
check(defaults.object(forKey: timeKey) as? Date == original, "timestamp written")
let second = Data("second snapshot".utf8)
defaults.set(second, forKey: key)
check(defaults.data(forKey: key) == second, "replacement readback")
check(defaults.object(forKey: timeKey) as? Date == original, "timestamp unchanged before verified update")
defaults.set("wrong type", forKey: key)
check(defaults.data(forKey: key) == nil, "invalid storage type detected")
check(defaults.object(forKey: timeKey) as? Date == original, "timestamp not advanced on failed validation")
defaults.set(first, forKey: key)
check(defaults.data(forKey: key) == first, "retry readback")
let newer = Date(timeIntervalSince1970: 1_700_000_100)
defaults.set(newer, forKey: timeKey)
check(defaults.object(forKey: timeKey) as? Date == newer, "timestamp updated after retry")
print("FIXED351: \(checks)/\(checks) UserDefaults persistence checks passed")
