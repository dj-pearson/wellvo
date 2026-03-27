# ProGuard rules for Wellvo Android app (release builds)

# ============================================================
# Kotlin metadata
# ============================================================
-keepattributes *Annotation*
-keepattributes RuntimeVisibleAnnotations
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes SourceFile,LineNumberTable

# ============================================================
# Jetpack Compose
# ============================================================
-keepclassmembers class * {
    @androidx.compose.ui.tooling.preview.Preview *;
}

# ============================================================
# Hilt / Dagger
# ============================================================
-keep class dagger.hilt.** { *; }
-keep class javax.inject.** { *; }
-keep class * extends dagger.hilt.android.internal.managers.ViewComponentManager$FragmentContextWrapper { *; }
-keepclasseswithmembers class * {
    @dagger.hilt.android.lifecycle.HiltViewModel <init>(...);
}

# ============================================================
# Supabase SDK + Ktor
# ============================================================
-keep class io.github.jan.supabase.** { *; }
-keep class io.ktor.** { *; }
-dontwarn io.ktor.**
-dontwarn org.slf4j.**

# ============================================================
# Kotlinx Serialization
# ============================================================
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class net.wellvo.android.**$$serializer { *; }
-keepclassmembers class net.wellvo.android.** {
    *** Companion;
}
-keepclasseswithmembers class net.wellvo.android.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# ============================================================
# Room
# ============================================================
-keep class * extends androidx.room.RoomDatabase { *; }
-keep @androidx.room.Entity class * { *; }
-keep @androidx.room.Dao class * { *; }

# ============================================================
# Google Sign-In / Credential Manager
# ============================================================
-keep class com.google.android.libraries.identity.googleid.** { *; }
-keep class androidx.credentials.** { *; }

# ============================================================
# Firebase Cloud Messaging
# ============================================================
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# ============================================================
# Google Play Billing
# ============================================================
-keep class com.android.vending.billing.** { *; }
-keep class com.android.billingclient.** { *; }

# ============================================================
# Google Play Services Location
# ============================================================
-keep class com.google.android.gms.location.** { *; }

# ============================================================
# WorkManager
# ============================================================
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
-keep class androidx.work.WorkerParameters { *; }

# ============================================================
# OkHttp (used by Ktor engine)
# ============================================================
-dontwarn okhttp3.**
-dontwarn okio.**

# ============================================================
# TelemetryDeck Analytics
# ============================================================
-keep class com.telemetrydeck.sdk.** { *; }
