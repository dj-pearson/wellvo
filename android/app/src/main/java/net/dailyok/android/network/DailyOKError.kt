package net.dailyok.android.network

sealed class DailyOKError : Exception() {
    data class Network(override val message: String = "Network error. Please check your connection.") : DailyOKError()
    data class Auth(override val message: String = "Authentication failed. Please sign in again.") : DailyOKError()
    data class NotFound(override val message: String = "The requested resource was not found.") : DailyOKError()
    data class ServerError(override val message: String = "Server error. Please try again later.") : DailyOKError()
    data class Offline(override val message: String = "You are offline. Your action will sync when reconnected.") : DailyOKError()
    data class Unknown(override val message: String = "An unexpected error occurred.") : DailyOKError()
    /**
     * The server answered and said no (wrong code, invite expired, family
     * full, too many attempts). [message] is the server's own explanation,
     * safe to show. Never retried: repeating a rejected pairing code counts as
     * another failed attempt.
     */
    data class Rejected(val status: Int, override val message: String) : DailyOKError()

    val localizedMessage: String
        get() = message ?: "An unexpected error occurred."
}
