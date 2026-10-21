package com.aivis.speechmobile.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int

@Serializable
data class VoiceReference(
    @SerialName("engineId") val engineID: String,
    @SerialName("speakerId") val speakerID: String,
    @SerialName("styleId") val styleID: Int,
)

@Serializable(with = OutputSamplingRateSerializer::class)
sealed class OutputSamplingRate {
    data object EngineDefault : OutputSamplingRate()
    data class Explicit(val value: Int) : OutputSamplingRate()
}

internal object OutputSamplingRateSerializer : KSerializer<OutputSamplingRate> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("OutputSamplingRate", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: OutputSamplingRate) {
        val jsonEncoder = encoder as JsonEncoder
        when (value) {
            is OutputSamplingRate.EngineDefault -> jsonEncoder.encodeJsonElement(JsonPrimitive("engineDefault"))
            is OutputSamplingRate.Explicit -> jsonEncoder.encodeJsonElement(JsonPrimitive(value.value))
        }
    }

    override fun deserialize(decoder: Decoder): OutputSamplingRate {
        val jsonDecoder = decoder as JsonDecoder
        val element = jsonDecoder.decodeJsonElement() as JsonPrimitive
        return if (element.isString) {
            OutputSamplingRate.EngineDefault
        } else {
            OutputSamplingRate.Explicit(element.int)
        }
    }
}

@Serializable
data class Mora(
    val text: String,
    val consonant: String? = null,
    val consonantLength: Double? = null,
    val vowel: String,
    val vowelLength: Double,
    val pitch: Double,
)

@Serializable
data class AccentPhrase(
    val moras: List<Mora>,
    val accent: Int,
    val pauseMora: Mora? = null,
    val isInterrogative: Boolean? = null,
)

@Serializable
data class AudioQuery(
    val accentPhrases: List<AccentPhrase>,
    val speedScale: Double,
    val intonationScale: Double,
    val tempoDynamicsScale: Double? = null,
    val pitchScale: Double,
    val volumeScale: Double,
    val pauseLengthScale: Double = 1.0,
    val prePhonemeLength: Double,
    val postPhonemeLength: Double,
    val outputSamplingRate: OutputSamplingRate,
    val outputStereo: Boolean,
    val kana: String? = null,
)

@Serializable
data class MorphingInfo(
    val rate: Double,
    @SerialName("targetEngineId") val targetEngineID: String,
    @SerialName("targetSpeakerId") val targetSpeakerID: String,
    @SerialName("targetStyleId") val targetStyleID: Int,
)

@Serializable
data class AudioItem(
    val text: String,
    val voice: VoiceReference,
    val query: AudioQuery? = null,
    val presetKey: String? = null,
    val morphingInfo: MorphingInfo? = null,
)

@Serializable
data class Tempo(
    val position: Int,
    val bpm: Double,
)

@Serializable
data class TimeSignature(
    val measureNumber: Int,
    val beats: Int,
    val beatType: Int,
)

@Serializable
data class Singer(
    @SerialName("engineId") val engineID: String,
    @SerialName("styleId") val styleID: Int,
)

@Serializable
data class Note(
    val id: String,
    val position: Double,
    val duration: Double,
    val noteNumber: Int,
    val lyric: String,
)

@Serializable
data class Track(
    val name: String,
    val singer: Singer? = null,
    val keyRangeAdjustment: Double,
    val volumeRangeAdjustment: Double,
    val notes: List<Note>,
    val pitchEditData: List<Double>,
    val solo: Boolean,
    val mute: Boolean,
    val gain: Double,
    val pan: Double,
)

@Serializable
data class TalkProject(
    val audioKeys: List<String>,
    val audioItems: Map<String, AudioItem>,
)

@Serializable
data class SongProject(
    val tpqn: Int,
    val tempos: List<Tempo>,
    val timeSignatures: List<TimeSignature>,
    val tracks: Map<String, Track>,
    val trackOrder: List<String>,
) {
    companion object {
        val empty = SongProject(
            tpqn = 480,
            tempos = listOf(Tempo(position = 0, bpm = 120.0)),
            timeSignatures = listOf(TimeSignature(measureNumber = 1, beats = 4, beatType = 4)),
            tracks = emptyMap(),
            trackOrder = emptyList(),
        )
    }
}

@Serializable
data class AISPProjectDocument(
    val appVersion: String,
    val talk: TalkProject,
    val song: SongProject,
)

@Serializable
data class Preset(
    val name: String,
    val speedScale: Double,
    val intonationScale: Double,
    val tempoDynamicsScale: Double? = null,
    val pitchScale: Double,
    val volumeScale: Double,
    val pauseLengthScale: Double,
    val prePhonemeLength: Double,
    val postPhonemeLength: Double,
)

@Serializable
data class PresetCatalog(
    val items: Map<String, Preset>,
    val keys: List<String>,
)

@Serializable
data class DefaultStyleID(
    @SerialName("engineId") val engineID: String,
    @SerialName("speakerUuid") val speakerUUID: String,
    @SerialName("defaultStyleId") val defaultStyleID: Int,
)

