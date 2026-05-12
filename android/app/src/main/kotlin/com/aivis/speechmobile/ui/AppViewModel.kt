package com.aivis.speechmobile.ui

import android.content.Context
import android.media.MediaPlayer
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aivis.speechmobile.core.AccentPhrase
import com.aivis.speechmobile.core.AISPProjectDocument
import com.aivis.speechmobile.core.AudioItem
import com.aivis.speechmobile.core.AudioQuery
import com.aivis.speechmobile.core.DefaultStyleID
import com.aivis.speechmobile.core.EngineRuntimeStatus
import com.aivis.speechmobile.core.InstalledModel
import com.aivis.speechmobile.core.ModelInspectionSummary
import com.aivis.speechmobile.core.ModelManifest
import com.aivis.speechmobile.core.ModelRepository
import com.aivis.speechmobile.core.Mora
import com.aivis.speechmobile.core.OutputSamplingRate
import com.aivis.speechmobile.core.Preset
import com.aivis.speechmobile.core.PresetCatalog
import com.aivis.speechmobile.core.SongProject
import com.aivis.speechmobile.core.SpeechEngine
import com.aivis.speechmobile.core.SupportedDevices
import com.aivis.speechmobile.core.TalkProject
import com.aivis.speechmobile.core.UserDictionary
import com.aivis.speechmobile.core.UserDictionaryEntry
import com.aivis.speechmobile.core.VoiceReference
import com.aivis.speechmobile.core.WAVDataConcatenator
import com.aivis.speechmobile.core.storage.AppStorage
import com.aivis.speechmobile.core.storage.FixtureBootstrap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

enum class AppTab(val title: String, val icon: String) {
    TALK("読み上げ", "waveform"),
    MODELS("モデル", "cube_box"),
    PRESETS("プリセット", "sliders"),
    DICTIONARY("辞書", "book"),
    SETTINGS("設定", "settings"),
    HELP("ヘルプ", "help"),
}

data class SpeechStyleOption(
    val speakerID: String,
    val speakerName: String,
    val styleID: Int,
    val styleName: String,
    val modelName: String?,
)

data class AccentMoraEditorItem(
    val phraseIndex: Int,
    val moraIndex: Int,
    val text: String,
    val isHighTone: Boolean,
    val pitch: Double,
    val consonantLength: Double?,
    val vowelLength: Double,
)

data class AccentPhraseEditorItem(
    val phraseIndex: Int,
    val text: String,
    val accent: Int,
    val moraCount: Int,
    val hasPause: Boolean,
    val pauseLength: Double?,
    val moras: List<AccentMoraEditorItem>,
)

data class TalkAudioRow(
    val key: String,
    val lineNumber: Int,
    val text: String,
    val styleID: Int,
    val presetKey: String?,
)

// ── TalkEditorViewModel ──────────────────────────────────────────────────────

class TalkEditorViewModel : ViewModel() {
    private val _project = MutableStateFlow(defaultProject())
    val project: StateFlow<AISPProjectDocument> = _project.asStateFlow()

    private val _selectedAudioKey = MutableStateFlow<String?>(null)

    init {
        _selectedAudioKey.value = _project.value.talk.audioKeys.firstOrNull()
    }

    val selectedAudioKeyFlow: StateFlow<String?> = _selectedAudioKey.asStateFlow()
    val selectedAudioKey: String? get() = _selectedAudioKey.value

    val audioRows: List<TalkAudioRow>
        get() = _project.value.talk.audioKeys.mapIndexedNotNull { idx, key ->
            val item = _project.value.talk.audioItems[key] ?: return@mapIndexedNotNull null
            TalkAudioRow(key = key, lineNumber = idx + 1, text = item.text, styleID = item.voice.styleID, presetKey = item.presetKey)
        }

    val selectedAudioItem: AudioItem?
        get() = selectedAudioKey?.let { _project.value.talk.audioItems[it] }

    val selectedQuery: AudioQuery? get() = selectedAudioItem?.query
    val currentText: String get() = selectedAudioItem?.text ?: ""
    val currentStyleID: Int? get() = selectedAudioItem?.voice?.styleID
    val currentPresetKey: String get() = presetLabel(selectedAudioItem?.presetKey)
    val kanaPreview: String get() = selectedQuery?.kana ?: currentText
    val accentEditorItems: List<AccentPhraseEditorItem>
        get() = selectedQuery?.accentPhrases?.mapIndexed { pIdx, phrase ->
            AccentPhraseEditorItem(
                phraseIndex = pIdx,
                text = phrase.moras.joinToString("") { it.text },
                accent = phrase.accent,
                moraCount = phrase.moras.size,
                hasPause = phrase.pauseMora != null,
                pauseLength = phrase.pauseMora?.vowelLength,
                moras = phrase.moras.mapIndexed { mIdx, mora ->
                    AccentMoraEditorItem(
                        phraseIndex = pIdx,
                        moraIndex = mIdx,
                        text = mora.text,
                        isHighTone = isHighTone(mIdx, phrase.accent),
                        pitch = mora.pitch,
                        consonantLength = mora.consonantLength,
                        vowelLength = mora.vowelLength,
                    )
                },
            )
        } ?: emptyList()

    fun selectAudioKey(key: String) {
        if (_project.value.talk.audioItems[key] != null) {
            _selectedAudioKey.value = key
        }
    }

    fun updateText(value: String): String {
        val texts = splitTextLikeDesktop(value)
        if (texts.size >= 2) {
            putSplitTexts(texts)
            return currentText
        }
        mutateSelectedItem { it.copy(text = value, query = it.query?.copy(kana = value, accentPhrases = emptyList())) }
        return value
    }

    fun addAudioItemAfterSelection() {
        val key = ensureSelectedKey()
        val base = _project.value.talk.audioItems[key]
        val newKey = nextAudioKey()
        _project.value = _project.value.let { doc ->
            val items = doc.talk.audioItems.toMutableMap()
            items[newKey] = audioItemInheriting(text = "", from = base)
            val keys = doc.talk.audioKeys.toMutableList()
            val idx = keys.indexOf(key).takeIf { it >= 0 }?.let { it + 1 } ?: keys.size
            keys.add(idx, newKey)
            doc.copy(talk = doc.talk.copy(audioKeys = keys, audioItems = items))
        }
        _selectedAudioKey.value = newKey
    }

