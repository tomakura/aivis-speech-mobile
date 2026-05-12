package com.aivis.speechmobile.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Book
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.automirrored.rounded.Help
import androidx.compose.material.icons.rounded.Memory
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aivis.speechmobile.ui.screens.DictionaryScreen
import com.aivis.speechmobile.ui.screens.HelpScreen
import com.aivis.speechmobile.ui.screens.ModelsScreen
import com.aivis.speechmobile.ui.screens.PresetsScreen
import com.aivis.speechmobile.ui.screens.SettingsScreen
import com.aivis.speechmobile.ui.screens.TalkScreen
import com.aivis.speechmobile.ui.theme.LocalAivisColors

private fun AppTab.icon(): ImageVector = when (this) {
    AppTab.TALK -> Icons.Rounded.GraphicEq
    AppTab.MODELS -> Icons.Rounded.Memory
    AppTab.PRESETS -> Icons.Rounded.Tune
    AppTab.DICTIONARY -> Icons.Rounded.Book
    AppTab.SETTINGS -> Icons.Rounded.Settings
    AppTab.HELP -> Icons.AutoMirrored.Rounded.Help
}

@Composable
fun AppRoot(appViewModel: AppViewModel) {
    val selectedTab by appViewModel.selectedTab.collectAsStateWithLifecycle()
    val colors = LocalAivisColors.current

    Scaffold(
        containerColor = colors.background,
        bottomBar = {
            NavigationBar(containerColor = colors.surface) {
                AppTab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = selectedTab == tab,
                        onClick = { appViewModel.selectTab(tab) },
                        icon = {
                            Icon(
                                imageVector = tab.icon(),
                                contentDescription = tab.title,
                            )
                        },
                        label = {
                            Text(tab.title, fontSize = 10.sp)
                        },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = colors.accent,
                            selectedTextColor = colors.accent,
                            unselectedIconColor = colors.mutedText,
                            unselectedTextColor = colors.mutedText,
                            indicatorColor = colors.accentMuted,
                        ),
                    )
                }
            }
        },
    ) { innerPadding ->
        Box(
            modifier = Modifier.fillMaxSize().padding(innerPadding),
        ) {
            when (selectedTab) {
                AppTab.TALK -> TalkScreen(appViewModel = appViewModel)
                AppTab.MODELS -> ModelsScreen(viewModel = appViewModel.modelManager)
                AppTab.PRESETS -> PresetsScreen(viewModel = appViewModel.presetManager)
                AppTab.DICTIONARY -> DictionaryScreen(viewModel = appViewModel.dictionaryManager)
                AppTab.SETTINGS -> SettingsScreen(viewModel = appViewModel.settingsViewModel)
                AppTab.HELP -> HelpScreen(viewModel = appViewModel.helpViewModel)
            }
        }
    }
}
