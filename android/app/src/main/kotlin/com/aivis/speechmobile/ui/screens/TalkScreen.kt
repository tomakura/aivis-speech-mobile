package com.aivis.speechmobile.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.ArrowDropDown
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.automirrored.rounded.MergeType
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Save
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aivis.speechmobile.ui.AccentMoraEditorItem
import com.aivis.speechmobile.ui.AccentPhraseEditorItem
import com.aivis.speechmobile.ui.AppViewModel
import com.aivis.speechmobile.ui.SpeechStyleOption
import com.aivis.speechmobile.ui.TalkAudioRow
import com.aivis.speechmobile.ui.components.AivisDivider
import com.aivis.speechmobile.ui.components.AivisNotice
import com.aivis.speechmobile.ui.components.AivisSection
import com.aivis.speechmobile.ui.components.LabeledSlider
import com.aivis.speechmobile.ui.theme.LocalAivisColors

@Composable
fun TalkScreen(appViewModel: AppViewModel) {
    val talkEditor = appViewModel.talkEditor
    @Suppress("UNUSED_VARIABLE")
    val project by talkEditor.project.collectAsStateWithLifecycle()
    val selectedKey by talkEditor.selectedAudioKeyFlow.collectAsStateWithLifecycle()
    val isBusy by appViewModel.isTalkActionRunning.collectAsStateWithLifecycle()
    val statusMessage by appViewModel.talkActionStatusMessage.collectAsStateWithLifecycle()
    val exportedPath by appViewModel.exportedWAVPath.collectAsStateWithLifecycle()
    val isPlaying by appViewModel.isPreviewPlaying.collectAsStateWithLifecycle()
    val currentTime by appViewModel.playbackCurrentTime.collectAsStateWithLifecycle()
    val duration by appViewModel.playbackDuration.collectAsStateWithLifecycle()
    @Suppress("UNUSED_VARIABLE")
    val installedModels by appViewModel.modelManager.installedModels.collectAsStateWithLifecycle()

    val audioRows = talkEditor.audioRows
    val selectedItem = talkEditor.selectedAudioItem
    val selectedQuery = talkEditor.selectedQuery
    val accentEditorItems = talkEditor.accentEditorItems
    val styleOptions = appViewModel.talkStyleOptions

    val context = LocalContext.current
    val colors = LocalAivisColors.current

    Column(modifier = Modifier.fillMaxSize().background(colors.background)) {
        // ── Audio row list (upper panel) ──────────────────────────────────────
        LazyColumn(
            modifier = Modifier.weight(0.38f).fillMaxWidth().background(colors.secondarySurface),
            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            items(audioRows, key = { it.key }) { row ->
                AudioRowCard(
                    row = row,
                    isSelected = row.key == selectedKey,
                    onClick = { talkEditor.selectAudioKey(row.key) },
                )
            }
            item {
                OutlinedButton(
                    onClick = { talkEditor.addAudioItemAfterSelection() },
                    modifier = Modifier.fillMaxWidth().height(36.dp),
                    contentPadding = PaddingValues(horizontal = 8.dp),
                ) {
                    Icon(Icons.Rounded.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("行を追加", style = MaterialTheme.typography.labelMedium)
                }
            }
        }

        HorizontalDivider(color = colors.border, thickness = 0.5.dp)

        // ── Selected item editor (lower panel, scrollable) ────────────────────
        Column(
            modifier = Modifier.weight(0.62f).fillMaxWidth().verticalScroll(rememberScrollState()),
        ) {
            if (selectedItem != null) {
                // Style + text
                StyleAndTextSection(
                    selectedItem = selectedItem,
                    styleOptions = styleOptions,
                    onStyleSelected = { appViewModel.selectTalkStyle(it) },
                    onTextChange = { appViewModel.updateTalkText(it) },
                    currentText = talkEditor.currentText,
                    selectedKey = selectedKey,
                )

                // Line controls row
                LineControlsRow(
                    onMoveUp = { talkEditor.moveSelectedAudioItem(-1) },
                    onMoveDown = { talkEditor.moveSelectedAudioItem(1) },
                    onDuplicate = { talkEditor.duplicateSelectedAudioItem() },
                    onDelete = { talkEditor.deleteSelectedAudioItem() },
                    canDelete = audioRows.size > 1,
                )

                HorizontalDivider(color = colors.border, thickness = 0.5.dp)

                // Action buttons
                ActionButtonsRow(
                    isBusy = isBusy,
                    hasExport = exportedPath != null,
                    isPlaying = isPlaying,
                    onSynthesize = { appViewModel.testSynthesis(context) },
                    onExport = { appViewModel.exportTalkWAV(context) },
                    onExportAll = { appViewModel.exportAllTalkWAV(context) },
                    onRegenerate = { appViewModel.regenerateTalkQuery() },
                    onTogglePlay = { appViewModel.togglePreviewPlayback() },
                )

                // Playback slider (shown when WAV is exported)
                if (exportedPath != null) {
                    PlaybackSliderRow(
                        currentTime = currentTime,
                        duration = duration,
                        isPlaying = isPlaying,
                        currentTimeLabel = appViewModel.playbackCurrentTimeLabel,
                        durationLabel = appViewModel.playbackDurationLabel,
                        byteCountLabel = appViewModel.exportedWAVByteCountLabel,
                        onSeek = { appViewModel.seekPreview((it * 1000).toInt()) },
                    )
                }

                HorizontalDivider(color = colors.border, thickness = 0.5.dp)

                // Parameter sliders
                ParameterSlidersSection(
                    query = selectedQuery,
                    onSpeedChange = { talkEditor.updateSpeedScale(it.toDouble()) },
                    onIntonationChange = { talkEditor.updateIntonationScale(it.toDouble()) },
                    onTempoChange = { talkEditor.updateTempoDynamicsScale(it.toDouble()) },
                    onPitchChange = { talkEditor.updatePitchScale(it.toDouble()) },
                    onVolumeChange = { talkEditor.updateVolumeScale(it.toDouble()) },
                    onPauseChange = { talkEditor.updatePauseLengthScale(it.toDouble()) },
                    onPrePhonemeChange = { talkEditor.updatePrePhonemeLength(it.toDouble()) },
                    onPostPhonemeChange = { talkEditor.updatePostPhonemeLength(it.toDouble()) },
                )

                // Accent phrase editor (shown when query has phrases)
                if (accentEditorItems.isNotEmpty()) {
                    HorizontalDivider(color = colors.border, thickness = 0.5.dp)
                    AccentPhrasesSection(
                        items = accentEditorItems,
                        kanaPreview = talkEditor.kanaPreview,
                        onAccentChange = { phraseIdx, accent ->
                            appViewModel.updateTalkPhraseAccent(phraseIdx, accent)
                        },
                        onMoveAccent = { phraseIdx, delta ->
                            appViewModel.moveTalkPhraseAccent(phraseIdx, delta)
                        },
                        onSplitAfter = { phraseIdx, moraIdx ->
                            appViewModel.splitTalkPhraseAfter(phraseIdx, moraIdx)
                        },
                        onMergeWithPrev = { phraseIdx ->
                            appViewModel.mergeTalkPhraseWithPrevious(phraseIdx)
                        },
                    )
                }

                Spacer(Modifier.height(80.dp))
            } else {
                Box(
                    modifier = Modifier.fillMaxWidth().padding(48.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "行を選択してください。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = colors.mutedText,
                    )
                }
            }
        }

        // ── Status bar ────────────────────────────────────────────────────────
        if (statusMessage != null) {
            Surface(
                color = colors.accentMuted,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = statusMessage!!,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

// ── Private composables ────────────────────────────────────────────────────────

@Composable
private fun AudioRowCard(row: TalkAudioRow, isSelected: Boolean, onClick: () -> Unit) {
    val colors = LocalAivisColors.current
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(8.dp),
        color = if (isSelected) colors.accentMuted else colors.surface,
        modifier = Modifier.fillMaxWidth().then(
            if (isSelected) Modifier.border(1.dp, colors.accent, RoundedCornerShape(8.dp)) else Modifier,
        ),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "${row.lineNumber}",
                style = MaterialTheme.typography.labelSmall,
                color = if (isSelected) colors.accent else colors.mutedText,
                modifier = Modifier.width(22.dp),
            )
            Spacer(Modifier.width(6.dp))
            Text(
                text = row.text.ifEmpty { "（空）" },
                style = MaterialTheme.typography.bodySmall,
                color = if (row.text.isEmpty()) colors.mutedText else MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun StyleAndTextSection(
    selectedItem: com.aivis.speechmobile.core.AudioItem,
    styleOptions: List<SpeechStyleOption>,
    onStyleSelected: (SpeechStyleOption) -> Unit,
    onTextChange: (String) -> Unit,
    currentText: String,
    selectedKey: String?,
) {
    val colors = LocalAivisColors.current
    var styleMenuExpanded by remember { mutableStateOf(false) }
    var textValue by remember(selectedKey) { mutableStateOf(currentText) }

    Column(modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
        // Style selector
        Row(verticalAlignment = Alignment.CenterVertically) {
            val currentStyle = styleOptions.firstOrNull { it.styleID == selectedItem.voice.styleID }
            Box {
                OutlinedButton(
                    onClick = { styleMenuExpanded = true },
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                    modifier = Modifier.height(32.dp),
                ) {
                    Text(
                        text = currentStyle?.let { "${it.speakerName} / ${it.styleName}" } ?: "スタイル選択",
                        style = MaterialTheme.typography.labelSmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Spacer(Modifier.width(2.dp))
                    Icon(Icons.Rounded.ArrowDropDown, contentDescription = null, modifier = Modifier.size(16.dp))
                }
                DropdownMenu(
                    expanded = styleMenuExpanded,
                    onDismissRequest = { styleMenuExpanded = false },
                ) {
                    styleOptions.forEach { option ->
                        DropdownMenuItem(
                            text = {
                                Column {
                                    Text(option.styleName, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold)
                                    Text(
                                        "${option.speakerName}${option.modelName?.let { " · $it" } ?: ""}",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = colors.mutedText,
                                    )
                                }
                            },
                            onClick = {
                                onStyleSelected(option)
                                styleMenuExpanded = false
                            },
                        )
                    }
                }
            }
            Spacer(Modifier.width(8.dp))
            Text(
                text = selectedItem.presetKey?.let { if (it == "manual") "手動" else it } ?: "手動",
                style = MaterialTheme.typography.labelSmall,
                color = colors.mutedText,
            )
        }

        Spacer(Modifier.height(6.dp))

        // Text field
        OutlinedTextField(
            value = textValue,
            onValueChange = { newText ->
                onTextChange(newText)
                textValue = newText
            },
            placeholder = { Text("読み上げテキストを入力", style = MaterialTheme.typography.bodySmall) },
            minLines = 3,
            maxLines = 6,
            modifier = Modifier.fillMaxWidth(),
            textStyle = MaterialTheme.typography.bodyMedium,
        )
    }
}

@Composable
private fun LineControlsRow(
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onDuplicate: () -> Unit,
    onDelete: () -> Unit,
    canDelete: Boolean,
) {
    val colors = LocalAivisColors.current
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(0.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onMoveUp, modifier = Modifier.size(36.dp)) {
            Icon(Icons.Rounded.KeyboardArrowUp, contentDescription = "上へ移動", modifier = Modifier.size(20.dp), tint = colors.mutedText)
        }
        IconButton(onClick = onMoveDown, modifier = Modifier.size(36.dp)) {
            Icon(Icons.Rounded.KeyboardArrowDown, contentDescription = "下へ移動", modifier = Modifier.size(20.dp), tint = colors.mutedText)
        }
        IconButton(onClick = onDuplicate, modifier = Modifier.size(36.dp)) {
            Icon(Icons.Rounded.ContentCopy, contentDescription = "複製", modifier = Modifier.size(18.dp), tint = colors.mutedText)
        }
        IconButton(onClick = onDelete, enabled = canDelete, modifier = Modifier.size(36.dp)) {
            Icon(Icons.Rounded.Delete, contentDescription = "削除", modifier = Modifier.size(18.dp), tint = if (canDelete) colors.warning else colors.border)
        }
    }
}

@Composable
private fun ActionButtonsRow(
    isBusy: Boolean,
    hasExport: Boolean,
    isPlaying: Boolean,
    onSynthesize: () -> Unit,
    onExport: () -> Unit,
    onExportAll: () -> Unit,
    onRegenerate: () -> Unit,
    onTogglePlay: () -> Unit,
) {
    val colors = LocalAivisColors.current
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (isBusy) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), color = colors.accent, strokeWidth = 2.dp)
            Spacer(Modifier.width(4.dp))
        }
        Button(
            onClick = onSynthesize,
            enabled = !isBusy,
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
            modifier = Modifier.height(34.dp),
        ) {
            Icon(Icons.Rounded.PlayArrow, contentDescription = null, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(3.dp))
            Text("合成", style = MaterialTheme.typography.labelMedium)
        }
        OutlinedButton(
            onClick = onRegenerate,
            enabled = !isBusy,
            contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp),
            modifier = Modifier.height(34.dp),
        ) {
            Icon(Icons.Rounded.Refresh, contentDescription = null, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(3.dp))
            Text("Query更新", style = MaterialTheme.typography.labelMedium)
        }
        OutlinedButton(
            onClick = onExport,
            enabled = !isBusy,
            contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp),
            modifier = Modifier.height(34.dp),
        ) {
            Icon(Icons.Rounded.Save, contentDescription = null, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(3.dp))
            Text("WAV", style = MaterialTheme.typography.labelMedium)
        }
        if (hasExport) {
            OutlinedButton(
                onClick = onTogglePlay,
                contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp),
                modifier = Modifier.height(34.dp),
            ) {
                Icon(
                    if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = colors.accent,
                )
            }
        }
    }
}