    fun duplicateSelectedAudioItem() {
        val key = selectedAudioKey ?: return
        val item = _project.value.talk.audioItems[key] ?: return
        val newKey = nextAudioKey()
        _project.value = _project.value.let { doc ->
            val items = doc.talk.audioItems.toMutableMap()
            items[newKey] = item
            val keys = doc.talk.audioKeys.toMutableList()
            val idx = keys.indexOf(key).takeIf { it >= 0 }?.let { it + 1 } ?: keys.size
            keys.add(idx, newKey)
            doc.copy(talk = doc.talk.copy(audioKeys = keys, audioItems = items))
        }
        _selectedAudioKey.value = newKey
    }

    fun deleteSelectedAudioItem() {
        val key = selectedAudioKey ?: return
        if (_project.value.talk.audioKeys.size <= 1) return
        val idx = _project.value.talk.audioKeys.indexOf(key).takeIf { it >= 0 } ?: return
        _project.value = _project.value.let { doc ->
            val items = doc.talk.audioItems.toMutableMap()
            items.remove(key)
            val keys = doc.talk.audioKeys.toMutableList()
            keys.removeAt(idx)
            doc.copy(talk = doc.talk.copy(audioKeys = keys, audioItems = items))
        }
        val nextIdx = minOf(idx, _project.value.talk.audioKeys.size - 1)
        _selectedAudioKey.value = _project.value.talk.audioKeys.getOrNull(nextIdx)
    }

    fun moveSelectedAudioItem(offset: Int) {
        val key = selectedAudioKey ?: return
        val keys = _project.value.talk.audioKeys.toMutableList()
        val idx = keys.indexOf(key).takeIf { it >= 0 } ?: return
        val dest = idx + offset
        if (dest !in keys.indices) return
        keys.removeAt(idx)
        keys.add(dest, key)
        _project.value = _project.value.copy(talk = _project.value.talk.copy(audioKeys = keys))
    }

    fun updateSpeedScale(v: Double) = mutateSelectedQuery { it.copy(speedScale = v) }
    fun updateIntonationScale(v: Double) = mutateSelectedQuery { it.copy(intonationScale = v) }
    fun updateTempoDynamicsScale(v: Double) = mutateSelectedQuery { it.copy(tempoDynamicsScale = v) }
    fun updatePitchScale(v: Double) = mutateSelectedQuery { it.copy(pitchScale = v) }
    fun updateVolumeScale(v: Double) = mutateSelectedQuery { it.copy(volumeScale = v) }
    fun updatePauseLengthScale(v: Double) = mutateSelectedQuery { it.copy(pauseLengthScale = v) }
    fun updatePrePhonemeLength(v: Double) = mutateSelectedQuery { it.copy(prePhonemeLength = v) }
    fun updatePostPhonemeLength(v: Double) = mutateSelectedQuery { it.copy(postPhonemeLength = v) }
    fun updateStereo(v: Boolean) = mutateSelectedQuery { it.copy(outputStereo = v) }

    fun updatePhraseAccent(phraseIndex: Int, accent: Int) {
        mutateSelectedQuery { q ->
            val phrases = q.accentPhrases.toMutableList()
            if (phraseIndex !in phrases.indices) return@mutateSelectedQuery q
            val phrase = phrases[phraseIndex]
            val clamped = accent.coerceIn(1, phrase.moras.size)
            phrases[phraseIndex] = phrase.copy(accent = clamped)
            q.copy(accentPhrases = phrases)
        }
    }

    fun movePhraseAccent(phraseIndex: Int, delta: Int) {
        val phrase = selectedQuery?.accentPhrases?.getOrNull(phraseIndex) ?: return
        updatePhraseAccent(phraseIndex, phrase.accent + delta)
    }

    fun splitPhraseAfter(phraseIndex: Int, moraIndex: Int) {
        mutateSelectedQuery { q ->
            val phrases = q.accentPhrases.toMutableList()
            if (phraseIndex !in phrases.indices) return@mutateSelectedQuery q
            val phrase = phrases[phraseIndex]
            val splitAt = moraIndex + 1
            if (splitAt >= phrase.moras.size) return@mutateSelectedQuery q
            val first = AccentPhrase(
                moras = phrase.moras.subList(0, splitAt),
                accent = phrase.accent.coerceIn(1, splitAt),
            )
            val secondMoras = phrase.moras.subList(splitAt, phrase.moras.size)
            val second = AccentPhrase(
                moras = secondMoras,
                accent = if (phrase.accent > splitAt) (phrase.accent - splitAt).coerceIn(1, secondMoras.size) else (secondMoras.size / 2).coerceAtLeast(1),
                pauseMora = phrase.pauseMora,
                isInterrogative = phrase.isInterrogative,
            )
            phrases.removeAt(phraseIndex)
            phrases.add(phraseIndex, first)
            phrases.add(phraseIndex + 1, second)
            q.copy(accentPhrases = phrases)
        }
    }

    fun mergePhraseWithPrevious(phraseIndex: Int) {
        mutateSelectedQuery { q ->
            val phrases = q.accentPhrases.toMutableList()
            if (phraseIndex <= 0 || phraseIndex !in phrases.indices) return@mutateSelectedQuery q
            val prev = phrases[phraseIndex - 1]
            val curr = phrases[phraseIndex]
            val merged = AccentPhrase(
                moras = prev.moras + curr.moras,
                accent = prev.accent.coerceIn(1, (prev.moras + curr.moras).size),
                pauseMora = curr.pauseMora,
                isInterrogative = curr.isInterrogative,
            )
            phrases.removeAt(phraseIndex)
            phrases.removeAt(phraseIndex - 1)
            phrases.add(phraseIndex - 1, merged)
            q.copy(accentPhrases = phrases)
        }
    }

    fun updateMoraPitch(phraseIndex: Int, moraIndex: Int, pitch: Double) {
        mutateMora(phraseIndex, moraIndex) { it.copy(pitch = pitch) }
    }

    fun updateMoraVowelLength(phraseIndex: Int, moraIndex: Int, length: Double) {
        mutateMora(phraseIndex, moraIndex) { it.copy(vowelLength = length) }
    }

    fun updateMoraConsonantLength(phraseIndex: Int, moraIndex: Int, length: Double) {
        mutateMora(phraseIndex, moraIndex) { mora ->
            if (mora.consonantLength != null) mora.copy(consonantLength = length) else mora
        }
    }

    fun updatePauseMoraLength(phraseIndex: Int, length: Double) {
        mutateSelectedQuery { q ->
            val phrases = q.accentPhrases.toMutableList()
            if (phraseIndex !in phrases.indices || phrases[phraseIndex].pauseMora == null) return@mutateSelectedQuery q
            phrases[phraseIndex] = phrases[phraseIndex].copy(
                pauseMora = phrases[phraseIndex].pauseMora!!.copy(vowelLength = length),
            )
            q.copy(accentPhrases = phrases)
        }
    }

