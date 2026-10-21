package com.aivis.speechmobile.core

import java.util.UUID

data class EngineRuntimeStatus(
    val providerName: String,
    val availability: Availability,
    val preferredExecutionProvider: String,
    val linkedVersion: String? = null,
    val nnApiAvailable: Boolean = false,
    val notes: List<String> = emptyList(),
) {
    enum class Availability { LINKED, UNAVAILABLE }

    companion object {
        val previewRoot = EngineRuntimeStatus(
            providerName = "プレビューランタイム",
            availability = Availability.UNAVAILABLE,
            preferredExecutionProvider = "CPU (ONNX Runtime 準備中)",
            linkedVersion = null,
            nnApiAvailable = false,
            notes = listOf("ランタイムはまだ注入されていません"),
        )
    }
}

data class SupportedDevices(
    val cpu: Boolean = true,
    val gpu: Boolean = false,
    val nnApiPreferred: Boolean = false,
)

data class ModelStyle(
    val localID: Int,
    val name: String,
)

data class ModelSpeaker(
    val uuid: UUID,
    val name: String,
    val styles: List<ModelStyle>,
)

data class ModelStyleRuntimeMetadata(
    val localID: Int,
    val name: String,
    val vectorDimension: Int? = null,
    val notes: List<String> = emptyList(),
)

data class ModelVectorRuntimeMetadata(
    val key: String,
    val dimension: Int,
    val associatedStyleIDs: List<Int> = emptyList(),
    val notes: List<String> = emptyList(),
)

data class ModelHyperParameterMetadata(
    val speedScale: Double? = null,
    val intonationScale: Double? = null,
    val tempoDynamicsScale: Double? = null,
    val pitchScale: Double? = null,
    val volumeScale: Double? = null,
    val pauseLengthScale: Double? = null,
    val prePhonemeLength: Double? = null,
    val postPhonemeLength: Double? = null,
    val outputSamplingRate: Int? = null,
    val outputStereo: Boolean? = null,
)

data class ModelRuntimeDescriptor(
    val styleProfiles: List<ModelStyleRuntimeMetadata> = emptyList(),
    val vectorProfiles: List<ModelVectorRuntimeMetadata> = emptyList(),
    val hyperParameters: ModelHyperParameterMetadata = ModelHyperParameterMetadata(),
    val notes: List<String> = emptyList(),
) {
    val availableStyleIDs: List<Int> get() = styleProfiles.map { it.localID }
}

data class ModelManifest(
    val uuid: UUID,
    val name: String,
    val version: String,
    val modelArchitecture: String,
    val modelFormat: String,
    val speakers: List<ModelSpeaker>,
    val runtimeDescriptor: ModelRuntimeDescriptor? = null,
)

data class InstalledModel(
    val id: UUID,
    val name: String,
    val version: String,
    val sourceURL: String? = null,
    val loadState: LoadState = LoadState.INSTALLED,
    val localFilePath: String? = null,
    val lastLoadedAt: Long? = null,
    val manifest: ModelManifest? = null,
) {
    enum class LoadState { INSTALLED, LOADED, ACTIVE }
}

interface SpeechEngine {
    suspend fun supportedDevices(): SupportedDevices
    suspend fun makeAudioQuery(text: String, styleID: Int): AudioQuery
    suspend fun synthesize(query: AudioQuery, styleID: Int): ByteArray
}

interface ModelRepository {
    suspend fun installedModels(): List<InstalledModel>
    suspend fun installModel(filePath: String): InstalledModel
    suspend fun installModel(remoteURL: String, isRemote: Boolean): InstalledModel
    suspend fun updateModel(id: UUID): InstalledModel
    suspend fun loadModel(id: UUID)
    suspend fun activateModel(id: UUID)
    suspend fun unloadModel(id: UUID)
    suspend fun removeModel(id: UUID)
}

data class ModelInspectionSummary(
    val inputNames: List<String>,
    val outputNames: List<String>,
    val inspectedAt: Long = System.currentTimeMillis(),
    val executionProvider: String? = null,
)

interface InspectableModelRepository : ModelRepository {
    suspend fun inspection(id: UUID): ModelInspectionSummary
}

interface ProjectStore {
    suspend fun loadProject(filePath: String): AISPProjectDocument
    suspend fun saveProject(project: AISPProjectDocument, filePath: String)
}

interface DictionaryStore {
    suspend fun loadDictionary(): UserDictionary
    suspend fun saveDictionary(dictionary: UserDictionary)
}

interface PresetStore {
    suspend fun loadPresetCatalog(): PresetCatalog
    suspend fun savePresetCatalog(catalog: PresetCatalog)
    suspend fun loadDefaultStyles(): List<DefaultStyleID>
    suspend fun saveDefaultStyles(styles: List<DefaultStyleID>)
}
