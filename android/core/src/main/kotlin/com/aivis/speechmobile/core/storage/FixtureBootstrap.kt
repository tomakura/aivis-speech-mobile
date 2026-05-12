package com.aivis.speechmobile.core.storage

import com.aivis.speechmobile.core.DefaultStyleID
import com.aivis.speechmobile.core.InstalledModel
import com.aivis.speechmobile.core.ModelManifest
import com.aivis.speechmobile.core.ModelSpeaker
import com.aivis.speechmobile.core.ModelStyle
import com.aivis.speechmobile.core.Preset
import com.aivis.speechmobile.core.PresetCatalog
import com.aivis.speechmobile.core.UserDictionary
import com.aivis.speechmobile.core.UserDictionaryEntry
import java.util.UUID

object FixtureBootstrap {
    private val sampleSpeakerUUID = UUID.fromString("2d8f6f95-3369-4af7-b0bd-a6310c5d5230")
    private val primaryModelUUID = UUID.fromString("4c9ca6f3-7d9f-4093-a8dd-f87f0d7c2724")
    private val secondaryModelUUID = UUID.fromString("6ad4f1d8-024a-4dc7-b0d8-24bce9822489")
    private val sampleEngineID = "1b4a5014-d9fd-11ee-b97d-83c170a68ed3"

    fun presetCatalog() = PresetCatalog(
        items = mapOf(
            "default-normal" to Preset(
                name = "Normal",
                speedScale = 1.0,
                intonationScale = 1.0,
                tempoDynamicsScale = 1.0,
                pitchScale = 0.0,
                volumeScale = 1.0,
                pauseLengthScale = 1.0,
                prePhonemeLength = 0.1,
                postPhonemeLength = 0.1,
            ),
            "default-slow" to Preset(
                name = "ゆっくり",
                speedScale = 0.75,
                intonationScale = 1.1,
                tempoDynamicsScale = 1.0,
                pitchScale = 0.0,
                volumeScale = 1.0,
                pauseLengthScale = 1.25,
                prePhonemeLength = 0.15,
                postPhonemeLength = 0.2,
            ),
            "default-fast" to Preset(
                name = "はっきり",
                speedScale = 1.2,
                intonationScale = 1.2,
                tempoDynamicsScale = 1.1,
                pitchScale = 0.0,
                volumeScale = 1.0,
                pauseLengthScale = 1.0,
                prePhonemeLength = 0.05,
                postPhonemeLength = 0.1,
            ),
        ),
        keys = listOf("default-normal", "default-slow", "default-fast"),
    )

    fun defaultStyles() = listOf(
        DefaultStyleID(
            engineID = sampleEngineID,
            speakerUUID = sampleSpeakerUUID.toString(),
            defaultStyleID = 0,
        ),
    )

    fun userDictionary() = UserDictionary(
        entries = listOf(
            UserDictionaryEntry(
                id = UUID.randomUUID().toString(),
                surface = "AivisSpeech",
                pronunciation = "アイビススピーチ",
                accentType = 7,
                wordType = UserDictionaryEntry.WordType.PROPER_NOUN,
                priority = 5,
            ),
        ),
    )

    fun installedModels(): List<InstalledModel> {
        val styles = listOf(
            ModelStyle(localID = 0, name = "Normal"),
            ModelStyle(localID = 1, name = "Joy"),
            ModelStyle(localID = 2, name = "Sadness"),
        )
        val speakers = listOf(ModelSpeaker(uuid = sampleSpeakerUUID, name = "Sample Speaker", styles = styles))
        val primaryManifest = ModelManifest(
            uuid = primaryModelUUID,
            name = "Sample Voice Model",
            version = "1.0.0",
            modelArchitecture = "Style-Bert-VITS2",
            modelFormat = "AIVMX",
            speakers = speakers,
        )
        val secondaryManifest = ModelManifest(
            uuid = secondaryModelUUID,
            name = "Misty Narrator",
            version = "0.9.2",
            modelArchitecture = "Style-Bert-VITS2",
            modelFormat = "AIVMX",
            speakers = speakers,
        )
        return listOf(
            InstalledModel(
                id = primaryModelUUID,
                name = primaryManifest.name,
                version = primaryManifest.version,
                sourceURL = "https://example.com/${primaryManifest.name}.aivmx",
                loadState = InstalledModel.LoadState.ACTIVE,
                manifest = primaryManifest,
            ),
            InstalledModel(
                id = secondaryModelUUID,
                name = secondaryManifest.name,
                version = secondaryManifest.version,
                sourceURL = "https://example.com/${secondaryManifest.name}.aivmx",
                loadState = InstalledModel.LoadState.LOADED,
                manifest = secondaryManifest,
            ),
        )
    }

    val sampleEngineIDStr: String get() = sampleEngineID
    val sampleSpeakerUUIDStr: String get() = sampleSpeakerUUID.toString()
}