    fun useStandardPauseForSelectedLine() {
        mutateSelectedQuery { it.copy(pauseLengthScale = 1.0, prePhonemeLength = 0.1, postPhonemeLength = 0.1) }
    }

    fun useLongerPauseForSelectedLine() {
        mutateSelectedQuery { it.copy(pauseLengthScale = 1.25, prePhonemeLength = 0.15, postPhonemeLength = 0.35) }
    }

    fun updateStyle(option: SpeechStyleOption) {
        mutateSelectedItem { item ->
            item.copy(
                voice = item.voice.copy(speakerID = option.speakerID, styleID = option.styleID),
            )
        }
    }

    fun applyPreset(preset: Preset, key: String) {
        mutateSelectedItem { item ->
            val q = item.query ?: defaultQuery(item.text)
            item.copy(
                query = q.copy(
                    speedScale = preset.speedScale,
                    intonationScale = preset.intonationScale,
                    tempoDynamicsScale = preset.tempoDynamicsScale,
                    pitchScale = preset.pitchScale,
                    volumeScale = preset.volumeScale,
                    pauseLengthScale = preset.pauseLengthScale,
                    prePhonemeLength = preset.prePhonemeLength,
                    postPhonemeLength = preset.postPhonemeLength,
                ),
                presetKey = key,
            )
        }
    }

    fun replaceSelectedQuery(query: AudioQuery, presetKey: String?) {
        val key = selectedAudioKey ?: return
        replaceQuery(query, presetKey, key)
    }

    fun replaceQuery(query: AudioQuery, presetKey: String?, forKey: String) {
        _project.value = _project.value.let { doc ->
            val items = doc.talk.audioItems.toMutableMap()
            val item = items[forKey] ?: return
            items[forKey] = item.copy(
                query = query,
                presetKey = presetKey ?: item.presetKey ?: "manual",
            )
            doc.copy(talk = doc.talk.copy(audioItems = items))
        }
    }

    fun invalidateAllQueries() {
        _project.value = _project.value.let { doc ->
            val items = doc.talk.audioItems.mapValues { (_, item) ->
                val q = item.query ?: return@mapValues item
                item.copy(query = q.copy(accentPhrases = emptyList(), kana = item.text))
            }
            doc.copy(talk = doc.talk.copy(audioItems = items))
        }
    }

    fun presetLabel(key: String?): String = when (key) {
        null -> "手動"
        "manual" -> "手動"
        "default-normal" -> "Normal"
        else -> key
    }

    fun regenerateSelectedQuery(preset: Preset? = null): AudioQuery {
        val item = selectedAudioItem ?: AudioItem(text = "", voice = VoiceReference("", "", 0))
        val query = generatedQuery(item.text, item.query, preset)
        replaceSelectedQuery(query, preset?.let { selectedAudioItem?.presetKey ?: "manual" } ?: selectedAudioItem?.presetKey)
        return query
    }

    private fun mutateSelectedItem(update: (AudioItem) -> AudioItem) {
        val key = ensureSelectedKey()
        _project.value = _project.value.let { doc ->
            val items = doc.talk.audioItems.toMutableMap()
            val item = items[key] ?: return
            items[key] = update(item)
            doc.copy(talk = doc.talk.copy(audioItems = items))
        }
    }

    private fun mutateSelectedQuery(update: (AudioQuery) -> AudioQuery) {
        mutateSelectedItem { item ->
            val q = item.query ?: return@mutateSelectedItem item
            item.copy(query = update(q))
        }
    }

    private fun mutateMora(phraseIndex: Int, moraIndex: Int, update: (Mora) -> Mora) {
        mutateSelectedQuery { q ->
            val phrases = q.accentPhrases.toMutableList()
            if (phraseIndex !in phrases.indices) return@mutateSelectedQuery q
            val moras = phrases[phraseIndex].moras.toMutableList()
            if (moraIndex !in moras.indices) return@mutateSelectedQuery q
            moras[moraIndex] = update(moras[moraIndex])
            phrases[phraseIndex] = phrases[phraseIndex].copy(moras = moras)
            q.copy(accentPhrases = phrases)
        }
    }

    private fun putSplitTexts(texts: List<String>) {
        if (texts.isEmpty()) return
        val selectedKey = ensureSelectedKey()
        val baseItem = _project.value.talk.audioItems[selectedKey]
        var prevKey = selectedKey
        texts.forEachIndexed { idx, text ->
            if (idx == 0) {
                mutateSelectedItem { it.copy(text = text, query = generatedQuery(text, it.query, null)) }
            } else {
                val newKey = nextAudioKey()
                _project.value = _project.value.let { doc ->
                    val items = doc.talk.audioItems.toMutableMap()
                    items[newKey] = audioItemInheriting(text, baseItem ?: _project.value.talk.audioItems[selectedKey])
                    val keys = doc.talk.audioKeys.toMutableList()
                    val insertIdx = keys.indexOf(prevKey).let { if (it >= 0) it + 1 else keys.size }
                    keys.add(insertIdx, newKey)
                    doc.copy(talk = doc.talk.copy(audioKeys = keys, audioItems = items))
                }
                prevKey = newKey
            }
        }
        _selectedAudioKey.value = prevKey
    }

    private fun ensureSelectedKey(): String {
        val key = _selectedAudioKey.value
        if (key != null && _project.value.talk.audioItems[key] != null) return key
        val newKey = nextAudioKey()
        _selectedAudioKey.value = newKey
        _project.value = _project.value.let { doc ->
            val items = doc.talk.audioItems.toMutableMap()
            items[newKey] = audioItemInheriting("", null)
            val keys = doc.talk.audioKeys.toMutableList()
            keys.add(newKey)
            doc.copy(talk = doc.talk.copy(audioKeys = keys, audioItems = items))
        }
        return newKey
    }

    private fun nextAudioKey(): String {
        var idx = _project.value.talk.audioKeys.size + 1
        var key = "audio-$idx"
        while (_project.value.talk.audioItems.containsKey(key)) {
            idx++; key = "audio-$idx"
        }
        return key
    }

