package net.dailyok.android.ui.navigation

import net.dailyok.android.data.models.AppUser

sealed class AuthState {
    data object Loading : AuthState()
    data object Unauthenticated : AuthState()
    data class Authenticated(val user: AppUser) : AuthState()
}
