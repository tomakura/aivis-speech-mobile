package com.aivis.speechmobile.core.storage

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.aivis.speechmobile.core.DefaultStyleID
import com.aivis.speechmobile.core.PresetCatalog
import com.aivis.speechmobile.core.UserDictionary
import kotlinx.coroutines.flow.first
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

private val Context.dataStore by preferencesDataStore(name = "aivis_speech_prefs")

class AppStorage(context: Context) {
    private val store = context.dataStore
    private val json = Json { ignoreUnknownKeys = true }

    private object Keys {
        val USER_DICTIONARY = stringPreferencesKey("user_dictionary")
        val PRESET_CATALOG = stringPreferencesKey("preset_catalog")
        val DEFAULT_STYLES = stringPreferencesKey("default_styles")
        val REMOTE_ENGINE_URL = stringPreferencesKey("remote_engine_url")
        val REMOTE_ENGINE_ENABLED = stringPreferencesKey("remote_engine_enabled")
    }

    suspend fun loadUserDictionary(): UserDictionary? {
        val prefs = store.data.first()
        val raw = prefs[Keys.USER_DICTIONARY] ?: return null
        return try { json.decodeFromString(raw) } catch (_: Exception) { null }
    }

    suspend fun saveUserDictionary(dictionary: UserDictionary) {
        store.edit { it[Keys.USER_DICTIONARY] = json.encodeToString(dictionary) }
    }

    suspend fun loadPresetCatalog(): PresetCatalog? {
        val prefs = store.data.first()
        val raw = prefs[Keys.PRESET_CATALOG] ?: return null
        return try { json.decodeFromString(raw) } catch (_: Exception) { null }
    }

    suspend fun savePresetCatalog(catalog: PresetCatalog) {
        store.edit { it[Keys.PRESET_CATALOG] = json.encodeToString(catalog) }
    }

    suspend fun loadDefaultStyles(): List<DefaultStyleID>? {
        val prefs = store.data.first()
        val raw = prefs[Keys.DEFAULT_STYLES] ?: return null
        return try { json.decodeFromString(raw) } catch (_: Exception) { null }
    }

    suspend fun saveDefaultStyles(styles: List<DefaultStyleID>) {
        store.edit { it[Keys.DEFAULT_STYLES] = json.encodeToString(styles) }
    }

    suspend fun remoteEngineEnabled(): Boolean {
        val prefs = store.data.first()
        return prefs[Keys.REMOTE_ENGINE_ENABLED] == "true"
    }

    suspend fun setRemoteEngineEnabled(enabled: Boolean) {
        store.edit { it[Keys.REMOTE_ENGINE_ENABLED] = if (enabled) "true" else "false" }
    }

    suspend fun remoteEngineURL(): String {
        val prefs = store.data.first()
        return prefs[Keys.REMOTE_ENGINE_URL] ?: ""
    }

    suspend fun setRemoteEngineURL(url: String) {
        store.edit { it[Keys.REMOTE_ENGINE_URL] = url }
    }
}
