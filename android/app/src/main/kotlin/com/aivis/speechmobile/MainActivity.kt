package com.aivis.speechmobile

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.viewmodel.compose.viewModel
import com.aivis.speechmobile.ui.AppRoot
import com.aivis.speechmobile.ui.AppViewModel
import com.aivis.speechmobile.ui.theme.AivisSpeechTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val appStorage = (application as AivisSpeechApplication).appStorage
        setContent {
            AivisSpeechTheme {
                val appViewModel: AppViewModel = viewModel {
                    AppViewModel(storage = appStorage)
                }
                AppRoot(appViewModel = appViewModel)
            }
        }
    }
}
