package com.aivis.speechmobile.core.engine

import com.aivis.speechmobile.core.AccentPhrase
import com.aivis.speechmobile.core.AudioQuery
import com.aivis.speechmobile.core.InstalledModel
import com.aivis.speechmobile.core.ModelStyleRuntimeMetadata
import com.aivis.speechmobile.core.Mora
import com.aivis.speechmobile.core.OutputSamplingRate
import com.aivis.speechmobile.core.SpeechEngine
import com.aivis.speechmobile.core.SupportedDevices
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit

class RemoteAivisSpeechEngine(
    private val baseUrl: String,
    private val client: OkHttpClient = defaultClient(),
) : SpeechEngine {

    private val json = Json { ignoreUnknownKeys = true }

    override suspend fun supportedDevices() = SupportedDevices(cpu = true, gpu = true)

    override suspend fun makeAudioQuery(text: String, styleID: Int): AudioQuery {
        val data = post(endpoint = "audio_query", speaker = styleID, text = text, body = null)
        return json.decodeFromString<RemoteAudioQueryPayload>(String(data)).toAudioQuery()
    }

    override suspend fun synthesize(query: AudioQuery, styleID: Int): ByteArray {
        val payload = RemoteAudioQueryPayload.from(query)
        val bodyJson = json.encodeToString(payload)
        return post(endpoint = "synthesis", speaker = styleID, text = null, body = bodyJson)
    }

    suspend fun resolveStyleID(localStyleID: Int, activeModel: InstalledModel?): Int {
        val speakers = speakers()
        if (speakers.flatMap { it.styles }.any { it.id == localStyleID }) {
            return localStyleID
        }
        val remoteSpeaker = activeModel?.let { findRemoteSpeaker(it, speakers) }
            ?: throw RemoteEngineException.styleMappingFailed(localStyleID, activeModel?.name)

        val localStyleName = localStyleName(localStyleID, activeModel)
        remoteSpeaker.styles.firstOrNull { it.name == localStyleName }?.let { return it.id }

        val sortedLocalStyles = localStyles(activeModel).sortedBy { it.localID }
        val localIndex = sortedLocalStyles.indexOfFirst { it.localID == localStyleID }
        if (localIndex >= 0 && localIndex < remoteSpeaker.styles.size) {
            return remoteSpeaker.styles[localIndex].id
        }
        if (localStyleID >= 0 && localStyleID < remoteSpeaker.styles.size) {
            return remoteSpeaker.styles[localStyleID].id
        }
        throw RemoteEngineException.styleMappingFailed(localStyleID, activeModel?.name)
    }

    private suspend fun speakers(): List<RemoteSpeakerPayload> {
        val data = get("speakers")
        return json.decodeFromString(String(data))
    }

    private fun get(endpoint: String): ByteArray {
        val url = "$baseUrl/$endpoint".toHttpUrlOrNull()
            ?: throw RemoteEngineException.invalidEndpoint(endpoint)
        val request = Request.Builder().url(url).get().build()
        return execute(request, endpoint)
    }

    private fun post(endpoint: String, speaker: Int, text: String?, body: String?): ByteArray {
        val urlBuilder = "$baseUrl/$endpoint".toHttpUrlOrNull()
            ?.newBuilder()
            ?.addQueryParameter("speaker", speaker.toString())
            ?: throw RemoteEngineException.invalidEndpoint(endpoint)
        if (text != null) urlBuilder.addQueryParameter("text", text)
        val url = urlBuilder.build()
        val requestBody = body?.toRequestBody("application/json".toMediaType())
        val request = Request.Builder()
            .url(url)
            .post(requestBody ?: "".toRequestBody("application/json".toMediaType()))
            .build()
        return execute(request, endpoint)
    }

    private fun execute(request: Request, endpoint: String): ByteArray {
        val response = client.newCall(request).execute()
        val bytes = response.use { it.body?.bytes() ?: ByteArray(0) }
        if (!response.isSuccessful) {
            val body = String(bytes)
            throw RemoteEngineException.requestFailed(endpoint, response.code, body)
        }
        return bytes
    }

    private fun findRemoteSpeaker(model: InstalledModel, speakers: List<RemoteSpeakerPayload>): RemoteSpeakerPayload? {
        val activeName = model.name.trim().lowercase()
        return speakers.firstOrNull { it.name.trim().lowercase() == activeName }
            ?: speakers.firstOrNull {
                val c = it.name.trim().lowercase()
                activeName.contains(c) || c.contains(activeName)
            }
    }

    private fun localStyles(model: InstalledModel): List<ModelStyleRuntimeMetadata> {
        val styleProfiles = model.manifest?.runtimeDescriptor?.styleProfiles
        if (!styleProfiles.isNullOrEmpty()) return styleProfiles
        return model.manifest?.speakers?.flatMap { speaker ->
            speaker.styles.map { ModelStyleRuntimeMetadata(localID = it.localID, name = it.name) }
        } ?: emptyList()
    }

    private fun localStyleName(localStyleID: Int, model: InstalledModel): String? =
        localStyles(model).firstOrNull { it.localID == localStyleID }?.name

    companion object {
        private fun defaultClient() = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .build()
    }
}

