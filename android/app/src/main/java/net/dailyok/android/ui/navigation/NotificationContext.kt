package net.dailyok.android.ui.navigation

data class NotificationContext(
    val type: String,
    val requestId: String? = null,
    val receiverId: String? = null
)
