# Default ProGuard rules for Wellvo Android app
# Add project-specific ProGuard rules here.

# Keep Kotlin metadata for reflection
-keepattributes *Annotation*
-keepattributes RuntimeVisibleAnnotations
-keepattributes Signature
-keepattributes InnerClasses

# Keep Compose @Preview functions in debug builds
-keepclassmembers class * {
    @androidx.compose.ui.tooling.preview.Preview *;
}

# Hilt
-keep class dagger.hilt.** { *; }
-keep class javax.inject.** { *; }
-keep class * extends dagger.hilt.android.internal.managers.ViewComponentManager$FragmentContextWrapper { *; }

# Supabase SDK
-keep class io.github.jan.supabase.** { *; }
-keep class io.ktor.** { *; }
-dontwarn io.ktor.**

# Kotlinx Serialization
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

# Room
-keep class * extends androidx.room.RoomDatabase { *; }
-keep @androidx.room.Entity class * { *; }
-keep @androidx.room.Dao class * { *; }

# Google Sign-In / Credential Manager
-keep class com.google.android.libraries.identity.googleid.** { *; }
-keep class androidx.credentials.** { *; }
