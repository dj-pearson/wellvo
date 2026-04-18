package net.dailyok.android.util

import android.content.SharedPreferences
import net.dailyok.android.di.SecurePrefs
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SecureStorage @Inject constructor(
    @SecurePrefs private val prefs: SharedPreferences
) {
    fun save(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
    }

    /**
     * Synchronous save using commit() for critical data (auth tokens, credentials).
     * Blocks until write completes, ensuring data is persisted before continuing.
     */
    fun saveSync(key: String, value: String): Boolean {
        return prefs.edit().putString(key, value).commit()
    }

    fun load(key: String): String? {
        return prefs.getString(key, null)
    }

    fun delete(key: String) {
        prefs.edit().remove(key).apply()
    }

    fun deleteSync(key: String): Boolean {
        return prefs.edit().remove(key).commit()
    }

    fun contains(key: String): Boolean {
        return prefs.contains(key)
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    fun saveInt(key: String, value: Int) {
        prefs.edit().putInt(key, value).apply()
    }

    fun loadInt(key: String, default: Int = 0): Int {
        return prefs.getInt(key, default)
    }

    fun saveLong(key: String, value: Long) {
        prefs.edit().putLong(key, value).apply()
    }

    fun loadLong(key: String, default: Long = 0L): Long {
        return prefs.getLong(key, default)
    }

    fun saveBoolean(key: String, value: Boolean) {
        prefs.edit().putBoolean(key, value).apply()
    }

    fun loadBoolean(key: String, default: Boolean = false): Boolean {
        return prefs.getBoolean(key, default)
    }

    companion object Keys {
        const val AUTH_TOKEN = "auth_token"
        const val REFRESH_TOKEN = "refresh_token"
        const val GOOGLE_USER_ID = "google_user_id"
        const val USER_ID = "user_id"
        const val PUSH_TOKEN = "push_token"
        const val AUTH_FAILED_ATTEMPTS = "auth_failed_attempts"
        const val AUTH_LOCKOUT_UNTIL = "auth_lockout_until"
        const val HAPTICS_ENABLED = "dailyok.haptics.enabled"
    }
}
