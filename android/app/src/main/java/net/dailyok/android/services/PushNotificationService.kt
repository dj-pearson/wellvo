package net.dailyok.android.services

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import net.dailyok.android.util.DebugLog as Log
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessaging
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import net.dailyok.android.util.SecureStorage
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PushNotificationService @Inject constructor(
    private val supabase: SupabaseClient,
    private val secureStorage: SecureStorage
) {
    companion object {
        private const val TAG = "PushNotificationService"
    }

    fun checkPermissionStatus(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    fun requiresPermissionRequest(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
    }

    suspend fun registerToken(userId: String) {
        try {
            val token = FirebaseMessaging.getInstance().token.await()
            upsertToken(userId, token)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register FCM token", e)
            throw e
        }
    }

    /**
     * Core token upsert logic shared between registerToken() and onNewToken().
     *
     * Mirrors iOS PushNotificationService.registerToken:
     *  - The "already registered" cache is per user. It used to be the bare
     *    last-seen token, which onNewToken also wrote before anyone was signed
     *    in — so the first real registration compared equal and was skipped,
     *    and the token never reached the server.
     *  - The upsert targets UNIQUE(user_id, token). Without onConflict it
     *    resolved on the primary key and became an INSERT that failed for a
     *    returning user's existing row.
     *  - JSON objects, not mapOf(...) — a Map<String, Any> has no serializer.
     */
    suspend fun upsertToken(userId: String, token: String) {
        val registeredKey = registeredTokenKey(userId)
        if (secureStorage.load(registeredKey) == token) {
            Log.d(TAG, "FCM token already registered for this user, skipping")
            return
        }

        // Deactivate this user's OTHER Android tokens (never the live one).
        try {
            supabase.postgrest.from("push_tokens")
                .update(buildJsonObject { put("is_active", false) }) {
                    filter {
                        eq("user_id", userId)
                        eq("platform", "android")
                        neq("token", token)
                    }
                }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to deactivate old tokens", e)
        }

        supabase.postgrest.from("push_tokens")
            .upsert(
                buildJsonObject {
                    put("user_id", userId)
                    put("token", token)
                    put("platform", "android")
                    put("is_active", true)
                }
            ) {
                onConflict = "user_id,token"
            }

        secureStorage.saveSync(registeredKey, token)
        secureStorage.saveSync(SecureStorage.PUSH_TOKEN, token)
        Log.d(TAG, "FCM token registered successfully")
    }

    private fun registeredTokenKey(userId: String) = "${SecureStorage.PUSH_TOKEN}_registered_$userId"

    /**
     * Called once a user is signed in: remember who they are (so onNewToken can
     * register a rotated token in the background) and register this device's
     * token. Nothing called registerToken before, so no Android device ever
     * received a push.
     */
    suspend fun onSignedIn(userId: String) {
        secureStorage.saveSync(SecureStorage.USER_ID, userId)
        try {
            registerToken(userId)
        } catch (e: Exception) {
            // Retried on the next sign-in / app start.
            Log.e(TAG, "FCM registration after sign-in failed", e)
        }
    }

    /** Stop this device receiving the user's pushes after sign-out. */
    suspend fun onSignedOut() {
        val userId = secureStorage.load(SecureStorage.USER_ID)
        val token = secureStorage.load(SecureStorage.PUSH_TOKEN)
        if (userId != null && token != null) {
            try {
                supabase.postgrest.from("push_tokens")
                    .update(buildJsonObject { put("is_active", false) }) {
                        filter {
                            eq("user_id", userId)
                            eq("token", token)
                        }
                    }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to deactivate token on sign-out", e)
            }
            secureStorage.deleteSync(registeredTokenKey(userId))
        }
        secureStorage.deleteSync(SecureStorage.USER_ID)
    }

    suspend fun refreshToken(userId: String) {
        registerToken(userId)
    }
}