    companion object {
        fun isHighTone(moraIndex: Int, accent: Int): Boolean {
            val accentIdx = maxOf(0, accent - 1)
            if (moraIndex == 0 && accentIdx != 0) return false
            return moraIndex <= accentIdx
        }

        fun splitTextLikeDesktop(text: String): List<String> =
            text.split('\n', '\r').map { it.trim() }.filter { it.isNotEmpty() }

        fun defaultQuery(text: String) = AudioQuery(
            accentPhrases = emptyList(),
            speedScale = 1.0,
            intonationScale = 1.0,
            tempoDynamicsScale = 1.0,
            pitchScale = 0.0,
            volumeScale = 1.0,
            pauseLengthScale = 1.0,
            prePhonemeLength = 0.1,
            postPhonemeLength = 0.1,
            outputSamplingRate = OutputSamplingRate.Explicit(44_100),
            outputStereo = false,
            kana = text,
        )

        fun generatedQuery(text: String, existing: AudioQuery?, preset: Preset?): AudioQuery {
            val base = existing ?: defaultQuery(text)
            val matchesText = base.kana?.trim() == text.trim()
            return AudioQuery(
                accentPhrases = if (text.isBlank() || !matchesText) emptyList() else base.accentPhrases,
                speedScale = preset?.speedScale ?: base.speedScale,
                intonationScale = preset?.intonationScale ?: base.intonationScale,
                tempoDynamicsScale = preset?.tempoDynamicsScale ?: base.tempoDynamicsScale,
                pitchScale = preset?.pitchScale ?: base.pitchScale,
                volumeScale = preset?.volumeScale ?: base.volumeScale,
                pauseLengthScale = preset?.pauseLengthScale ?: base.pauseLengthScale,
                prePhonemeLength = preset?.prePhonemeLength ?: base.prePhonemeLength,
                postPhonemeLength = preset?.postPhonemeLength ?: base.postPhonemeLength,
                outputSamplingRate = base.outputSamplingRate,
                outputStereo = base.outputStereo,
                kana = if (text.isBlank()) "" else text,
            )
        }

        private fun audioItemInheriting(text: String, from: AudioItem?): AudioItem {
            val voice = from?.voice ?: VoiceReference(
                FixtureBootstrap.sampleEngineIDStr,
                FixtureBootstrap.sampleSpeakerUUIDStr,
                0,
            )
            return AudioItem(
                text = text,
                voice = voice,
                query = generatedQuery(text, from?.query, null),
                presetKey = from?.presetKey ?: "manual",
            )
        }

        private fun defaultProject(): AISPProjectDocument {
            val voice = VoiceReference(
                FixtureBootstrap.sampleEngineIDStr,
                FixtureBootstrap.sampleSpeakerUUIDStr,
                0,
            )
            val item = AudioItem(text = "", voice = voice, query = defaultQuery(""), presetKey = "default-normal")
            return AISPProjectDocument(
                appVersion = "1.1.0-dev",
                talk = TalkProject(audioKeys = listOf("audio-1"), audioItems = mapOf("audio-1" to item)),
                song = SongProject.empty,
            )
        }
    }
}

// ── ModelManagerViewModel ────────────────────────────────────────────────────

class ModelManagerViewModel(
    initialModels: List<InstalledModel> = FixtureBootstrap.installedModels(),
    val supportedDevices: SupportedDevices = SupportedDevices(),
    val runtimeStatus: EngineRuntimeStatus = EngineRuntimeStatus.previewRoot,
    private val modelRepository: ModelRepository? = null,
) : ViewModel() {
    private val _installedModels = MutableStateFlow(initialModels)
    val installedModels: StateFlow<List<InstalledModel>> = _installedModels.asStateFlow()

    private val _inspections = MutableStateFlow<Map<UUID, ModelInspectionSummary>>(emptyMap())
    val inspections: StateFlow<Map<UUID, ModelInspectionSummary>> = _inspections.asStateFlow()

    private val _busyModelID = MutableStateFlow<UUID?>(null)
    val busyModelID: StateFlow<UUID?> = _busyModelID.asStateFlow()

    private val _statusMessage = MutableStateFlow<String?>(null)
    val statusMessage: StateFlow<String?> = _statusMessage.asStateFlow()

    val activeModel: InstalledModel? get() = _installedModels.value.firstOrNull { it.loadState == InstalledModel.LoadState.ACTIVE }
    val loadedModelCount: Int get() = _installedModels.value.count { it.loadState != InstalledModel.LoadState.INSTALLED }

    fun activateModel(id: UUID) {
        if (_busyModelID.value != null) return
        viewModelScope.launch {
            _busyModelID.value = id
            try {
                if (modelRepository != null) {
                    modelRepository.activateModel(id)
                    _installedModels.value = modelRepository.installedModels()
                } else {
                    _installedModels.value = _installedModels.value.map { m ->
                        when {
                            m.id == id -> m.copy(loadState = InstalledModel.LoadState.ACTIVE)
                            m.loadState == InstalledModel.LoadState.ACTIVE -> m.copy(loadState = InstalledModel.LoadState.LOADED)
                            else -> m
                        }
                    }
                }
                _statusMessage.value = null
            } catch (e: Exception) {
                _statusMessage.value = e.message
            } finally {
                _busyModelID.value = null
            }
        }
    }

    fun loadModel(id: UUID) {
        if (_busyModelID.value != null || modelRepository == null) return
        viewModelScope.launch {
            _busyModelID.value = id
            try {
                modelRepository.loadModel(id)
                _installedModels.value = modelRepository.installedModels()
                _statusMessage.value = null
            } catch (e: Exception) {
                _statusMessage.value = e.message
            } finally {
                _busyModelID.value = null
            }
        }
    }

    fun unloadModel(id: UUID) {
        if (_busyModelID.value != null || modelRepository == null) return
        viewModelScope.launch {
            _busyModelID.value = id
            try {
                modelRepository.unloadModel(id)
                _inspections.value = _inspections.value - id
                _installedModels.value = modelRepository.installedModels()
                _statusMessage.value = null
            } catch (e: Exception) {
                _statusMessage.value = e.message
            } finally {
                _busyModelID.value = null
            }
        }
    }

    fun importModel(context: Context, filePath: String) {
        if (_busyModelID.value != null || modelRepository == null) {
            _statusMessage.value = "モデルリポジトリが接続されていません。"
            return
        }
        viewModelScope.launch {
            _busyModelID.value = UUID.randomUUID()
            try {
                modelRepository.installModel(filePath)
                _installedModels.value = modelRepository.installedModels()
                _statusMessage.value = "モデルを読み込みました。"
            } catch (e: Exception) {
                _statusMessage.value = e.message
            } finally {
                _busyModelID.value = null
            }
        }
    }

    fun refreshFromRepository() {
        if (modelRepository == null) return
        viewModelScope.launch {
            try {
                _installedModels.value = modelRepository.installedModels()
                _statusMessage.value = null
            } catch (e: Exception) {
                _statusMessage.value = e.message
            }
        }
    }

    val seededRepositoryNotice = "同梱シードモデルでリポジトリと ONNX セッションの接続を検証しています。読み上げ出力は必要に応じてプレビュー波形経路を使います。"
}

