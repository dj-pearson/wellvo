package net.wellvo.android.di

import android.content.Context
import android.content.SharedPreferences
import androidx.room.Room
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import net.wellvo.android.data.WellvoDatabase
import net.wellvo.android.data.OfflineCheckInDao
import net.zetetic.database.sqlcipher.SupportOpenHelperFactory
import java.security.SecureRandom
import javax.inject.Qualifier
import javax.inject.Singleton

@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class SecurePrefs

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    private const val DB_KEY_PREF = "room_db_encryption_key"

    @Provides
    @Singleton
    fun provideSharedPreferences(
        @ApplicationContext context: Context
    ): SharedPreferences {
        return context.getSharedPreferences("wellvo_prefs", Context.MODE_PRIVATE)
    }

    @Provides
    @Singleton
    @SecurePrefs
    fun provideEncryptedSharedPreferences(
        @ApplicationContext context: Context
    ): SharedPreferences {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        return EncryptedSharedPreferences.create(
            context,
            "wellvo_secure_prefs",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    @Provides
    @Singleton
    fun provideDatabase(
        @ApplicationContext context: Context,
        @SecurePrefs securePrefs: SharedPreferences
    ): WellvoDatabase {
        // Load SQLCipher native libraries
        System.loadLibrary("sqlcipher")

        val passphrase = getOrCreateDbKey(securePrefs)
        val factory = SupportOpenHelperFactory(passphrase.toByteArray())

        // If an unencrypted DB exists, delete it so Room can create an encrypted one.
        // Offline check-ins are transient (synced and deleted), so no data loss risk.
        val dbFile = context.getDatabasePath("wellvo.db")
        if (dbFile.exists()) {
            migrateUnencryptedDb(context)
        }

        return Room.databaseBuilder(
            context,
            WellvoDatabase::class.java,
            "wellvo_encrypted.db"
        )
            .openHelperFactory(factory)
            .fallbackToDestructiveMigration()
            .build()
    }

    @Provides
    fun provideOfflineCheckInDao(database: WellvoDatabase): OfflineCheckInDao {
        return database.offlineCheckInDao()
    }

    /// Generate or retrieve the Room database encryption key from EncryptedSharedPreferences.
    private fun getOrCreateDbKey(securePrefs: SharedPreferences): String {
        val existing = securePrefs.getString(DB_KEY_PREF, null)
        if (existing != null) return existing

        // Generate a 32-byte random key encoded as hex
        val keyBytes = ByteArray(32)
        SecureRandom().nextBytes(keyBytes)
        val key = keyBytes.joinToString("") { "%02x".format(it) }

        securePrefs.edit().putString(DB_KEY_PREF, key).apply()
        return key
    }

    /// Remove old unencrypted database files so Room doesn't conflict.
    /// Offline check-ins are synced and deleted, so losing unsynced data is acceptable
    /// during this one-time migration to encrypted storage.
    private fun migrateUnencryptedDb(context: Context) {
        val dbFile = context.getDatabasePath("wellvo.db")
        val walFile = context.getDatabasePath("wellvo.db-wal")
        val shmFile = context.getDatabasePath("wellvo.db-shm")
        dbFile.delete()
        walFile.delete()
        shmFile.delete()
    }
}
