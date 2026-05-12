package com.aivis.speechmobile.ui.screens

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aivis.speechmobile.ui.PresetManagerViewModel
import com.aivis.speechmobile.ui.components.AivisDivider
import com.aivis.speechmobile.ui.components.AivisNotice
import com.aivis.speechmobile.ui.components.AivisScrollableScreen
import com.aivis.speechmobile.ui.components.AivisSection
import com.aivis.speechmobile.ui.theme.LocalAivisColors

@Composable
fun PresetsScreen(viewModel: PresetManagerViewModel) {
    val catalog by viewModel.catalog.collectAsStateWithLifecycle()
    val selectedKey by viewModel.selectedPresetKey.collectAsStateWithLifecycle()
    val colors = LocalAivisColors.current

    AivisScrollableScreen(title = "プリセット") {
        AivisSection(title = "プリセット一覧 (${catalog.keys.size})") {
            if (catalog.keys.isEmpty()) {
                Text(
                    text = "プリセットはありません。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.mutedText,
                    modifier = Modifier.padding(16.dp),
                )
            } else {
                catalog.keys.forEachIndexed { i, key ->
                    val preset = catalog.items[key] ?: return@forEachIndexed
                    val isSelected = key == selectedKey
                    if (i > 0) AivisDivider()
                    Surface(
                        onClick = { viewModel.selectPresetKey(key) },
                        color = if (isSelected) colors.accentMuted else colors.surface,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = preset.name,
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.SemiBold,
                                    color = if (isSelected) colors.accent else MaterialTheme.colorScheme.onSurface,
                                )
                                Spacer(Modifier.height(2.dp))
                                Text(
                                    text = "速度 ${"%.2f".format(preset.speedScale)}  " +
                                        "イントネーション ${"%.2f".format(preset.intonationScale)}  " +
                                        "音量 ${"%.2f".format(preset.volumeScale)}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = colors.mutedText,
                                )
                            }
                            if (isSelected) {
                                Spacer(Modifier.width(8.dp))
                                Icon(
                                    imageVector = Icons.Rounded.Check,
                                    contentDescription = "選択中",
                                    tint = colors.accent,
                                    modifier = Modifier.size(20.dp),
                                )
                            }
                        }
                    }
                }
            }
        }

        if (selectedKey != null) {
            val preset = catalog.items[selectedKey]
            if (preset != null) {
                AivisSection(title = "選択中プリセットの詳細") {
                    AivisDivider()
                    listOf(
                        "話速" to "%.2f".format(preset.speedScale),
                        "イントネーション" to "%.2f".format(preset.intonationScale),
                        "テンポゆらぎ" to "%.2f".format(preset.tempoDynamicsScale),
                        "ピッチ" to "%.2f".format(preset.pitchScale),
                        "音量" to "%.2f".format(preset.volumeScale),
                        "無音長スケール" to "%.2f".format(preset.pauseLengthScale),
                        "開始無音" to "%.2f".format(preset.prePhonemeLength),
                        "終端無音" to "%.2f".format(preset.postPhonemeLength),
                    ).forEachIndexed { i, (label, value) ->
                        if (i > 0) AivisDivider()
                        androidx.compose.material3.ListItem(
                            headlineContent = { Text(label) },
                            trailingContent = { Text(value, color = colors.mutedText) },
                        )
                    }
                }
            }
        }

        AivisNotice(body = "プリセットは読み上げタブで各行に適用できます。デスクトップ版 AivisSpeech のプリセット名と互換性があります。")
    }
}