@Composable
private fun PlaybackSliderRow(
    currentTime: Float,
    duration: Float,
    isPlaying: Boolean,
    currentTimeLabel: String,
    durationLabel: String,
    byteCountLabel: String?,
    onSeek: (Float) -> Unit,
) {
    val colors = LocalAivisColors.current
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 2.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(currentTimeLabel, style = MaterialTheme.typography.labelSmall, color = colors.mutedText)
            if (byteCountLabel != null) {
                Text(byteCountLabel, style = MaterialTheme.typography.labelSmall, color = colors.mutedText)
            }
            Text(durationLabel, style = MaterialTheme.typography.labelSmall, color = colors.mutedText)
        }
        if (duration > 0f) {
            Slider(
                value = currentTime.coerceIn(0f, duration),
                onValueChange = onSeek,
                valueRange = 0f..duration,
                colors = SliderDefaults.colors(
                    thumbColor = colors.accent,
                    activeTrackColor = colors.accent,
                    inactiveTrackColor = colors.border,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun ParameterSlidersSection(
    query: com.aivis.speechmobile.core.AudioQuery?,
    onSpeedChange: (Float) -> Unit,
    onIntonationChange: (Float) -> Unit,
    onTempoChange: (Float) -> Unit,
    onPitchChange: (Float) -> Unit,
    onVolumeChange: (Float) -> Unit,
    onPauseChange: (Float) -> Unit,
    onPrePhonemeChange: (Float) -> Unit,
    onPostPhonemeChange: (Float) -> Unit,
) {
    val speed = query?.speedScale?.toFloat() ?: 1.0f
    val intonation = query?.intonationScale?.toFloat() ?: 1.0f
    val tempo = query?.tempoDynamicsScale?.toFloat() ?: 1.0f
    val pitch = query?.pitchScale?.toFloat() ?: 0.0f
    val volume = query?.volumeScale?.toFloat() ?: 1.0f
    val pause = query?.pauseLengthScale?.toFloat() ?: 1.0f
    val pre = query?.prePhonemeLength?.toFloat() ?: 0.1f
    val post = query?.postPhonemeLength?.toFloat() ?: 0.1f

    Column(modifier = Modifier.padding(vertical = 4.dp)) {
        LabeledSlider(label = "話速", value = speed, onValueChange = onSpeedChange, valueRange = 0.5f..2.0f, displayValue = "%.2f".format(speed))
        AivisDivider()
        LabeledSlider(label = "イントネーション", value = intonation, onValueChange = onIntonationChange, valueRange = 0.0f..2.0f, displayValue = "%.2f".format(intonation))
        AivisDivider()
        LabeledSlider(label = "テンポゆらぎ", value = tempo, onValueChange = onTempoChange, valueRange = 0.0f..2.0f, displayValue = "%.2f".format(tempo))
        AivisDivider()
        LabeledSlider(label = "ピッチ", value = pitch, onValueChange = onPitchChange, valueRange = -0.15f..0.15f, displayValue = "%.2f".format(pitch))
        AivisDivider()
        LabeledSlider(label = "音量", value = volume, onValueChange = onVolumeChange, valueRange = 0.0f..2.0f, displayValue = "%.2f".format(volume))
        AivisDivider()
        LabeledSlider(label = "無音長スケール", value = pause, onValueChange = onPauseChange, valueRange = 0.0f..2.0f, displayValue = "%.2f".format(pause))
        AivisDivider()
        LabeledSlider(label = "開始無音 (秒)", value = pre, onValueChange = onPrePhonemeChange, valueRange = 0.0f..1.5f, displayValue = "%.2f".format(pre))
        AivisDivider()
        LabeledSlider(label = "終端無音 (秒)", value = post, onValueChange = onPostPhonemeChange, valueRange = 0.0f..1.5f, displayValue = "%.2f".format(post))
    }
}

@Composable
private fun AccentPhrasesSection(
    items: List<AccentPhraseEditorItem>,
    kanaPreview: String,
    onAccentChange: (Int, Int) -> Unit,
    onMoveAccent: (Int, Int) -> Unit,
    onSplitAfter: (Int, Int) -> Unit,
    onMergeWithPrev: (Int) -> Unit,
) {
    val colors = LocalAivisColors.current
    Column(modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
        Text(
            text = "アクセント編集",
            style = MaterialTheme.typography.labelSmall,
            color = colors.mutedText,
            modifier = Modifier.padding(start = 4.dp, bottom = 6.dp),
        )
        if (kanaPreview.isNotEmpty()) {
            Text(
                text = kanaPreview,
                style = MaterialTheme.typography.bodySmall,
                color = colors.mutedText,
                modifier = Modifier.padding(bottom = 8.dp),
            )
        }
        items.forEach { item ->
            AccentPhraseRow(
                item = item,
                onMoveAccent = { delta -> onMoveAccent(item.phraseIndex, delta) },
                onSplitAfter = { moraIdx -> onSplitAfter(item.phraseIndex, moraIdx) },
                onMergeWithPrev = { onMergeWithPrev(item.phraseIndex) },
            )
            if (item.phraseIndex < items.size - 1) {
                Spacer(Modifier.height(8.dp))
                HorizontalDivider(color = colors.border, thickness = 0.5.dp)
                Spacer(Modifier.height(8.dp))
            }
        }
    }
}

@Composable
private fun AccentPhraseRow(
    item: AccentPhraseEditorItem,
    onMoveAccent: (Int) -> Unit,
    onSplitAfter: (Int) -> Unit,
    onMergeWithPrev: () -> Unit,
) {
    val colors = LocalAivisColors.current
    Column {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "フレーズ ${item.phraseIndex + 1}",
                style = MaterialTheme.typography.labelSmall,
                color = colors.mutedText,
            )
            if (item.phraseIndex > 0) {
                Spacer(Modifier.width(6.dp))
                Surface(
                    onClick = onMergeWithPrev,
                    shape = RoundedCornerShape(4.dp),
                    color = colors.secondarySurface,
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.AutoMirrored.Rounded.MergeType, contentDescription = null, modifier = Modifier.size(12.dp), tint = colors.mutedText)
                        Spacer(Modifier.width(2.dp))
                        Text("結合", style = MaterialTheme.typography.labelSmall, color = colors.mutedText)
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            Text(
                text = "型: ${item.accent}",
                style = MaterialTheme.typography.labelSmall,
                color = colors.mutedText,
            )
            IconButton(onClick = { onMoveAccent(-1) }, modifier = Modifier.size(28.dp)) {
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowLeft, contentDescription = "アクセント-", modifier = Modifier.size(18.dp), tint = colors.accent)
            }
            IconButton(onClick = { onMoveAccent(1) }, modifier = Modifier.size(28.dp)) {
                Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = "アクセント+", modifier = Modifier.size(18.dp), tint = colors.accent)
            }
        }
        Spacer(Modifier.height(4.dp))
        LazyRow(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            itemsIndexed(item.moras) { moraIdx, mora ->
                MoraTile(
                    mora = mora,
                    onClick = { onSplitAfter(moraIdx) },
                )
            }
        }
        if (item.hasPause) {
            Spacer(Modifier.height(4.dp))
            Surface(
                shape = RoundedCornerShape(4.dp),
                color = colors.secondarySurface,
            ) {
                Text(
                    text = "ポーズ ${"%.2f".format(item.pauseLength ?: 0.0)}秒",
                    style = MaterialTheme.typography.labelSmall,
                    color = colors.mutedText,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                )
            }
        }
    }
}

@Composable
private fun MoraTile(mora: AccentMoraEditorItem, onClick: () -> Unit) {
    val colors = LocalAivisColors.current
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(4.dp),
        color = if (mora.isHighTone) colors.accentMuted else colors.secondarySurface,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(
                modifier = Modifier
                    .width(34.dp)
                    .height(5.dp)
                    .background(
                        if (mora.isHighTone) colors.accent else colors.border,
                        RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp),
                    ),
            )
            Text(
                text = mora.text,
                style = MaterialTheme.typography.bodySmall,
                color = if (mora.isHighTone) colors.accent else MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.padding(horizontal = 5.dp, vertical = 3.dp),
            )
        }
    }
}
