package com.rodwave.engine.mods

import kotlinx.serialization.Serializable

/** Folders the user chose as installation targets. */
@Serializable
enum class DestinationKind(val label: String) {
    CLEO_SCRIPTS("CLEO scripts folder"),
    AML_MODS("AML mods folder"),
    AML_CONFIGS("AML configs folder"),
    EXPORT("Export folder"),
}

@Serializable
enum class ModKind(val label: String) {
    CLEO_SCRIPT("CLEO script"),
    CLEO_TEXT("CLEO text (.fxt)"),
    AML_MOD("AML native mod"),
    CONFIG("Config file"),
    BUNDLE("Bundle"),
    OTHER("Other file"),
}

/** One file of a managed mod, stored in Rodwave's library and installed to [destination]/[targetPath]. */
@Serializable
data class ModFile(
    val libraryPath: String,
    val destination: DestinationKind,
    val targetPath: String,
    val sha256: String,
    val size: Long,
    val kind: ModKind,
)

@Serializable
data class ManagedMod(
    val id: String,
    val name: String,
    val kind: ModKind,
    val category: String = "General",
    val version: String? = null,
    val author: String? = null,
    val description: String = "",
    val sourceName: String,
    val importedAt: Long,
    val files: List<ModFile>,
    /** True while the mod's files are installed. */
    val enabled: Boolean = false,
    val installOperationId: String? = null,
    /** Declared or detected requirements (component ids or AML GUIDs). */
    val requires: List<String> = emptyList(),
    /** Analysis findings captured at import time. */
    val findings: List<String> = emptyList(),
    /** README text found in the archive, if any. */
    val instructions: String? = null,
)

/** Ownership of an installed file: which mod put it there and what it contained. */
@Serializable
data class InstalledFileRecord(
    val destination: DestinationKind,
    val targetPath: String,
    val modId: String,
    val sha256: String,
    val size: Long,
    val operationId: String,
)

/** A file saved before Rodwave replaced or deleted it. */
@Serializable
data class BackupEntry(
    val destination: DestinationKind,
    val targetPath: String,
    val backupFile: String,
    val sha256: String,
    val size: Long,
)

@Serializable
enum class OperationType { INSTALL, UNINSTALL, RESTORE }

@Serializable
enum class OperationStatus { SUCCEEDED, ROLLED_BACK, FAILED }

@Serializable
data class OperationRecord(
    val id: String,
    val type: OperationType,
    val modId: String?,
    val modName: String?,
    val startedAt: Long,
    val finishedAt: Long,
    val status: OperationStatus,
    val steps: List<String>,
    val backups: List<BackupEntry>,
    val error: String? = null,
)

/** Optional manifest authors can put in an archive as `rodwave-mod.json`. */
@Serializable
data class ModManifest(
    val name: String? = null,
    val version: String? = null,
    val author: String? = null,
    val description: String? = null,
    val category: String? = null,
    val requires: List<String> = emptyList(),
)
