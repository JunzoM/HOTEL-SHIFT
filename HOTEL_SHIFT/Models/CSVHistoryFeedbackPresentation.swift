import Foundation

// FIXED347: One source for the visible notification and VoiceOver announcement.
enum CSVHistoryFeedbackPresentation {
    static func visibleMessage(_ message: String) -> String { message }

    static func announcement(message: String, status: String) -> String {
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanMessage.isEmpty { return cleanStatus }
        if cleanStatus.isEmpty || cleanMessage == cleanStatus { return cleanMessage }
        return cleanMessage + (cleanMessage.hasSuffix("。") ? "" : "。") + cleanStatus
    }
}


// FIXED348: Evaluate the visual and spoken feedback from the same accepted event.
struct CSVHistoryFeedbackDecision {
    let shouldPresent: Bool
    let visibleMessage: String?
    let announcement: String?

    static func evaluate(message: String, symbol: String, state: String,
                         dismissedKey: String?, dismissedState: String?,
                         activeMessage: String?, activeSymbol: String?, activeState: String?) -> Self {
        let allowed = CSVHistoryFeedbackPolicy.shouldPresent(
            message: message, symbol: symbol, state: state,
            dismissedKey: dismissedKey, dismissedState: dismissedState,
            activeMessage: activeMessage, activeSymbol: activeSymbol, activeState: activeState)
        return Self(shouldPresent: allowed,
                    visibleMessage: allowed ? CSVHistoryFeedbackPresentation.visibleMessage(message) : nil,
                    announcement: allowed ? CSVHistoryFeedbackPresentation.announcement(message: message, status: state) : nil)
    }
}
