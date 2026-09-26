package net.dailyok.android

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class DailyOKApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        val notificationManager = getSystemService(NotificationManager::class.java)

        val checkinChannel = NotificationChannel(
            CHANNEL_CHECKIN_REQUESTS,
            "Check-in Requests",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Daily check-in reminders and on-demand check-in requests"
            enableVibration(true)
            setSound(
                Uri.parse("android.resource://${packageName}/raw/notification_sound"),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .build()
            )
        }

        val urgentChannel = NotificationChannel(
            CHANNEL_URGENT_ALERTS,
            "Urgent Alerts",
            NotificationManager.IMPORTANCE_MAX
        ).apply {
            description = "Urgent alerts requiring immediate attention"
            enableVibration(true)
            enableLights(true)
        }

        val locationChannel = NotificationChannel(
            CHANNEL_LOCATION_ALERTS,
            "Location Alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alerts about receiver location changes"
            enableVibration(true)
        }

        // Everything informational: "Mom checked in", digests, reminders to an
        // owner. Before this, every message type the app didn't list by name
        // (owner_alert included) was logged and dropped.
        val updatesChannel = NotificationChannel(
            CHANNEL_FAMILY_UPDATES,
            "Family Updates",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Check-in confirmations and summaries"
        }

        notificationManager.createNotificationChannels(
            listOf(checkinChannel, urgentChannel, locationChannel, updatesChannel)
        )
    }

    companion object {
        const val CHANNEL_CHECKIN_REQUESTS = "checkin_requests"
        const val CHANNEL_URGENT_ALERTS = "urgent_alerts"
        const val CHANNEL_LOCATION_ALERTS = "location_alerts"
        const val CHANNEL_FAMILY_UPDATES = "family_updates"
    }
}
