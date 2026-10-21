package com.aivis.speechmobile

import android.app.Application
import com.aivis.speechmobile.core.storage.AppStorage

class AivisSpeechApplication : Application() {
    lateinit var appStorage: AppStorage
        private set

    override fun onCreate() {
        super.onCreate()
        appStorage = AppStorage(this)
    }
}
