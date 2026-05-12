package com.aivis.speechmobile.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aivis.speechmobile.core.EngineRuntimeStatus
import com.aivis.speechmobile.ui.SettingsViewModel
import com.aivis.speechmobile.ui.components.AivisDivider
import com.aivis.speechmobile.ui.components.AivisKeyValueRow
import com.aivis.speechmobile.ui.components.AivisNotice
import com.aivis.speechmobile.ui.components.AivisOverview
import com.aivis.speechmobile.ui.components.AivisScrollableScreen
import com.aivis.speechmobile.ui.components.AivisSection
import com.aivis.speechmobile.ui.theme.LocalAivisColors

@Composable
fun SettingsScreen(viewModel: SettingsViewModel) {
    val remoteEnabled by viewModel.remoteEngineEnabled.collectAsStateWithLifecycle()
    val remoteURL by viewModel.remoteEngineURLString.collectAsStateWithLifecycle()
    val colors = LocalAivisColors.current
    val status = viewModel.runtimeStatus

    AivisScrollableScreen(title = "設定") {
        AivisSection(title = "エンジンランタイム") {
            AivisKeyValueRow(
                label = "プロバイダー",
                value = status.providerName,
            )
            AivisDivider()
            AivisKeyValueRow(
                label = "ステータス",
                value = if (status.availability == EngineRuntimeStatus.Availability.LINKED) "利用可能" else "準備中",
            )
            AivisDivider()
            AivisKeyValueRow(
                label = "実行プロバイダー",
                value = status.preferredExecutionProvider,
            )
            status.linkedVersion?.let { ver ->
                AivisDivider()
                AivisKeyValueRow(label = "バージョン", value = ver)
            }
            if (status.nnApiAvailable) {
                AivisDivider()
                AivisKeyValueRow(label = "NNAPI", value = "利用可能")
            }
        }
        AivisOverview(title = "ランタイム情報", body = viewModel.summary)
        AivisSection(title = "リモートエンジン") {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "リモートエンジンを使用",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        text = "AivisSpeech Engine に HTTP 接続",
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.mutedText,
                    )
                }
                Switch(
                    checked = remoteEnabled,
                    onCheckedChange = { viewModel.setRemoteEngineEnabled(it) },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = colors.accent,
                        checkedTrackColor = colors.accentMuted,
                    ),
                )
            }
            if (remoteEnabled) {
                AivisDivider()
                Spacer(Modifier.height(4.dp))
                OutlinedTextField(
                    value = remoteURL,
                    onValueChange = { viewModel.setRemoteEngineURLString(it) },
                    label = { Text("エンジン URL") },
                    placeholder = { Text("http://127.0.0.1:10101") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
        }
        AivisNotice(body = "リモートエンジンを有効にすると、ローカルの AivisSpeech Engine (Desktop 版) と HTTP 経由で通信して音声合成を行います。")
        if (status.notes.isNotEmpty()) {
            AivisSection(title = "ノート") {
                status.notes.forEachIndexed { i, note ->
                    if (i > 0) AivisDivider()
                    AivisKeyValueRow(label = "·", value = note)
                }
            }
        }
    }
}