// ── PresetManagerViewModel ────────────────────────────────────────────────────

class PresetManagerViewModel(
    initialCatalog: PresetCatalog = FixtureBootstrap.presetCatalog(),
    initialDefaultStyles: List<DefaultStyleID> = FixtureBootstrap.defaultStyles(),
) : ViewModel() {
    private val _catalog = MutableStateFlow(initialCatalog)
    val catalog: StateFlow<PresetCatalog> = _catalog.asStateFlow()

    private val _defaultStyles = MutableStateFlow(initialDefaultStyles)
    val defaultStyles: StateFlow<List<DefaultStyleID>> = _defaultStyles.asStateFlow()

    private val _selectedPresetKey = MutableStateFlow<String?>(initialCatalog.keys.firstOrNull())
    val selectedPresetKey: StateFlow<String?> = _selectedPresetKey.asStateFlow()

    val selectedPreset: Preset? get() = _selectedPresetKey.value?.let { _catalog.value.items[it] }

    fun selectPresetKey(key: String) {
        _selectedPresetKey.value = key
    }
}

// ── DictionaryManagerViewModel ────────────────────────────────────────────────

class DictionaryManagerViewModel(
    initialDictionary: UserDictionary = FixtureBootstrap.userDictionary(),
    private val onDictionaryChanged: (() -> Unit)? = null,
    private val storage: AppStorage? = null,
) : ViewModel() {
    private val _dictionary = MutableStateFlow(initialDictionary)
    val dictionary: StateFlow<UserDictionary> = _dictionary.asStateFlow()

    private val _searchText = MutableStateFlow("")
    val searchText: StateFlow<String> = _searchText.asStateFlow()

    private val _editingEntryID = MutableStateFlow<String?>(null)
    val editingEntryID: StateFlow<String?> = _editingEntryID.asStateFlow()

    private val _editorSurface = MutableStateFlow("")
    val editorSurface: StateFlow<String> = _editorSurface.asStateFlow()

    private val _editorPronunciation = MutableStateFlow("")
    val editorPronunciation: StateFlow<String> = _editorPronunciation.asStateFlow()

    private val _editorAccentType = MutableStateFlow(1)
    val editorAccentType: StateFlow<Int> = _editorAccentType.asStateFlow()

    private val _editorWordType = MutableStateFlow(UserDictionaryEntry.WordType.PROPER_NOUN)
    val editorWordType: StateFlow<UserDictionaryEntry.WordType> = _editorWordType.asStateFlow()

    private val _editorPriority = MutableStateFlow(5)
    val editorPriority: StateFlow<Int> = _editorPriority.asStateFlow()

    private val _statusMessage = MutableStateFlow<String?>(null)
    val statusMessage: StateFlow<String?> = _statusMessage.asStateFlow()

    val isEditingExistingEntry: Boolean get() = _editingEntryID.value != null

    val filteredEntries: List<UserDictionaryEntry>
        get() {
            val q = _searchText.value
            if (q.isEmpty()) return _dictionary.value.entries
            return _dictionary.value.entries.filter { it.surface.contains(q, true) || it.pronunciation.contains(q, true) }
        }

    val editorMoraCount: Int get() = previewMoraTexts(_editorPronunciation.value).size.coerceAtLeast(1)
    val editorAccentRange: IntRange get() = 1..editorMoraCount.coerceAtLeast(1)

    fun setSearchText(text: String) { _searchText.value = text }
    fun setEditorSurface(v: String) { _editorSurface.value = v }
    fun setEditorPronunciation(v: String) { _editorPronunciation.value = v }
    fun setEditorWordType(v: UserDictionaryEntry.WordType) { _editorWordType.value = v }
    fun setEditorPriority(v: Int) { _editorPriority.value = v }
    fun updateEditorAccentType(v: Int) { _editorAccentType.value = v.coerceIn(editorAccentRange) }

    fun beginAddingEntry() {
        _editingEntryID.value = null
        _editorSurface.value = ""
        _editorPronunciation.value = ""
        _editorAccentType.value = 1
        _editorWordType.value = UserDictionaryEntry.WordType.PROPER_NOUN
        _editorPriority.value = 5
        _statusMessage.value = null
    }

    fun beginEditing(entry: UserDictionaryEntry) {
        _editingEntryID.value = entry.id
        _editorSurface.value = entry.surface
        _editorPronunciation.value = entry.pronunciation
        _editorAccentType.value = entry.accentType
        _editorWordType.value = entry.wordType
        _editorPriority.value = entry.priority
        _statusMessage.value = null
    }

    fun cancelEditing() { beginAddingEntry() }

    fun saveEditingEntry() {
        val surface = _editorSurface.value.trim()
        val pronunciation = _editorPronunciation.value.trim()
        if (surface.isEmpty()) { _statusMessage.value = "表記を入力してください。"; return }
        if (pronunciation.isEmpty()) { _statusMessage.value = "読みを入力してください。"; return }
        val moraCount = previewMoraTexts(pronunciation).size.coerceAtLeast(1)
        val accent = _editorAccentType.value.coerceIn(1, moraCount)
        val entry = UserDictionaryEntry(
            id = _editingEntryID.value ?: UUID.randomUUID().toString(),
            surface = surface,
            pronunciation = pronunciation,
            accentType = accent,
            wordType = _editorWordType.value,
            priority = _editorPriority.value.coerceIn(0, 10),
        )
        val entries = _dictionary.value.entries.toMutableList()
        val existingIdx = entries.indexOfFirst { it.id == entry.id }
        val message: String
        if (existingIdx >= 0) {
            entries[existingIdx] = entry
            message = "辞書を更新しました。"
        } else {
            entries.add(entry)
            message = "辞書に追加しました。"
        }
        entries.sortWith(compareByDescending<UserDictionaryEntry> { it.priority }.thenBy { it.surface })
        _dictionary.value = UserDictionary(entries)
        _statusMessage.value = message
        persistDictionary()
        beginEditing(entry)
    }

    fun deleteEditingEntry() {
        val id = _editingEntryID.value ?: run { _statusMessage.value = "削除する単語を選択してください。"; return }
        val entries = _dictionary.value.entries.toMutableList()
        val idx = entries.indexOfFirst { it.id == id }
        if (idx < 0) { _statusMessage.value = "削除する単語を選択してください。"; return }
        entries.removeAt(idx)
        _dictionary.value = UserDictionary(entries)
        _statusMessage.value = "辞書から削除しました。"
        persistDictionary()
        beginAddingEntry()
    }

    private fun persistDictionary() {
        viewModelScope.launch {
            storage?.saveUserDictionary(_dictionary.value)
            onDictionaryChanged?.invoke()
        }
    }

    companion object {
        fun previewMoraTexts(pronunciation: String): List<String> {
            val smallKana = setOf("ャ", "ュ", "ョ", "ァ", "ィ", "ゥ", "ェ", "ォ")
            val chars = pronunciation.filter { it != ' ' && it != '　' }.map { it.toString() }
            val moras = mutableListOf<String>()
            var i = 0
            while (i < chars.size) {
                val c = chars[i]
                if (c.isBlank()) { i++; continue }
                if (i + 1 < chars.size && smallKana.contains(chars[i + 1])) {
                    moras.add(c + chars[i + 1]); i += 2
                } else {
                    moras.add(c); i++
                }
            }
            return moras
        }

        fun isHighTone(moraIndex: Int, accent: Int): Boolean {
            val a = (accent - 1).coerceAtLeast(0)
            if (moraIndex == 0 && a != 0) return false
            return moraIndex <= a
        }
    }
}

