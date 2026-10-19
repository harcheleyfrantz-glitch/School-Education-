package com.rodwave.engine.mods

import com.rodwave.engine.archive.SafeZip
import com.rodwave.engine.compat.InstalledGame
import com.rodwave.engine.compat.NativeModInspector
import com.rodwave.engine.fs.FsException
import com.rodwave.engine.fs.VirtualFile
import com.rodwave.engine.fs.readBytes
import com.rodwave.engine.fs.resolve
import com.rodwave.engine.fs.sha256

enum class ActionType(val label: String) {
    CREATE("Create"),
    REPLACE("Replace (original backed up)"),
    SKIP_IDENTICAL("Skip — identical file already present"),
    DELETE("Delete (backed up first)"),
    RESTORE("Restore original"),
}

data class PlannedAction(
    val type: ActionType,
    val destination: DestinationKind,
    val targetPath: String,
    val file: ModFile? = null,
    val backup: BackupEntry? = null,
    val note: String = "",
)

data class Conflict(val destination: DestinationKind, val targetPath: String, val reason: String, val ownerModId: String? = null)

/** Facts the planner uses to warn about missing loaders and ABI problems. */
data class PlanContext(
    val game: InstalledGame? = null,
    val amlDetected: Boolean = false,
    val cleoLoaderDetected: Boolean = false,
)

/** A dry-run description of everything an operation would change. */
data class InstallPlan(
    val mod: ManagedMod,
    val type: OperationType,
    val actions: List<PlannedAction>,
    /** Problems that prevent applying the plan. */
    val blockers: List<String>,
    /** Changes the user must explicitly accept (replacing files Rodwave does not own, ...). */
    val confirmations: List<Conflict>,
    val warnings: List<String>,
) {
    val changesFiles: Boolean get() = actions.any { it.type != ActionType.SKIP_IDENTICAL }

    fun canApply(confirmed: Boolean): Boolean = blockers.isEmpty() && (confirmations.isEmpty() || confirmed)

    fun describe(): String = buildString {
        appendLine("${type.name.lowercase().replaceFirstChar { it.uppercase() }} '${mod.name}' — dry run")
        actions.forEach { appendLine("  ${it.type.label}: ${it.destination.label}/${it.targetPath}${if (it.note.isNotEmpty()) " (${it.note})" else ""}") }
        blockers.forEach { appendLine("  BLOCKED: $it") }
        confirmations.forEach { appendLine("  NEEDS CONFIRMATION: ${it.destination.label}/${it.targetPath} — ${it.reason}") }
        warnings.forEach { appendLine("  Warning: $it") }
    }
}

class InstallPlanner(private val store: ModStore) {

    fun planInstall(mod: ManagedMod, destinations: Map<DestinationKind, VirtualFile>, context: PlanContext = PlanContext()): InstallPlan {
        val actions = ArrayList<PlannedAction>()
        val blockers = ArrayList<String>()
        val confirmations = ArrayList<Conflict>()
        val warnings = ArrayList<String>()

        val duplicateTargets = mod.files.groupBy { it.destination to it.targetPath.lowercase() }.filter { it.value.size > 1 }
        duplicateTargets.keys.forEach { (d, p) -> blockers += "Several files of this mod would be installed to ${d.label}/$p" }

        for (file in mod.files) {
            val (safePath, reason) = SafeZip.normalize(file.targetPath)
            if (safePath == null || safePath != file.targetPath) {
                blockers += "Unsafe target path '${file.targetPath}' (${reason ?: "not normalised"})"
                continue
            }
            val root = destinations[file.destination]
            if (root == null) {
                blockers += "Choose a ${file.destination.label} in Game Directory settings before installing ${file.targetPath}"
                continue
            }
            if (!root.canWrite) {
                blockers += "Rodwave cannot write to the ${file.destination.label} (${root.name}); Android denied write access"
                continue
            }
            checkFile(file, context, blockers, warnings)
            val existing = try {
                root.resolve(file.targetPath)
            } catch (e: FsException) {
                blockers += "Cannot inspect ${file.targetPath}: ${e.message}"
                continue
            }
            if (existing == null) {
                actions += PlannedAction(ActionType.CREATE, file.destination, file.targetPath, file)
                continue
            }
            if (existing.isDirectory) {
                blockers += "${file.destination.label}/${file.targetPath} is a folder"
                continue
            }
            val existingHash = try {
                existing.readBytes().sha256()
            } catch (e: FsException) {
                blockers += "Cannot read existing ${file.targetPath}: ${e.message}"
                continue
            }
            if (existingHash == file.sha256) {
                actions += PlannedAction(ActionType.SKIP_IDENTICAL, file.destination, file.targetPath, file, note = "not owned by this mod; it will stay when the mod is removed")
                continue
            }
            val owner = store.owner(file.destination, file.targetPath)
            when {
                owner == null -> {
                    actions += PlannedAction(ActionType.REPLACE, file.destination, file.targetPath, file, note = "existing file is not managed by Rodwave")
                    confirmations += Conflict(file.destination, file.targetPath, "replaces a file Rodwave did not install (it will be backed up)")
                }
                owner.modId == mod.id -> actions += PlannedAction(ActionType.REPLACE, file.destination, file.targetPath, file, note = "update of this mod's file")
                else -> {
                    val other = store.mod(owner.modId)?.name ?: owner.modId
                    blockers += "${file.destination.label}/${file.targetPath} belongs to the installed mod '$other'; disable it first"
                }
            }
        }

        blockers += abiProblems(mod, context.game)
        if (mod.files.any { it.kind == ModKind.CLEO_SCRIPT } && !context.cleoLoaderDetected) {
            warnings += "No CLEO loader was verified; scripts will not run until one is installed"
        }
        if (mod.files.any { it.kind == ModKind.AML_MOD } && !context.amlDetected) {
            warnings += "AML was not detected; native mods will not load without it"
        }
        mod.requires.forEach { warnings += "Declared requirement: $it (Rodwave cannot verify every requirement)" }
        return InstallPlan(mod, OperationType.INSTALL, actions, blockers.distinct(), confirmations, warnings.distinct())
    }

