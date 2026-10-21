package com.aivis.speechmobile.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aivis.speechmobile.core.UserDictionaryEntry
import com.aivis.speechmobile.ui.DictionaryManagerViewModel
import com.aivis.speechmobile.ui.components.AivisDivider
import com.aivis.speechmobile.ui.components.AivisNotice
import com.aivis.speechmobile.ui.components.AivisScrollableScreen
import com.aivis.speechmobile.ui.components.AivisSection
import com.aivis.speechmobile.ui.theme.LocalAivisColors

@Composable
fun DictionaryScreen(viewModel: DictionaryManagerViewModel) {
    val dictionary by viewModel.dictionary.collectAsStateWithLifecycle()
    val searchText by viewModel.searchText.collectAsStateWithLifecycle()
    val editingEntryID by viewModel.editingEntryID.collectAsStateWithLifecycle()
    val editorSurface by viewModel.editorSurface.collectAsStateWithLifecycle()
    val editorPronunciation by viewModel.editorPronunciation.collectAsStateWithLifecycle()
    val editorAccentType by viewModel.editorAccentType.collectAsStateWithLifecycle()
    val editorWordType by viewModel.editorWordType.collectAsStateWithLifecycle()
    val editorPriority by viewModel.editorPriority.collectAsStateWithLifecycle()
    val statusMessage by viewModel.statusMessage.collectAsStateWithLifecycle()
    val colors = LocalAivisColors.current

    val filteredEntries = viewModel.filteredEntries
    val moraTexts = DictionaryManagerViewModel.previewMoraTexts(editorPronunciation)
    val moraCount = moraTexts.size.coerceAtLeast(1)

    AivisScrollableScreen(
        title = "辞書",
        actions = {
            Surface(
                onClick = { viewModel.beginAddingEntry() },
                shape = RoundedCornerShape(8.dp),
                color = colors.accent,
            ) {
                Icon(
                    imageVector = Icons.Rounded.Add,
                    contentDescription = "追加",
                    tint = androidx.compose.ui.graphics.Color.White,
                    modifier = Modifier.padding(8.dp).size(20.dp),
                )
            }
        },
    ) {
        OutlinedTextField(
            value = searchText,
            onValueChange = { viewModel.setSearchText(it) },
            placeholder = { Text("表記・読みで検索") },
            leadingIcon = { Icon(Icons.Rounded.Search, contentDescription = null) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp),
        )

        if (statusMessage != null) {
            AivisNotice(body = statusMessage!!)
        }

        AivisSection(title = "単語一覧 (${filteredEntries.size})") {
            if (filteredEntries.isEmpty()) {
                Text(
                    text = if (searchText.isEmpty()) "辞書に登録された単語はありません。" else "検索結果はありません。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.mutedText,
                    modifier = Modifier.padding(16.dp),
                )
            } else {
                filteredEntries.forEachIndexed { i, entry ->
                    if (i > 0) AivisDivider()
                    val isEditing = entry.id == editingEntryID
                    Surface(
                        onClick = { viewModel.beginEditing(entry) },
                        color = if (isEditing) colors.accentMuted else colors.surface,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = entry.surface,
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.SemiBold,
                                    color = if (isEditing) colors.accent else MaterialTheme.colorScheme.onSurface,
                                )
                                Text(
                                    text = "${entry.pronunciation}  アクセント: ${entry.accentType}  優先度: ${entry.priority}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = colors.mutedText,
                                )
                            }
                            WordTypeBadge(wordType = entry.wordType)
                        }
                    }
                }
            }
        }

        // Editor section (visible when adding or editing)
        AivisSection(title = if (viewModel.isEditingExistingEntry) "単語を編集" else "単語を追加") {
            // Surface text
            Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                Text("表記", style = MaterialTheme.typography.labelSmall, color = colors.mutedText)
                Spacer(Modifier.height(4.dp))
                OutlinedTextField(
                    value = editorSurface,
                    onValueChange = { viewModel.setEditorSurface(it) },
                    placeholder = { Text("例: AivisSpeech") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            AivisDivider()

            // Pronunciation
            Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                Text("読み（カタカナ）", style = MaterialTheme.typography.labelSmall, color = colors.mutedText)
                Spacer(Modifier.height(4.dp))
                OutlinedTextField(
                    value = editorPronunciation,
                    onValueChange = { viewModel.setEditorPronunciation(it) },
                    placeholder = { Text("例: アイビススピーチ") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // Mora preview with accent visualization
            if (moraTexts.isNotEmpty()) {
                AivisDivider()
                Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("アクセント型", style = MaterialTheme.typography.labelSmall, color = colors.mutedText)
                        Text("$editorAccentType / $moraCount", style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium)
                    }
                    Spacer(Modifier.height(4.dp))
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        itemsIndexed(moraTexts) { idx, mora ->
                            val isHigh = DictionaryManagerViewModel.isHighTone(idx, editorAccentType)
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Box(
                                    modifier = Modifier
                                        .width(32.dp)
                                        .height(6.dp)
                                        .background(
                                            if (isHigh) colors.accent else colors.border,
                                            RoundedCornerShape(2.dp),
                                        ),
                                )
                                Spacer(Modifier.height(2.dp))
                                Surface(
                                    color = if (isHigh) colors.accentMuted else colors.secondarySurface,
                                    shape = RoundedCornerShape(4.dp),
                                ) {
                                    Text(
                                        text = mora,
                                        style = MaterialTheme.typography.bodySmall,
                                        modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
                                    )
                                }
                            }
                        }
                    }
                    Spacer(Modifier.height(4.dp))
                    Slider(
                        value = editorAccentType.toFloat(),
                        onValueChange = { viewModel.updateEditorAccentType(it.toInt()) },
                        valueRange = 1f..moraCount.toFloat().coerceAtLeast(1f),
                        steps = (moraCount - 2).coerceAtLeast(0),
                        colors = SliderDefaults.colors(
                            thumbColor = colors.accent,
                            activeTrackColor = colors.accent,
                        ),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }

            AivisDivider()

            // Word type selector
            Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                Text("品詞", style = MaterialTheme.typography.labelSmall, color = colors.mutedText)
                Spacer(Modifier.height(6.dp))
                LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    val types = UserDictionaryEntry.WordType.values()
                    items(types.size) { i ->
                        val wt = types[i]
                        FilterChip(
                            selected = editorWordType == wt,
                            onClick = { viewModel.setEditorWordType(wt) },
                            label = { Text(wordTypeLabel(wt), style = MaterialTheme.typography.labelSmall) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = colors.accentMuted,
                                selectedLabelColor = colors.accent,
                            ),
                        )
                    }
                }
            }

            AivisDivider()

            // Priority slider
            Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("優先度", style = MaterialTheme.typography.labelSmall, color = colors.mutedText)
                    Text("$editorPriority", style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium)
                }
                Slider(
                    value = editorPriority.toFloat(),
                    onValueChange = { viewModel.setEditorPriority(it.toInt()) },
                    valueRange = 0f..10f,
                    steps = 9,
                    colors = SliderDefaults.colors(
                        thumbColor = colors.accent,
                        activeTrackColor = colors.accent,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // Save / Delete buttons
            AivisDivider()
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Button(
                    onClick = { viewModel.saveEditingEntry() },
                    colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
                    modifier = Modifier.weight(1f),
                ) {
                    Text(if (viewModel.isEditingExistingEntry) "更新" else "追加")
                }
                if (viewModel.isEditingExistingEntry) {
                    OutlinedButton(
                        onClick = { viewModel.deleteEditingEntry() },
                        modifier = Modifier.weight(1f),
                    ) {
                        Text("削除")
                    }
                }
                OutlinedButton(
                    onClick = { viewModel.cancelEditing() },
                ) {
                    Text("キャンセル")
                }
            }
        }

        AivisNotice(body = "辞書に登録した単語は、次回の AudioQuery 生成から読み上げに反映されます。カタカナで読みを入力し、アクセント型を設定してください。")
    }
}

@Composable
private fun WordTypeBadge(wordType: UserDictionaryEntry.WordType) {
    val colors = LocalAivisColors.current
    Surface(
        shape = RoundedCornerShape(4.dp),
        color = colors.accentMuted,
    ) {
        Text(
            text = wordTypeLabel(wordType),
            style = MaterialTheme.typography.labelSmall,
            color = colors.accent,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

private fun wordTypeLabel(wordType: UserDictionaryEntry.WordType): String = when (wordType) {
    UserDictionaryEntry.WordType.PROPER_NOUN -> "固有名詞"
    UserDictionaryEntry.WordType.COMMON_NOUN -> "一般名詞"
    UserDictionaryEntry.WordType.VERB -> "動詞"
    UserDictionaryEntry.WordType.ADJECTIVE -> "形容詞"
    UserDictionaryEntry.WordType.SUFFIX -> "語尾"
}