// ── SettingsViewModel ──────────────────────────────────────────────────────────

class SettingsViewModel(
    val runtimeStatus: EngineRuntimeStatus = EngineRuntimeStatus.previewRoot,
    val summary: String = "端末上のランタイム初期化は有効です。",
    private val storage: AppStorage? = null,
) : ViewModel() {
    private val _remoteEngineEnabled = MutableStateFlow(false)
    val remoteEngineEnabled: StateFlow<Boolean> = _remoteEngineEnabled.asStateFlow()

    private val _remoteEngineURLString = MutableStateFlow("")
    val remoteEngineURLString: StateFlow<String> = _remoteEngineURLString.asStateFlow()

    init {
        viewModelScope.launch {
            _remoteEngineEnabled.value = storage?.remoteEngineEnabled() ?: false
            _remoteEngineURLString.value = storage?.remoteEngineURL() ?: ""
        }
    }

    fun setRemoteEngineEnabled(enabled: Boolean) {
        _remoteEngineEnabled.value = enabled
        viewModelScope.launch { storage?.setRemoteEngineEnabled(enabled) }
    }

    fun setRemoteEngineURLString(url: String) {
        _remoteEngineURLString.value = url
        viewModelScope.launch { storage?.setRemoteEngineURL(url) }
    }
}

// ── HelpViewModel ──────────────────────────────────────────────────────────────

class HelpViewModel(
    val summary: String = "読み上げを中心にしたモバイルシェルです。iOS と Android 互換に向けてランタイム層を分離し、ネイティブ Style-Bert-VITS2 の入口を接続しています。",
) : ViewModel()

// ── AppViewModel (coordinator) ────────────────────────────────────────────────

