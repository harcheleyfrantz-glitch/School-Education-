package com.rodwave.studio.core

import com.rodwave.engine.fs.VirtualFile
import com.rodwave.engine.fs.readText
import com.rodwave.engine.fs.resolve
import com.rodwave.engine.fs.writeFile
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
enum class ThemeVariant(val title: String) {
    SUNSET("Sunset (default)"),
    MIDNIGHT("Midnight blue"),
    AMOLED("AMOLED black"),
}

@Serializable
data class StudioSettings(
    val fontSize: Int = 14,
    val autocomplete: Boolean = true,
    val autoIndent: Boolean = true,
    val codingBar: Boolean = true,
    val liveDiagnostics: Boolean = true,
    val autosaveSeconds: Int = 15,
    val theme: ThemeVariant = ThemeVariant.SUNSET,
    val defaultFormat: String = "csa",
    /** Granted folders by [FolderPurpose] name. */
    val folders: Map<String, FolderRef> = emptyMap(),
    val useImportedLibrary: Boolean = true,
    val onboardingDone: Boolean = false,
) {
    fun folder(purpose: FolderPurpose): FolderRef? = folders[purpose.name]
}

/** Settings persisted as JSON in Rodwave's private storage. */
class SettingsStore(private val storage: VirtualFile) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; prettyPrint = true }

    fun load(): StudioSettings = runCatching {
        storage.resolve(FILE)?.readText()?.let { json.decodeFromString(StudioSettings.serializer(), it) }
    }.getOrNull() ?: StudioSettings()

    fun save(settings: StudioSettings) {
        storage.writeFile(FILE, json.encodeToString(StudioSettings.serializer(), settings).toByteArray())
    }

    companion object {
        const val FILE = "settings.json"
    }
}