    private fun checkFile(file: ModFile, context: PlanContext, blockers: MutableList<String>, warnings: MutableList<String>) {
        if (file.kind != ModKind.AML_MOD) return
        // Detailed ABI checks run on the library copy at apply time too; here we use import findings.
        val gameAbis = context.game?.abis.orEmpty()
        if (gameAbis.isEmpty()) warnings += "${file.targetPath}: the game's ABI is unknown, so the ABI could not be checked"
        if (file.destination == DestinationKind.AML_MODS && !file.targetPath.endsWith(".so")) {
            blockers += "${file.targetPath}: AML only loads files ending in .so"
        }
    }

    /** Checks native mods against the game ABI using the library copies. */
    fun abiProblems(mod: ManagedMod, game: InstalledGame?): List<String> {
        val gameAbis = game?.abis.orEmpty()
        return mod.files.filter { it.kind == ModKind.AML_MOD }.mapNotNull { f ->
            val info = runCatching { NativeModInspector.inspect(f.targetPath, store.readLibraryFile(mod, f)) }.getOrNull()
                ?: return@mapNotNull "${f.targetPath}: library copy unreadable"
            when {
                info.error != null -> "${f.targetPath}: ${info.error}"
                !info.isAmlMod -> "${f.targetPath}: not an AML mod (no __GetModInfo export)"
                !info.isLoaderCompatibleAbi -> "${f.targetPath}: built for ${info.abi?.androidName}; AML is ARM-only"
                gameAbis.isNotEmpty() && info.abi !in gameAbis -> "${f.targetPath}: ${info.abi?.androidName} does not match the game (${gameAbis.joinToString { it.androidName }})"
                else -> null
            }
        }
    }

    fun planUninstall(mod: ManagedMod, destinations: Map<DestinationKind, VirtualFile>): InstallPlan {
        val actions = ArrayList<PlannedAction>()
        val blockers = ArrayList<String>()
        val confirmations = ArrayList<Conflict>()
        val warnings = ArrayList<String>()
        val records = store.installedFiles().filter { it.modId == mod.id }
        if (records.isEmpty()) warnings += "No installed files are recorded for this mod"
        for (record in records) {
            val root = destinations[record.destination]
            if (root == null) {
                blockers += "The ${record.destination.label} is not configured; cannot remove ${record.targetPath}"
                continue
            }
            val existing = runCatching { root.resolve(record.targetPath) }.getOrNull()
            if (existing == null || existing.isDirectory) {
                warnings += "${record.targetPath} is already gone"
                continue
            }
            val hash = runCatching { existing.readBytes().sha256() }.getOrNull()
            if (hash != record.sha256) {
                confirmations += Conflict(record.destination, record.targetPath, "was modified after installation (it will be backed up before removal)")
            }
            actions += PlannedAction(ActionType.DELETE, record.destination, record.targetPath)
        }
        // Put back originals that the install replaced.
        val install = mod.installOperationId?.let(store::operation)
        install?.backups?.forEach { b ->
            if (destinations[b.destination] == null) {
                blockers += "The ${b.destination.label} is not configured; cannot restore ${b.targetPath}"
            } else {
                actions += PlannedAction(ActionType.RESTORE, b.destination, b.targetPath, backup = b, note = "original from before the install")
            }
        }
        return InstallPlan(mod, OperationType.UNINSTALL, actions, blockers.distinct(), confirmations, warnings)
    }
}
