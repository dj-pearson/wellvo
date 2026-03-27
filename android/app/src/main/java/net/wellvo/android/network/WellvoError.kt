package net.wellvo.android.network

sealed class WellvoError : Exception() {
    data class Network(override val message: String = "Network error. Please check your connection.") : WellvoError()
    data class Auth(override val message: String = "Authentication failed. Please sign in again.") : WellvoError()
    data class NotFound(override val message: String = "The requested resource was not found.") : WellvoError()
    data class ServerError(override val message: String = "Server error. Please try again later.") : WellvoError()
    data class Offline(override val message: String = "You are offline. Your action will sync when reconnected.") : WellvoError()
    data class Unknown(override val message: String = "An unexpected error occurred.") : WellvoError()

    val localizedMessage: String
        get() = message ?: "An unexpected error occurred."
}
