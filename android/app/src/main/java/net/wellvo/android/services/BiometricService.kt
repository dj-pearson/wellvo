package net.wellvo.android.services

import android.content.Context
import android.content.SharedPreferences
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.suspendCancellableCoroutine
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

@Singleton
class BiometricService @Inject constructor(
    @ApplicationContext private val context: Context,
    private val prefs: SharedPreferences
) {
    companion object {
        private const val KEY_BIOMETRIC_ENABLED = "biometric_auth_enabled"
        private const val KEY_BIOMETRIC_SKIPPED = "biometric_auth_skipped"
    }

    // MARK: - Availability

    fun isBiometricAvailable(): Boolean {
        val biometricManager = BiometricManager.from(context)
        return biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) ==
                BiometricManager.BIOMETRIC_SUCCESS
    }

    fun biometricName(): String {
        return "Biometric" // Android doesn't easily distinguish face vs fingerprint
    }

    // MARK: - Authentication

    suspend fun authenticate(activity: FragmentActivity): Boolean {
        if (!isBiometricAvailable()) return false

        return suspendCancellableCoroutine { continuation ->
            val executor = ContextCompat.getMainExecutor(activity)

            val callback = object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    if (continuation.isActive) continuation.resume(true)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    if (continuation.isActive) continuation.resume(false)
                }

                override fun onAuthenticationFailed() {
                    // Don't resume yet — user can retry within the system prompt
                }
            }

            val promptInfo = BiometricPrompt.PromptInfo.Builder()
                .setTitle("Unlock Wellvo")
                .setSubtitle("Use your biometric credential to continue")
                .setNegativeButtonText("Cancel")
                .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
                .build()

            val biometricPrompt = BiometricPrompt(activity, executor, callback)
            biometricPrompt.authenticate(promptInfo)

            continuation.invokeOnCancellation {
                biometricPrompt.cancelAuthentication()
            }
        }
    }

    // MARK: - Preference Management

    var isEnabled: Boolean
        get() = prefs.getBoolean(KEY_BIOMETRIC_ENABLED, false)
        set(value) { prefs.edit().putBoolean(KEY_BIOMETRIC_ENABLED, value).apply() }

    var hasBeenSkipped: Boolean
        get() = prefs.getBoolean(KEY_BIOMETRIC_SKIPPED, false)
        set(value) { prefs.edit().putBoolean(KEY_BIOMETRIC_SKIPPED, value).apply() }

    fun shouldPromptToEnable(): Boolean {
        return isBiometricAvailable() && !isEnabled && !hasBeenSkipped
    }

    fun reset() {
        prefs.edit()
            .remove(KEY_BIOMETRIC_ENABLED)
            .remove(KEY_BIOMETRIC_SKIPPED)
            .apply()
    }
}
