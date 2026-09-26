package net.dailyok.android.ui.navigation

/**
 * The role routing cares about. MainActivity and DailyOKNavHost referred to
 * this type but it was never declared, so the app could not compile — hidden
 * because CI stopped at dependency resolution before reaching compilation.
 */
enum class UserRole { Owner, Receiver, Viewer }

fun net.dailyok.android.data.models.UserRole.toNavRole(): UserRole = when (this) {
    net.dailyok.android.data.models.UserRole.Owner -> UserRole.Owner
    net.dailyok.android.data.models.UserRole.Receiver -> UserRole.Receiver
    net.dailyok.android.data.models.UserRole.Viewer -> UserRole.Viewer
}

fun UserRole.toModelRole(): net.dailyok.android.data.models.UserRole = when (this) {
    UserRole.Owner -> net.dailyok.android.data.models.UserRole.Owner
    UserRole.Receiver -> net.dailyok.android.data.models.UserRole.Receiver
    UserRole.Viewer -> net.dailyok.android.data.models.UserRole.Viewer
}
