package net.wellvo.android.services

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessaging
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.tasks.await
import net.wellvo.android.util.SecureStorage
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
            val storedToken = secureStorage.load(SecureStorage.PUSH_TOKEN)

            if (token == storedToken) {
                Log.d(TAG, "FCM token unchanged, skipping registration")
                return
            }

            // Mark old tokens as inactive
            if (storedToken != null) {
                try {
                    supabase.postgrest.from("push_tokens")
                        .update(mapOf("is_active" to false)) {
                            filter {
                                eq("user_id", userId)
                                eq("token", storedToken)
                            }
                        }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to deactivate old token", e)
                }
            }

            // Register new token
            supabase.postgrest.from("push_tokens")
                .upsert(
                    mapOf(
                        "user_id" to userId,
                        "token" to token,
                        "platform" to "android",
                        "is_active" to true
                    )
                )

            secureStorage.save(SecureStorage.PUSH_TOKEN, token)
            Log.d(TAG, "FCM token registered successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register FCM token", e)
            throw e
        }
    }

    suspend fun refreshToken(userId: String) {
        registerToken(userId)
    }
}
