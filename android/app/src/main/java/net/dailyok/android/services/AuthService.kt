package net.dailyok.android.services

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
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.OtpType
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.auth.user.UserSession
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.rpc
import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.JsonPrimitive
import net.dailyok.android.BuildConfig
import net.dailyok.android.data.models.AppUser
import net.dailyok.android.network.DailyOKError
import net.dailyok.android.util.SecureStorage
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthService @Inject constructor(
    private val supabase: SupabaseClient,
    private val secureStorage: SecureStorage
) {
    val sessionStatus: Flow<SessionStatus>
        get() = supabase.auth.sessionStatus

    // Phone-number sign-in was retired: server-sent SMS codes would need A2P
    // 10DLC registration. Sign-in is Google or email. An account created with a
    // phone number keeps its session and is asked to add an email (below).

    /**
     * True when the signed-in account has no email: it was made with the
     * retired phone sign-in, so once signed out it has no way back in. A
     * pending (unconfirmed) address lives in new_email, not email, so it
     * still counts as missing.
     */
    fun signedInAccountLacksEmail(): Boolean {
        val user = supabase.auth.currentUserOrNull() ?: return false
        return accountLacksEmail(user.email)
    }

    /**
     * Ask GoTrue to attach [email] to the signed-in account. It emails a
     * 6-digit code (and a link); nothing changes until it is confirmed.
     */
    suspend fun requestAddEmail(email: String) {
        val trimmed = email.trim().lowercase()
        try {
            supabase.auth.updateUser { this.email = trimmed }
        } catch (e: Exception) {
            throw mapAuthError(e)
        }
    }

    /** Confirm the 6-digit code from the add-email message. */
    suspend fun confirmAddedEmail(email: String, code: String) {
        val trimmed = email.trim().lowercase()
        try {
            supabase.auth.verifyEmailOtp(
                type = OtpType.Email.EMAIL_CHANGE,
                email = trimmed,
                token = code.filter { it.isDigit() }
            )
        } catch (e: Exception) {
            throw mapAuthError(e)
        }
        syncProfileEmail()
    }

    /**
     * Whether the account now has a confirmed email, after the user tapped the
     * link in the message instead of typing the code. Refreshes the session so
     * the answer comes from the server.
     */
    suspend fun refreshAddedEmailStatus(): Boolean {
        try {
            supabase.auth.refreshCurrentSession()
        } catch (_: Exception) {
            return false
        }
        val hasEmail = !signedInAccountLacksEmail()
        if (hasEmail) syncProfileEmail()
        return hasEmail
    }

    /** Copy the confirmed auth email onto users.email (best-effort). */
    private suspend fun syncProfileEmail() {
        val user = supabase.auth.currentUserOrNull() ?: return
        val email = user.email?.takeIf { it.isNotBlank() } ?: return
        try {
            supabase.postgrest.from("users")
                .update(buildJsonObject { put("email", JsonPrimitive(email)) }) {
                    filter { eq("id", user.id) }
                }
        } catch (_: Exception) { /* best-effort */ }
    }

    suspend fun signUpWithEmail(email: String, password: String, displayName: String) {
        validatePassword(password)
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
            throw DailyOKError.Auth("Google Sign-In is not configured. Please set GOOGLE_WEB_CLIENT_ID.")
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
            throw DailyOKError.Auth("Unexpected credential type received.")
        } catch (e: GetCredentialCancellationException) {
            throw DailyOKError.Auth("Google Sign-In was cancelled.")
        } catch (e: NoCredentialException) {
            throw DailyOKError.Auth("No Google accounts available. Please add a Google account to your device.")
        } catch (e: DailyOKError) {
            throw e
        } catch (e: Exception) {
            throw mapAuthError(e)
        }
    }

    suspend fun resetPassword(email: String) {
        try {
            supabase.auth.resetPasswordForEmail(email.trim().lowercase())
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

    /**
     * Push the device's current IANA timezone to users.timezone when it
     * differs from the stored value. The edge-function dedup and the owner
     * dashboard's "today" window both key off this column, so a stale value
     * produces off-by-hours bugs. Best-effort: silent no-op on any failure.
     */
    suspend fun syncTimezoneIfChanged() {
        val userId = currentUserId() ?: return
        val deviceTz = java.time.ZoneId.systemDefault().id
        if (deviceTz.isBlank()) return

        try {
            val stored = supabase.postgrest.from("users")
                .select(columns = Columns.list("timezone")) {
                    filter { eq("id", userId) }
                }
                .decodeSingleOrNull<TimezoneOnly>()

            if (stored?.timezone == deviceTz) return

            supabase.postgrest.from("users")
                .update(buildJsonObject { put("timezone", JsonPrimitive(deviceTz)) }) {
                    filter { eq("id", userId) }
                }
        } catch (_: Exception) { /* best-effort */ }
    }

    @kotlinx.serialization.Serializable
    private data class TimezoneOnly(val timezone: String? = null)

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

    @kotlinx.serialization.Serializable
    private data class IdOnly(val id: String)

    @kotlinx.serialization.Serializable
    private data class RoleOnly(val role: net.dailyok.android.data.models.UserRole)

    /**
     * The signed-in user's role from their actual family membership: owner of
     * a family, else their active member role, else null (no family yet).
     * THROWS if the lookup fails — a failure is not "no family".
     *
     * Routing used users.role, which defaults to "owner" for every account,
     * so a receiver whose join hadn't completed landed in the owner tabs.
     */
    suspend fun currentMembershipRole(): net.dailyok.android.data.models.UserRole? {
        val userId = currentUserId() ?: return null
        val owned = supabase.postgrest.from("families")
            .select(Columns.list("id")) {
                filter { eq("owner_id", userId) }
                limit(1)
            }
            .decodeList<IdOnly>()
        if (owned.isNotEmpty()) return net.dailyok.android.data.models.UserRole.Owner

        return supabase.postgrest.from("family_members")
            .select(Columns.list("role")) {
                filter { eq("user_id", userId) }
                filter { eq("status", "active") }
                limit(1)
            }
            .decodeList<RoleOnly>()
            .firstOrNull()
            ?.role
    }

    suspend fun refreshSession() {
        try {
            supabase.auth.refreshCurrentSession()
        } catch (e: Exception) {
            throw mapAuthError(e)
        }
    }

    suspend fun exportUserData(): String {
        val userId = currentUserId() ?: throw DailyOKError.Auth("Not signed in.")
        val result = supabase.postgrest.rpc(
            "export_user_data",
            buildJsonObject { put("p_user_id", JsonPrimitive(userId)) }
        )
        return result.data
    }

    suspend fun deleteAccount() {
        val userId = currentUserId() ?: throw DailyOKError.Auth("Not signed in.")
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

    private fun validatePassword(password: String) {
        if (password.length < 10) {
            throw DailyOKError.Auth("Password must be at least 10 characters.")
        }
        if (password.length > 128) {
            throw DailyOKError.Auth("Password must be 128 characters or fewer.")
        }
        val hasUpper = password.any { it.isUpperCase() }
        val hasLower = password.any { it.isLowerCase() }
        val hasDigit = password.any { it.isDigit() }
        if (!hasUpper || !hasLower || !hasDigit) {
            throw DailyOKError.Auth("Password must contain uppercase, lowercase, and a number. Avoid common passwords.")
        }
        if (password.lowercase() in commonPasswords) {
            throw DailyOKError.Auth("This password is too common. Please choose a stronger password.")
        }
    }

    companion object {
        private val commonPasswords = setOf(
            "password", "123456789", "1234567890", "qwerty1234", "iloveyou1",
            "password1", "password12", "password123", "letmein123", "welcome123",
            "monkey1234", "dragon1234", "master1234", "qwertyuiop", "1234567891",
            "trustno1a", "sunshine12", "princess12", "football12", "charlie123",
            "shadow1234", "michael123", "jennifer12", "hunter1234", "thomas1234",
            "jordan1234", "mustang123", "access1234", "123456789a", "abcdefghij",
        )

        /** Pure core of [signedInAccountLacksEmail]. */
        fun accountLacksEmail(email: String?): Boolean = email.isNullOrBlank()

        /** Validates the phone number an owner types for someone they invite. */
        fun isValidUSPhone(phone: String): Boolean {
            val digits = phone.replace(Regex("[^\\d]"), "")
            return when {
                digits.length == 10 -> digits[0] in '2'..'9'
                digits.length == 11 -> digits.startsWith("1") && digits[1] in '2'..'9'
                else -> false
            }
        }

        fun mapAuthError(e: Exception): DailyOKError {
            val msg = e.message?.lowercase() ?: ""
            return when {
                "rate" in msg || "too many" in msg -> DailyOKError.Auth("Too many attempts. Please wait and try again.")
                "invalid" in msg && "otp" in msg -> DailyOKError.Auth("Invalid code. Please check and try again.")
                "expired" in msg -> DailyOKError.Auth("Code expired. Please request a new one.")
                "already" in msg && ("registered" in msg || "exists" in msg || "in use" in msg) ->
                    DailyOKError.Auth("That email is already used by another Daily OK account.")
                "not found" in msg -> DailyOKError.NotFound()
                "network" in msg || "connection" in msg -> DailyOKError.Network()
                else -> DailyOKError.Auth(e.message ?: "Authentication failed.")
            }
        }
    }
}
