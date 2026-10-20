package com.rodwave.studio.core

import com.rodwave.engine.compat.InstalledGame
import com.rodwave.engine.fs.VirtualFile
import kotlinx.serialization.Serializable

/** A folder the user granted through the system picker. [uri] is platform specific. */
@Serializable
data class FolderRef(val uri: String, val displayName: String)

data class PickedFile(val name: String, val bytes: ByteArray)

/** What a folder is used for; the picker may start at a location suited to it. */
enum class FolderPurpose(val title: String, val description: String) {
    GAME_DATA(
        "Game data folder",
        "Optional. Android/data/com.rockstargames.gtasa on Android 10 and older, or a copy you can access.",
    ),
    CLEO_SCRIPTS("CLEO scripts folder", "Where your CLEO loader reads .csa/.csi files."),
    AML_MODS("AML mods folder", "AMLMods/com.rockstargames.gtasa is readable by other apps on modern Android."),
    EXPORT("Export folder", "Any folder you can reach, e.g. Download/Rodwave. Use it when the game folders are not accessible."),
}

/**
 * Everything Rodwave needs from the operating system. The Android implementation uses the Storage
 * Access Framework and the package manager; the desktop harness uses java.io.
 */
interface PlatformServices {
    val platformName: String
    /** Android API level, or null on other platforms. */
    val sdkInt: Int?
    /** Private storage for projects, mods, backups and settings. */
    val appStorage: VirtualFile
    val deviceInfo: Map<String, String>

    /** The installed GTA SA package as reported by the system, or null. */
    fun installedGame(): InstalledGame?

    fun pickFolder(purpose: FolderPurpose, onResult: (FolderRef?) -> Unit)
    fun pickFile(mimeTypes: List<String>, onResult: (PickedFile?) -> Unit)
    /** Lets the user choose where to save [data]; reports success and the chosen name. */
    fun saveDocument(suggestedName: String, mimeType: String, data: ByteArray, onResult: (Boolean, String?) -> Unit)

    /** Opens a previously granted folder, or null if access was lost. */
    fun openFolder(ref: FolderRef): VirtualFile?
    fun releaseFolder(ref: FolderRef)

    fun openUrl(url: String)
    fun share(title: String, text: String)
    fun copyToClipboard(label: String, text: String)

    /** Blocking HTTPS download used only for user-initiated library downloads. */
    fun downloadText(url: String, maxBytes: Int): String
}
