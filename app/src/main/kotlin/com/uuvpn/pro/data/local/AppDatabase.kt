package com.uuvpn.pro.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import com.uuvpn.pro.data.model.NodeModel

@Database(
    entities = [NodeModel::class],
    version = 1,
    exportSchema = false,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun nodeDao(): NodeDao
}