@Serializable
data class UserDictionaryEntry(
    val id: String,
    val surface: String,
    val pronunciation: String,
    val accentType: Int,
    val wordType: WordType,
    val priority: Int,
) {
    enum class WordType(val value: String) {
        PROPER_NOUN("PROPER_NOUN"),
        COMMON_NOUN("COMMON_NOUN"),
        VERB("VERB"),
        ADJECTIVE("ADJECTIVE"),
        SUFFIX("SUFFIX"),
        ;

        companion object {
            fun from(value: String) = entries.firstOrNull { it.value == value } ?: PROPER_NOUN
        }
    }
}

@Serializable
data class UserDictionary(
    val entries: List<UserDictionaryEntry>,
)

data class WAVPCMFormat(
    val audioFormat: Short,
    val channelCount: Short,
    val sampleRate: Int,
    val byteRate: Int,
    val blockAlign: Short,
    val bitsPerSample: Short,
)

object WAVDataConcatenator {
    fun concatenate(wavs: List<ByteArray>): ByteArray {
        require(wavs.isNotEmpty()) { "No WAV data provided" }
        val segments = wavs.map(::parseSegment)
        val referenceFormat = segments[0].first
        for (segment in segments) {
            require(segment.first == referenceFormat) {
                "WAV formats must match. Expected $referenceFormat, got ${segment.first}"
            }
        }
        val pcmData = segments.map { it.second }
        val totalPcmSize = pcmData.sumOf { it.size }
        return buildWAV(referenceFormat, pcmData, totalPcmSize)
    }

    private fun parseSegment(wav: ByteArray): Pair<WAVPCMFormat, ByteArray> {
        require(wav.size >= 12) { "Invalid WAV: too small" }
        require(wav.asciiAt(0, 4) == "RIFF" && wav.asciiAt(8, 4) == "WAVE") { "Invalid RIFF/WAVE" }
        var cursor = 12
        var format: WAVPCMFormat? = null
        var pcmData: ByteArray? = null
        while (cursor + 8 <= wav.size) {
            val chunkID = wav.asciiAt(cursor, 4)
            val chunkSize = wav.int32LE(cursor + 4)
            val dataStart = cursor + 8
            val dataEnd = dataStart + chunkSize
            if (dataEnd > wav.size) break
            when (chunkID) {
                "fmt " -> {
                    format = WAVPCMFormat(
                        audioFormat = wav.int16LE(dataStart),
                        channelCount = wav.int16LE(dataStart + 2),
                        sampleRate = wav.int32LE(dataStart + 4),
                        byteRate = wav.int32LE(dataStart + 8),
                        blockAlign = wav.int16LE(dataStart + 12),
                        bitsPerSample = wav.int16LE(dataStart + 14),
                    )
                }
                "data" -> pcmData = wav.copyOfRange(dataStart, dataEnd)
            }
            cursor = dataEnd + (chunkSize % 2)
        }
        return Pair(
            checkNotNull(format) { "Missing fmt chunk" },
            checkNotNull(pcmData) { "Missing data chunk" },
        )
    }

    private fun buildWAV(fmt: WAVPCMFormat, chunks: List<ByteArray>, totalPcm: Int): ByteArray {
        val out = java.io.ByteArrayOutputStream(44 + totalPcm)
        fun writeBytes(vararg bytes: Byte) = out.write(bytes)
        fun writeString(s: String) = out.write(s.toByteArray(Charsets.US_ASCII))
        fun writeInt16LE(v: Short) {
            out.write(v.toInt() and 0xFF)
            out.write((v.toInt() shr 8) and 0xFF)
        }
        fun writeInt32LE(v: Int) {
            out.write(v and 0xFF)
            out.write((v shr 8) and 0xFF)
            out.write((v shr 16) and 0xFF)
            out.write((v shr 24) and 0xFF)
        }
        writeString("RIFF")
        writeInt32LE(36 + totalPcm)
        writeString("WAVE")
        writeString("fmt ")
        writeInt32LE(16)
        writeInt16LE(fmt.audioFormat)
        writeInt16LE(fmt.channelCount)
        writeInt32LE(fmt.sampleRate)
        writeInt32LE(fmt.byteRate)
        writeInt16LE(fmt.blockAlign)
        writeInt16LE(fmt.bitsPerSample)
        writeString("data")
        writeInt32LE(totalPcm)
        for (chunk in chunks) out.write(chunk)
        return out.toByteArray()
    }

    private fun ByteArray.asciiAt(offset: Int, length: Int) =
        String(this, offset, length, Charsets.US_ASCII)

    private fun ByteArray.int16LE(offset: Int): Short =
        ((this[offset].toInt() and 0xFF) or ((this[offset + 1].toInt() and 0xFF) shl 8)).toShort()

    private fun ByteArray.int32LE(offset: Int): Int =
        (this[offset].toInt() and 0xFF) or
            ((this[offset + 1].toInt() and 0xFF) shl 8) or
            ((this[offset + 2].toInt() and 0xFF) shl 16) or
            ((this[offset + 3].toInt() and 0xFF) shl 24)
}
