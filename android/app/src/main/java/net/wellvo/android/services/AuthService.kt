package net.wellvo.android.services

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.providers.builtin.IDToken
import io.github.jan.supabase.auth.providers.builtin.OTP
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.auth.user.UserSession
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.rpc
import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.JsonPrimitive
import net.wellvo.android.BuildConfig
import net.wellvo.android.data.models.AppUser
import net.wellvo.android.network.WellvoError
import net.wellvo.android.util.SecureStorage
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthService @Inject constructor(
    private val supabase: SupabaseClient,
    private val secureStorage: SecureStorage
) {
    val sessionStatus: Flow<SessionStatus>
        get() = supabase.auth.sessionStatus

    suspend fun sendPhoneOTP(phone: String) {
        val normalized = normalizePhone(phone)
        try {
            supabase.auth.signInWith(OTP) {
                this.phone = normalized
            }
        } catch (e: Exception) {
            throw mapAuthError(e)
        }
    }

    suspend fun verifyPhoneOTP(phone: String, code: String) {
        val normalized = normalizePhone(phone)
        try {
            supabase.auth.verifyPhoneOtp(
                phone = normalized,
                token = code,
                type = io.github.jan.supabase.auth.OtpType.Phone.SMS
            )
        } catch (e: Exception) {
            throw mapAuthError(e)
        }
    }

    suspend fun signUpWithEmail(email: String, password: String, displayName: String) {
        try {
            supabase.auth.signUpWith(Email) {
                this.email = email
                this.password = password
                this.data = kotlinx.serialization.json.buildJsonObject {
                    put("display_name", kotlinx.serialization.json.JsonPrimitive(displayName))
                }
            }
        } catch (e: Exception) {
            throw mapAuthError(e)
        }
    }

    suspend fun signInWithEmail(email: String, password: String) {
        try {
            supabase.auth.signInWith(Email) {
                this.email = email
                this.password = password
            }
        } catch (e: Exception) {
            throw mapAuthError(e)
        }
    }

    suspend fun signInWithGoogle(context: Context) {
        val webClientId = BuildConfig.GOOGLE_WEB_CLIENT_ID
        if (webClientId.isBlank()) {
            throw WellvoError.Auth("Google Sign-In is not configured. Please set GOOGLE_WEB_CLIENT_ID.")
        }

        val googleIdToken = getGoogleIdToken(context, webClientId)

        try {
            supabase.auth.signInWith(IDToken) {
                provider = Google
                idToken = googleIdToken
            }
        } catch (e: Exception) {
            throw mapAuthError(e)
        }
    }

    private suspend fun getGoogleIdToken(context: Context, webClientId: String): String {
        val credentialManager = CredentialManager.create(context)

        val googleIdOption = GetGoogleIdOption.Builder()
            .setFilterByAuthorizedAccounts(false)
            .setServerClientId(webClientId)
            .setAutoSelectEnabled(true)
            .build()

        val request = GetCredentialRequest.Builder()
            .addCredentialOption(googleIdOption)
            .build()

        try {
            val result = credentialManager.getCredential(context, request)
            val credential = result.credential

            if (credential is CustomCredential &&
                credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
            ) {
                val googleIdTokenCredential = GoogleIdTokenCredential.createFrom(credential.data)
                return googleIdTokenCredential.idToken
            }
            throw WellvoError.Auth("Unexpected credential type received.")
        } catch (e: GetCredentialCancellationException) {
            throw WellvoError.Auth("Google Sign-In was cancelled.")
        } catch (e: NoCredentialException) {
            throw WellvoError.Auth("No Google accounts available. Please add a Google account to your device.")
        } catch (e: WellvoError) {
            throw e
        } catch (e: Exception) {
            throw mapAuthError(e)
        }
    }

    suspend fun getCurrentUser(): AppUser? {
        val userId = currentUserId() ?: return null
        return try {
            supabase.postgrest.from("users")
                .select {
                    filter { eq("id", userId) }
                }
                .decodeSingleOrNull<AppUser>()
        } catch (_: Exception) {
            null
        }
    }

    suspend fun signOut() {
        try {
            supabase.auth.signOut()
        } catch (_: Exception) { }
        secureStorage.clear()
    }

    fun currentSession(): UserSession? {
        return supabase.auth.currentSessionOrNull()
    }

    fun currentUserId(): String? {
        return supabase.auth.currentUserOrNull()?.id
    }

    suspend fun refreshSession() {
        try {
            supabase.auth.refreshCurrentSession()
        } catch (e: Exception) {
            throw mapAuthError(e)
        }
    }

    suspend fun exportUserData(): String {
        val userId = currentUserId() ?: throw WellvoError.Auth("Not signed in.")
        val result = supabase.postgrest.rpc(
            "export_user_data",
            buildJsonObject { put("p_user_id", JsonPrimitive(userId)) }
        )
        return result.data
    }

    suspend fun deleteAccount() {
        val userId = currentUserId() ?: throw WellvoError.Auth("Not signed in.")
        supabase.postgrest.rpc(
            "delete_user_account",
            buildJsonObject { put("p_user_id", JsonPrimitive(userId)) }
        )
        signOut()
    }

    suspend fun isGoogleLinked(): Boolean {
        val user = supabase.auth.currentUserOrNull() ?: return false
        return user.identities?.any { it.provider == "google" } == true
    }

    suspend fun updateDataRetention(familyId: String, days: Int) {
        supabase.postgrest.from("families")
            .update(buildJsonObject { put("data_retention_days", JsonPrimitive(days)) }) {
                filter { eq("id", familyId) }
            }
    }

    suspend fun getDataRetention(familyId: String): Int {
        @kotlinx.serialization.Serializable
        data class RetentionResult(
            @kotlinx.serialization.SerialName("data_retention_days")
            val dataRetentionDays: Int
        )
        return try {
            supabase.postgrest.from("families")
                .select(Columns.list("data_retention_days")) {
                    filter { eq("id", familyId) }
                }
                .decodeSingle<RetentionResult>()
                .dataRetentionDays
        } catch (_: Exception) {
            365
        }
    }

    companion object {
        fun normalizePhone(phone: String): String {
            val digits = phone.replace(Regex("[^\\d]"), "")
            return when {
                digits.length == 10 && digits[0] in '2'..'9' -> "+1$digits"
                digits.length == 11 && digits.startsWith("1") -> "+$digits"
                phone.startsWith("+") -> phone
                else -> "+$digits"
            }
        }

        fun isValidUSPhone(phone: String): Boolean {
            val digits = phone.replace(Regex("[^\\d]"), "")
            return when {
                digits.length == 10 -> digits[0] in '2'..'9'
                digits.length == 11 -> digits.startsWith("1") && digits[1] in '2'..'9'
                else -> false
            }
        }

        fun mapAuthError(e: Exception): WellvoError {
            val msg = e.message?.lowercase() ?: ""
            return when {
                "rate" in msg || "too many" in msg -> WellvoError.Auth("Too many attempts. Please wait and try again.")
                "invalid" in msg && "otp" in msg -> WellvoError.Auth("Invalid code. Please check and try again.")
                "expired" in msg -> WellvoError.Auth("Code expired. Please request a new one.")
                "not found" in msg -> WellvoError.NotFound()
                "network" in msg || "connection" in msg -> WellvoError.Network()
                else -> WellvoError.Auth(e.message ?: "Authentication failed.")
            }
        }
    }
}
