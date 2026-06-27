import Foundation

/// Centralized error type for all Daily OK services.
/// Provides user-facing localized descriptions for consistent error display.
enum DailyOKError: LocalizedError {
    case network(Error)
    case auth(String)
    case notFound(String)
    case serverError(String)
    case offline
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .network(let error):
            return String(localized: "Network error: \(error.localizedDescription)")
        case .auth(let message):
            return message
        case .notFound(let resource):
            return String(localized: "\(resource) not found.")
        case .serverError(let message):
            return String(localized: "Server error: \(message)")
        case .offline:
            return String(localized: "You appear to be offline. Your action will be completed when you reconnect.")
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