class AppViewModel(
    private val storage: AppStorage?,
    private val speechEngine: SpeechEngine? = null,
    private val modelRepository: ModelRepository? = null,
) : ViewModel() {

    private val _selectedTab = MutableStateFlow(AppTab.TALK)
    val selectedTab: StateFlow<AppTab> = _selectedTab.asStateFlow()

    val talkEditor = TalkEditorViewModel()
    val modelManager = ModelManagerViewModel(modelRepository = modelRepository)
    val presetManager = PresetManagerViewModel(
        initialCatalog = FixtureBootstrap.presetCatalog(),
        initialDefaultStyles = FixtureBootstrap.defaultStyles(),
    )
    val dictionaryManager = DictionaryManagerViewModel(
        initialDictionary = FixtureBootstrap.userDictionary(),
        onDictionaryChanged = { talkEditor.invalidateAllQueries() },
        storage = storage,
    )
    val settingsViewModel = SettingsViewModel(storage = storage)
    val helpViewModel = HelpViewModel()

    private val _talkActionStatusMessage = MutableStateFlow<String?>(null)
    val talkActionStatusMessage: StateFlow<String?> = _talkActionStatusMessage.asStateFlow()

    private val _isTalkActionRunning = MutableStateFlow(false)
    val isTalkActionRunning: StateFlow<Boolean> = _isTalkActionRunning.asStateFlow()

    private val _exportedWAVPath = MutableStateFlow<String?>(null)
    val exportedWAVPath: StateFlow<String?> = _exportedWAVPath.asStateFlow()

    private val _exportedWAVByteCount = MutableStateFlow(0)
    val exportedWAVByteCount: StateFlow<Int> = _exportedWAVByteCount.asStateFlow()

    private val _isPreviewPlaying = MutableStateFlow(false)
    val isPreviewPlaying: StateFlow<Boolean> = _isPreviewPlaying.asStateFlow()

    private val _playbackCurrentTime = MutableStateFlow(0f)
    val playbackCurrentTime: StateFlow<Float> = _playbackCurrentTime.asStateFlow()

    private val _playbackDuration = MutableStateFlow(0f)
    val playbackDuration: StateFlow<Float> = _playbackDuration.asStateFlow()

    private var mediaPlayer: MediaPlayer? = null
    private var playbackTimerJob: Job? = null
    private var autoQueryJob: Job? = null

    init {
        val firstPresetKey = presetManager.catalog.value.keys.firstOrNull()
        val firstPreset = firstPresetKey?.let { presetManager.catalog.value.items[it] }
        if (firstPreset != null && firstPresetKey != null) {
            talkEditor.applyPreset(firstPreset, firstPresetKey)
            presetManager.selectPresetKey(firstPresetKey)
        }
    }

    fun selectTab(tab: AppTab) { _selectedTab.value = tab }

    val talkStyleOptions: List<SpeechStyleOption>
        get() {
            val selectedVoice = talkEditor.selectedAudioItem?.voice
            val fallbackSpeakerID = selectedVoice?.speakerID ?: ""
            val activeModel = modelManager.activeModel
            val manifestOptions = activeModel?.manifest?.speakers?.flatMap { speaker ->
                speaker.styles.map { style ->
                    SpeechStyleOption(
                        speakerID = speaker.uuid.toString(),
                        speakerName = speaker.name,
                        styleID = style.localID,
                        styleName = style.name,
                        modelName = activeModel.name,
                    )
                }
            } ?: emptyList()
            val descriptorOptions = activeModel?.manifest?.runtimeDescriptor?.styleProfiles?.map { style ->
                SpeechStyleOption(
                    speakerID = fallbackSpeakerID,
                    speakerName = activeModel.manifest?.speakers?.firstOrNull()?.name ?: "選択中の話者",
                    styleID = style.localID,
                    styleName = style.name,
                    modelName = activeModel.name,
                )
            } ?: emptyList()
            val options = if (manifestOptions.isNotEmpty()) manifestOptions else descriptorOptions
            if (selectedVoice == null) return options
            val hasMatch = options.any { it.speakerID == selectedVoice.speakerID && it.styleID == selectedVoice.styleID }
                || options.any { it.styleID == selectedVoice.styleID }
            if (hasMatch) return options
            return listOf(
                SpeechStyleOption(
                    speakerID = selectedVoice.speakerID,
                    speakerName = "現在の話者",
                    styleID = selectedVoice.styleID,
                    styleName = if (selectedVoice.styleID == 0) "Normal" else "Style ID ${selectedVoice.styleID}",
                    modelName = null,
                ),
            ) + options
        }

    fun selectTalkStyle(option: SpeechStyleOption) {
        talkEditor.updateStyle(option)
        clearPreviewArtifact()
        _talkActionStatusMessage.value = "${option.styleName} に切り替えました。"
    }

    fun updateTalkText(text: String) {
        val selected = talkEditor.updateText(text)
        clearPreviewArtifact()
        _talkActionStatusMessage.value = null
        scheduleAutoQueryRefresh(selected)
    }

    fun updateTalkPhraseAccent(phraseIndex: Int, accent: Int) {
        talkEditor.updatePhraseAccent(phraseIndex, accent)
        clearPreviewArtifact()
    }

    fun moveTalkPhraseAccent(phraseIndex: Int, delta: Int) {
        talkEditor.movePhraseAccent(phraseIndex, delta)
        clearPreviewArtifact()
    }

    fun splitTalkPhraseAfter(phraseIndex: Int, moraIndex: Int) {
        talkEditor.splitPhraseAfter(phraseIndex, moraIndex)
        clearPreviewArtifact()
    }

    fun mergeTalkPhraseWithPrevious(phraseIndex: Int) {
        talkEditor.mergePhraseWithPrevious(phraseIndex)
        clearPreviewArtifact()
    }

    fun regenerateTalkQuery() {
        viewModelScope.launch { doRegenerateTalkQuery() }
    }

    fun testSynthesis(context: Context) {
        viewModelScope.launch { exportCurrentTalkWAV(context, "preview", autoplay = true) }
    }

    fun exportTalkWAV(context: Context) {
        viewModelScope.launch { exportCurrentTalkWAV(context, "export") }
    }

    fun exportAllTalkWAV(context: Context) {
        viewModelScope.launch { doExportAllTalkWAV(context) }
    }

    fun togglePreviewPlayback() {
        if (_isPreviewPlaying.value) {
            stopPreviewPlayback()
            _talkActionStatusMessage.value = "プレビュー再生を停止しました。"
        } else {
            startPreviewPlayback()
        }
    }

    fun seekPreview(positionMs: Int) {
        mediaPlayer?.seekTo(positionMs)
        _playbackCurrentTime.value = positionMs / 1000f
    }

    val exportedWAVByteCountLabel: String?
        get() {
            val c = _exportedWAVByteCount.value
            if (c <= 0) return null
            return when {
                c >= 1_048_576 -> "%.1f MB".format(c / 1_048_576f)
                c >= 1024 -> "%.1f KB".format(c / 1024f)
                else -> "$c bytes"
            }
        }

    val playbackCurrentTimeLabel: String
        get() = formatTime(_playbackCurrentTime.value)

    val playbackDurationLabel: String
        get() = formatTime(_playbackDuration.value)

    private fun formatTime(seconds: Float): String {
        val totalSec = seconds.toInt()
        return "%d:%02d".format(totalSec / 60, totalSec % 60)
    }

    private suspend fun doRegenerateTalkQuery() {
        if (_isTalkActionRunning.value) return
        autoQueryJob?.cancel()
        val text = talkEditor.currentText.trim()
        if (text.isEmpty()) { _talkActionStatusMessage.value = "テキストを入力してください。"; return }
        _isTalkActionRunning.value = true
        try {
            val query = if (speechEngine != null && talkEditor.selectedAudioItem != null) {
                speechEngine.makeAudioQuery(text, talkEditor.selectedAudioItem!!.voice.styleID)
            } else {
                talkEditor.regenerateSelectedQuery(presetManager.selectedPreset)
            }
            talkEditor.replaceSelectedQuery(query, presetManager.selectedPresetKey.value)
            clearPreviewArtifact()
            _talkActionStatusMessage.value = "AudioQuery を更新しました。"
        } catch (e: Exception) {
            _talkActionStatusMessage.value = e.message
        } finally {
            _isTalkActionRunning.value = false
        }
    }

    private fun scheduleAutoQueryRefresh(text: String) {
        autoQueryJob?.cancel()
        if (text.isBlank() || speechEngine == null) return
        autoQueryJob = viewModelScope.launch {
            delay(550)
            if (talkEditor.currentText.trim() != text) return@launch
            val item = talkEditor.selectedAudioItem ?: return@launch
            val q = item.query
            if (q != null && q.kana?.trim() == text && q.accentPhrases.isNotEmpty()) return@launch
            if (_isTalkActionRunning.value) return@launch
            _isTalkActionRunning.value = true
            try {
                val regenerated = speechEngine.makeAudioQuery(text, item.voice.styleID)
                if (talkEditor.currentText.trim() != text) return@launch
                val prev = talkEditor.selectedAudioItem?.query
                val merged = queryPreservingControls(regenerated, prev)
                talkEditor.replaceSelectedQuery(merged, presetManager.selectedPresetKey.value)
                clearPreviewArtifact()
                _talkActionStatusMessage.value = "AudioQuery を自動更新しました。"
            } catch (e: Exception) {
                if (talkEditor.currentText.trim() == text) _talkActionStatusMessage.value = e.message
            } finally {
                _isTalkActionRunning.value = false
            }
        }
    }

    private suspend fun exportCurrentTalkWAV(context: Context, prefix: String, autoplay: Boolean = false) {
        if (_isTalkActionRunning.value) return
        val item = talkEditor.selectedAudioItem
        if (item == null || item.text.isBlank()) {
            _talkActionStatusMessage.value = "合成するテキストを入力してください。"
            return
        }
        _isTalkActionRunning.value = true
        try {
            val query = ensuredQuery(item)
            val wavData = synthesizeWAV(query, item.voice.styleID)
            val dir = File(context.cacheDir, "AivisSpeechExports").also { it.mkdirs() }
            val fileName = "$prefix-${talkEditor.selectedAudioKey ?: "selected"}-${UUID.randomUUID().toString().take(8)}.wav"
            val outFile = File(dir, fileName)
            withContext(Dispatchers.IO) { outFile.writeBytes(wavData) }
            stopPreviewPlayback()
            _exportedWAVPath.value = outFile.absolutePath
            _exportedWAVByteCount.value = wavData.size
            refreshPlaybackMetadata(outFile.absolutePath)
            _talkActionStatusMessage.value = "WAVを生成しました: ${outFile.name}"
            if (autoplay) startPreviewPlayback()
        } catch (e: Exception) {
            _talkActionStatusMessage.value = e.message
        } finally {
            _isTalkActionRunning.value = false
        }
    }

    private suspend fun doExportAllTalkWAV(context: Context) {
        if (_isTalkActionRunning.value) return
        val rows = talkEditor.project.value.talk.audioKeys
            .mapNotNull { key -> talkEditor.project.value.talk.audioItems[key]?.takeIf { it.text.isNotBlank() }?.let { key to it } }
        if (rows.isEmpty()) { _talkActionStatusMessage.value = "書き出すテキスト行がありません。"; return }
        _isTalkActionRunning.value = true
        try {
            val wavs = rows.map { (key, item) ->
                val q = ensuredQueryForKey(key, item)
                synthesizeWAV(q, item.voice.styleID)
            }
            val merged = WAVDataConcatenator.concatenate(wavs)
            val dir = File(context.cacheDir, "AivisSpeechExports").also { it.mkdirs() }
            val outFile = File(dir, "all-talk-${UUID.randomUUID().toString().take(8)}.wav")
            withContext(Dispatchers.IO) { outFile.writeBytes(merged) }
            stopPreviewPlayback()
            _exportedWAVPath.value = outFile.absolutePath
            _exportedWAVByteCount.value = merged.size
            refreshPlaybackMetadata(outFile.absolutePath)
            _talkActionStatusMessage.value = "全行WAVを生成しました: ${outFile.name}"
        } catch (e: Exception) {
            _talkActionStatusMessage.value = e.message
        } finally {
            _isTalkActionRunning.value = false
        }
    }

    private suspend fun ensuredQuery(item: AudioItem): AudioQuery {
        val key = talkEditor.selectedAudioKey ?: return makeCurrentQuery(item)
        return ensuredQueryForKey(key, item)
    }

    private suspend fun ensuredQueryForKey(key: String, item: AudioItem): AudioQuery {
        val q = item.query
        if (q != null && q.kana?.trim() == item.text.trim() && q.accentPhrases.isNotEmpty()) return q
        val generated = makeCurrentQuery(item)
        talkEditor.replaceQuery(generated, item.presetKey, key)
        return generated
    }

    private suspend fun makeCurrentQuery(item: AudioItem): AudioQuery {
        val regenerated = if (speechEngine != null) {
            speechEngine.makeAudioQuery(item.text, item.voice.styleID)
        } else {
            TalkEditorViewModel.defaultQuery(item.text)
        }
        return queryPreservingControls(regenerated, item.query)
    }

    private suspend fun synthesizeWAV(query: AudioQuery, styleID: Int): ByteArray {
        val engine = speechEngine ?: throw IllegalStateException("音声合成ランタイムが接続されていません。")
        return engine.synthesize(query, styleID)
    }

    private fun queryPreservingControls(regenerated: AudioQuery, prev: AudioQuery?): AudioQuery {
        prev ?: return regenerated
        return regenerated.copy(
            speedScale = prev.speedScale,
            intonationScale = prev.intonationScale,
            tempoDynamicsScale = prev.tempoDynamicsScale,
            pitchScale = prev.pitchScale,
            volumeScale = prev.volumeScale,
            pauseLengthScale = prev.pauseLengthScale,
            prePhonemeLength = prev.prePhonemeLength,
            postPhonemeLength = prev.postPhonemeLength,
            outputSamplingRate = prev.outputSamplingRate,
            outputStereo = prev.outputStereo,
        )
    }

    private fun clearPreviewArtifact() {
        stopPreviewPlayback()
        _exportedWAVPath.value = null
        _exportedWAVByteCount.value = 0
        _playbackCurrentTime.value = 0f
        _playbackDuration.value = 0f
    }

    private fun startPreviewPlayback() {
        val path = _exportedWAVPath.value ?: run {
            _talkActionStatusMessage.value = "先にWAVプレビューを生成してください。"
            return
        }
        try {
            mediaPlayer?.release()
            val mp = MediaPlayer().apply {
                setDataSource(path)
                prepare()
                setOnCompletionListener {
                    _isPreviewPlaying.value = false
                    stopPlaybackTimer()
                    _playbackCurrentTime.value = _playbackDuration.value
                }
            }
            mp.start()
            mediaPlayer = mp
            _playbackDuration.value = mp.duration / 1000f
            _isPreviewPlaying.value = true
            startPlaybackTimer()
            _talkActionStatusMessage.value = "プレビュー再生を開始しました。"
        } catch (e: Exception) {
            _talkActionStatusMessage.value = e.message
        }
    }

    private fun stopPreviewPlayback() {
        mediaPlayer?.apply { if (isPlaying) stop(); release() }
        mediaPlayer = null
        _isPreviewPlaying.value = false
        stopPlaybackTimer()
    }

    private fun refreshPlaybackMetadata(path: String) {
        try {
            val mp = MediaPlayer().apply { setDataSource(path); prepare() }
            _playbackDuration.value = mp.duration / 1000f
            _playbackCurrentTime.value = 0f
            mp.release()
        } catch (_: Exception) {
            _playbackDuration.value = 0f
            _playbackCurrentTime.value = 0f
        }
    }

    private fun startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimerJob = viewModelScope.launch {
            while (true) {
                delay(200)
                val mp = mediaPlayer ?: break
                _playbackCurrentTime.value = mp.currentPosition / 1000f
                _playbackDuration.value = mp.duration / 1000f
            }
        }
    }

    private fun stopPlaybackTimer() {
        playbackTimerJob?.cancel()
        playbackTimerJob = null
    }

    override fun onCleared() {
        super.onCleared()
        mediaPlayer?.release()
        mediaPlayer = null
    }
}