sealed class RemoteEngineException(message: String) : IOException(message) {
    companion object {
        fun invalidBaseURL(url: String) = InvalidBaseURL("AivisSpeech Engine URL が正しくありません: $url")
        fun invalidEndpoint(ep: String) = InvalidEndpoint("エンドポイント URL を作成できません: $ep")
        fun requestFailed(ep: String, code: Int, body: String) =
            RequestFailed("AivisSpeech Engine $ep が失敗しました。HTTP $code: ${body.ifEmpty { "レスポンス本文なし" }}")
        fun styleMappingFailed(id: Int, modelName: String?) =
            StyleMappingFailed("スタイルIDへ変換できませんでした。model=${modelName ?: "未確定"}, localStyleID=$id")
    }

    class InvalidBaseURL(msg: String) : RemoteEngineException(msg)
    class InvalidEndpoint(msg: String) : RemoteEngineException(msg)
    class RequestFailed(msg: String) : RemoteEngineException(msg)
    class StyleMappingFailed(msg: String) : RemoteEngineException(msg)
}

@Serializable
internal data class RemoteSpeakerPayload(
    val name: String,
    @SerialName("speaker_uuid") val speakerUUID: String,
    val styles: List<RemoteSpeakerStylePayload>,
)

@Serializable
internal data class RemoteSpeakerStylePayload(
    val name: String,
    val id: Int,
    val type: String? = null,
)

@Serializable
internal data class RemoteMoraPayload(
    val text: String,
    val consonant: String? = null,
    @SerialName("consonant_length") val consonantLength: Double? = null,
    val vowel: String,
    @SerialName("vowel_length") val vowelLength: Double,
    val pitch: Double,
) {
    fun toMora() = Mora(
        text = text,
        consonant = consonant,
        consonantLength = consonantLength,
        vowel = vowel,
        vowelLength = vowelLength,
        pitch = pitch,
    )

    companion object {
        fun from(mora: Mora) = RemoteMoraPayload(
            text = mora.text,
            consonant = mora.consonant,
            consonantLength = mora.consonantLength,
            vowel = mora.vowel,
            vowelLength = mora.vowelLength,
            pitch = mora.pitch,
        )
    }
}

@Serializable
internal data class RemoteAccentPhrasePayload(
    val moras: List<RemoteMoraPayload>,
    val accent: Int,
    @SerialName("pause_mora") val pauseMora: RemoteMoraPayload? = null,
    @SerialName("is_interrogative") val isInterrogative: Boolean = false,
) {
    fun toAccentPhrase() = AccentPhrase(
        moras = moras.map { it.toMora() },
        accent = accent,
        pauseMora = pauseMora?.toMora(),
        isInterrogative = isInterrogative,
    )

    companion object {
        fun from(phrase: AccentPhrase) = RemoteAccentPhrasePayload(
            moras = phrase.moras.map { RemoteMoraPayload.from(it) },
            accent = phrase.accent,
            pauseMora = phrase.pauseMora?.let { RemoteMoraPayload.from(it) },
            isInterrogative = phrase.isInterrogative ?: false,
        )
    }
}

@Serializable
internal data class RemoteAudioQueryPayload(
    @SerialName("accent_phrases") val accentPhrases: List<RemoteAccentPhrasePayload>,
    val speedScale: Double,
    val intonationScale: Double,
    val tempoDynamicsScale: Double,
    val pitchScale: Double,
    val volumeScale: Double,
    val prePhonemeLength: Double,
    val postPhonemeLength: Double,
    val pauseLength: Double? = null,
    val pauseLengthScale: Double,
    val outputSamplingRate: Int,
    val outputStereo: Boolean,
    val kana: String? = null,
) {
    fun toAudioQuery() = AudioQuery(
        accentPhrases = accentPhrases.map { it.toAccentPhrase() },
        speedScale = speedScale,
        intonationScale = intonationScale,
        tempoDynamicsScale = tempoDynamicsScale,
        pitchScale = pitchScale,
        volumeScale = volumeScale,
        pauseLengthScale = pauseLengthScale,
        prePhonemeLength = prePhonemeLength,
        postPhonemeLength = postPhonemeLength,
        outputSamplingRate = OutputSamplingRate.Explicit(outputSamplingRate),
        outputStereo = outputStereo,
        kana = kana,
    )

    companion object {
        fun from(query: AudioQuery) = RemoteAudioQueryPayload(
            accentPhrases = query.accentPhrases.map { RemoteAccentPhrasePayload.from(it) },
            speedScale = query.speedScale,
            intonationScale = query.intonationScale,
            tempoDynamicsScale = query.tempoDynamicsScale ?: 1.0,
            pitchScale = query.pitchScale,
            volumeScale = query.volumeScale,
            prePhonemeLength = query.prePhonemeLength,
            postPhonemeLength = query.postPhonemeLength,
            pauseLength = null,
            pauseLengthScale = query.pauseLengthScale,
            outputSamplingRate = when (val r = query.outputSamplingRate) {
                is OutputSamplingRate.EngineDefault -> 44_100
                is OutputSamplingRate.Explicit -> r.value
            },
            outputStereo = query.outputStereo,
            kana = query.kana,
        )
    }
}
