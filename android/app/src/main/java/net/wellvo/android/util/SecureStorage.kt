package net.wellvo.android.util

import android.content.SharedPreferences
import net.wellvo.android.di.SecurePrefs
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SecureStorage @Inject constructor(
    @SecurePrefs private val prefs: SharedPreferences
) {
    fun save(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
    }

    fun load(key: String): String? {
        return prefs.getString(key, null)
    }

    fun delete(key: String) {
        prefs.edit().remove(key).apply()
    }

    fun contains(key: String): Boolean {
        return prefs.contains(key)
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    companion object Keys {
        const val AUTH_TOKEN = "auth_token"
        const val REFRESH_TOKEN = "refresh_token"
        const val GOOGLE_USER_ID = "google_user_id"
        const val USER_ID = "user_id"
        const val PUSH_TOKEN = "push_token"
    }
}
