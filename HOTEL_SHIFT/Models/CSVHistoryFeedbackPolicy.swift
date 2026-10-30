import Foundation

// FIXED345: Pure policy shared by SwiftUI feedback and executable transition tests.
enum CSVHistoryFeedbackPolicy {
    static func shouldPresent(message: String, symbol: String, state: String,
                              dismissedKey: String?, dismissedState: String?,
                              activeMessage: String?, activeSymbol: String?, activeState: String?) -> Bool {
        let fingerprint = message + "|" + symbol
        if dismissedState == state && dismissedKey == fingerprint { return false }
        if activeMessage == message && activeSymbol == symbol && activeState == state { return false }
        return true
    }
}
