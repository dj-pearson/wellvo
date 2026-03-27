package net.wellvo.android.data

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(entities = [OfflineCheckIn::class], version = 1)
abstract class WellvoDatabase : RoomDatabase() {
    abstract fun offlineCheckInDao(): OfflineCheckInDao
}
