package com.rodwave.engine.compat

import com.rodwave.engine.scm.Abi

/** The six states shown in the Compatibility Center. */
enum class ComponentState(val label: String) {
    COMPATIBLE("Compatible"),
    PARTIALLY_COMPATIBLE("Partially compatible"),
    INSTALLED_UNVERIFIED("Installed but unverified"),
    NOT_DETECTED("Not detected"),
    INCOMPATIBLE("Incompatible"),
    UNKNOWN("Unknown"),
}

enum class Confidence(val label: String) { HIGH("High"), MEDIUM("Medium"), LOW("Low") }

/** One observation supporting a state, e.g. "configs/ModLoaderCore.ini exists". */
data class Evidence(val text: String, val confidence: Confidence, val path: String? = null)

enum class ComponentCategory(val label: String) {
    GAME("Game"),
    SCRIPT_LOADER("Script loader"),
    NATIVE_LOADER("Native mod loader"),
    NATIVE_MOD("Native mods"),
    FORMAT("Script & text formats"),
    OTHER("Other"),
}

data class ExternalLink(val title: String, val url: String)

/** Static knowledge about a modding component, with the source of each fact in [sources]. */
data class ComponentProfile(
    val id: String,
    val name: String,
    val category: ComponentCategory,
    val summary: String,
    val supportedVersions: String,
    val supportedAbis: String,
    val requirements: List<String>,
    val installSteps: List<String>,
    val limitations: List<String>,
    val links: List<ExternalLink> = emptyList(),
    /** How the facts above were verified. */
    val sources: List<String>,
)

data class ComponentStatus(
    val profile: ComponentProfile,
    val state: ComponentState,
    val summary: String,
    val evidence: List<Evidence> = emptyList(),
)

/** Facts about the installed game as reported by Android's package manager. */
data class InstalledGame(
    val packageName: String,
    val versionName: String?,
    val versionCode: Long?,
    /** ABIs of the game's native libraries (from the APK or the native library directory). */
    val abis: Set<Abi>,
    /** Native library file names inside the APK (empty if the APK could not be read). */
    val nativeLibraries: List<String>,
    val apkReadable: Boolean,
    val targetSdk: Int? = null,
    /** ABI the game process runs with (Android picks one of [abis] at install time), if known. */
    val runningAbi: Abi? = null,
) {
    val hasAml: Boolean get() = nativeLibraries.any { it.equals("libAML.so", ignoreCase = true) }
    val primaryAbi: Abi? get() = runningAbi ?: abis.maxByOrNull { it.bits }

    /**
     * ABIs a native mod may be built for. A library must match the process, so this is the running
     * ABI when known; otherwise every packaged ABI is plausible.
     */
    val modAbis: Set<Abi> get() = runningAbi?.let { setOf(it) } ?: abis
}

/** Where the chosen folder sits relative to the game. */
enum class LocationKind(val label: String) {
    GAME_DATA_FOLDER("Game data folder (Android/data/com.rockstargames.gtasa)"),
    AML_INTERNAL_MODS("AML internal mods folder (AMLMods/<package>)"),
    MODS_FOLDER("Native mods folder"),
    CONFIGS_FOLDER("AML configs folder"),
    SCRIPTS_FOLDER("Folder with CLEO scripts"),
    GENERIC("Folder without recognisable game files"),
}

/** Known GTA San Andreas Android versions, as enumerated by CLEO Android (`GameVerInternal`). */
object GtaSaVersions {
    val KNOWN = listOf("1.00", "1.01", "1.02", "1.03", "1.05", "1.05 GER", "1.06", "1.07", "1.08", "2.00+")

    /** Classifies a package version name; returns null when it is not recognisable. */
    fun classify(versionName: String?): String? {
        val v = versionName?.trim() ?: return null
        val match = Regex("^(\\d+)\\.(\\d+)").find(v) ?: return null
        val major = match.groupValues[1].toInt()
        val minor = match.groupValues[2].toInt()
        return when {
            major == 1 && minor in listOf(0, 1, 2, 3, 5, 6, 7, 8) -> "1.%02d".format(minor)
            major >= 2 -> "2.00+"
            else -> null
        }
    }

    fun isLegacy(versionName: String?): Boolean = classify(versionName)?.startsWith("1.") == true
}
