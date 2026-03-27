package net.wellvo.android.services

import android.app.Application
import android.util.Log
import com.telemetrydeck.sdk.TelemetryDeck
import dagger.hilt.android.qualifiers.ApplicationContext
import net.wellvo.android.BuildConfig
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AnalyticsService @Inject constructor(
    @ApplicationContext private val context: android.content.Context
) {
    companion object {
        private const val TAG = "AnalyticsService"

        // Auth events
        const val SIGN_IN = "sign_in"
        const val SIGN_UP = "sign_up"
        const val SIGN_OUT = "sign_out"

        // Check-in events
        const val CHECK_IN_COMPLETED = "check_in_completed"
        const val CHECK_IN_OFFLINE_QUEUED = "check_in_offline_queued"
        const val CHECK_IN_OFFLINE_SYNCED = "check_in_offline_synced"
        const val MOOD_SUBMITTED = "mood_submitted"

        // Dashboard events
        const val DASHBOARD_VIEWED = "dashboard_viewed"
        const val ON_DEMAND_SENT = "on_demand_sent"

        // Family events
        const val RECEIVER_INVITED = "receiver_invited"
        const val RECEIVER_REMOVED = "receiver_removed"

        // Settings events
        const val SETTINGS_SAVED = "settings_saved"
        const val REPORT_EXPORTED = "report_exported"

        // History events
        const val HISTORY_VIEWED = "history_viewed"

        // Subscription events
        const val SUBSCRIPTION_STARTED = "subscription_started"
        const val SUBSCRIPTION_RESTORED = "subscription_restored"
        const val SUBSCRIPTION_VIEW_OPENED = "subscription_view_opened"

        // Onboarding events
        const val ONBOARDING_STARTED = "onboarding_started"
        const val ONBOARDING_COMPLETED = "onboarding_completed"
        const val ONBOARDING_STEP_VIEWED = "onboarding_step_viewed"

        // Notification events
        const val NOTIFICATION_PERMISSION_GRANTED = "notification_permission_granted"
        const val NOTIFICATION_PERMISSION_DENIED = "notification_permission_denied"

        // Alert events
        const val ALERT_VIEWED = "alert_viewed"
        const val ALERT_DISMISSED = "alert_dismissed"

        // App lifecycle events
        const val APP_OPENED = "app_opened"
        const val APP_BACKGROUNDED = "app_backgrounded"
    }

    private var isInitialized = false

    fun initialize() {
        if (BuildConfig.DEBUG) {
            Log.d(TAG, "Analytics disabled in debug builds")
            return
        }

        val appId = BuildConfig.TELEMETRY_DECK_APP_ID
        if (appId.isBlank()) {
            Log.w(TAG, "TelemetryDeck app ID not configured")
            return
        }

        try {
            val builder = TelemetryDeck.Builder()
                .appID(appId)

            if (context is Application) {
                builder.build(context)
            }
            isInitialized = true
            Log.d(TAG, "TelemetryDeck initialized")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize TelemetryDeck", e)
        }
    }

    fun track(event: String, properties: Map<String, String> = emptyMap()) {
        if (!isInitialized) return

        try {
            if (properties.isEmpty()) {
                TelemetryDeck.signal(event)
            } else {
                TelemetryDeck.signal(event, properties)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to track event: $event", e)
        }
    }

    fun trackScreen(screenName: String) {
        track("screen_viewed", mapOf("screen" to screenName))
    }
}
