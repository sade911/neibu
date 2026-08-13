package com.uuvpn.pro

import android.app.Application
import dagger.hilt.android.HiltAndroidApp

/**
 * UUVPN PRO Application — Hilt 入口
 */
@HiltAndroidApp
class UuVpnApp : Application() {

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    companion object {
        lateinit var instance: UuVpnApp
            private set
    }
}
