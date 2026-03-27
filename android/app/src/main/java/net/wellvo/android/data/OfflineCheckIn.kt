package net.wellvo.android.data

import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.PrimaryKey
import androidx.room.Query

@Entity(tableName = "offline_checkins")
data class OfflineCheckIn(
    @PrimaryKey
    val id: String,
    @ColumnInfo(name = "family_id")
    val familyId: String,
    @ColumnInfo(name = "receiver_id")
    val receiverId: String,
    val mood: String? = null,
    val source: String,
    @ColumnInfo(name = "created_at")
    val createdAt: Long,
    val synced: Boolean = false
)

@Dao
interface OfflineCheckInDao {
    @Insert
    suspend fun insert(checkIn: OfflineCheckIn)

    @Query("SELECT * FROM offline_checkins WHERE synced = 0")
    suspend fun getUnsynced(): List<OfflineCheckIn>

    @Query("UPDATE offline_checkins SET synced = 1 WHERE id = :id")
    suspend fun markSynced(id: String)

    @Query("DELETE FROM offline_checkins")
    suspend fun deleteAll()
}
