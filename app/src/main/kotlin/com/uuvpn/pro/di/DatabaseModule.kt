package com.uuvpn.pro.di

import android.content.Context
import androidx.room.Room
import com.uuvpn.pro.data.local.AppDatabase
import com.uuvpn.pro.data.local.NodeDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase {
        return Room.databaseBuilder(
            context,
            AppDatabase::class.java,
            "uuvpn_db",
        )
            .fallbackToDestructiveMigration()
            .build()
    }

    @Provides
    fun provideNodeDao(database: AppDatabase): NodeDao {
        return database.nodeDao()
    }
}
