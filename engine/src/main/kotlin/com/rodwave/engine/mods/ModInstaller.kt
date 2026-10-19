package com.rodwave.engine.mods

import com.rodwave.engine.fs.FsException
import com.rodwave.engine.fs.VirtualFile
import com.rodwave.engine.fs.ensureDirectory
import com.rodwave.engine.fs.readBytes
import com.rodwave.engine.fs.resolve
import com.rodwave.engine.fs.sha256
import com.rodwave.engine.fs.writeBytes

data class OperationResult(val success: Boolean, val record: OperationRecord?, val message: String)

/**
 * Applies install plans with backups, read-back verification and rollback.
 *
 * Every replaced or deleted file is copied to Rodwave's backup store first. If any step fails,
 * completed steps are undone in reverse order and the operation is recorded as rolled back.
 */
class ModInstaller(
    private val store: ModStore,
    private val clock: () -> Long = System::currentTimeMillis,
    private val newId: () -> String = { java.util.UUID.randomUUID().toString() },
) {
    private sealed class Undo {
        data class RemoveCreated(val root: VirtualFile, val path: String) : Undo()
        data class RestoreContent(val root: VirtualFile, val path: String, val backup: BackupEntry) : Undo()
    }

    fun apply(plan: InstallPlan, destinations: Map<DestinationKind, VirtualFile>, confirmed: Boolean): OperationResult {
        if (!plan.canApply(confirmed)) {
            val why = plan.blockers.firstOrNull() ?: "confirmation required for ${plan.confirmations.size} change(s)"
            return OperationResult(false, null, "Not applied: $why")
        }
        val opId = newId()
        val started = clock()
        val steps = ArrayList<String>()
        val backups = ArrayList<BackupEntry>()
        val undo = ArrayList<Undo>()
        val registry = store.installedFiles().toMutableList()

        fun backup(dest: DestinationKind, path: String, data: ByteArray): BackupEntry {
            val file = store.writeBackup(opId, backups.size, data)
            val entry = BackupEntry(dest, path, file, data.sha256(), data.size.toLong())
            // Verify the backup before touching the original.
            store.readBackup(entry)
            backups += entry
            steps += "Backed up ${dest.label}/$path"
            return entry
        }

        try {
            for (action in plan.actions) {
                val root = destinations[action.destination] ?: throw FsException("${action.destination.label} is not configured")
                when (action.type) {
                    ActionType.SKIP_IDENTICAL -> steps += "Skipped identical ${action.targetPath}"
                    ActionType.CREATE, ActionType.REPLACE -> {
                        val file = action.file!!
                        val data = store.readLibraryFile(plan.mod, file)
                        val existing = root.resolve(action.targetPath)
                        if (existing != null && existing.isFile) {
                            val b = backup(action.destination, action.targetPath, existing.readBytes())
                            undo += Undo.RestoreContent(root, action.targetPath, b)
                        } else {
                            undo += Undo.RemoveCreated(root, action.targetPath)
                        }
                        writeVerified(root, action.targetPath, data)
                        registry.removeAll { it.destination == action.destination && it.targetPath.equals(action.targetPath, true) }
                        registry += InstalledFileRecord(action.destination, action.targetPath, plan.mod.id, file.sha256, file.size, opId)
                        steps += "${if (existing != null) "Replaced" else "Created"} ${action.destination.label}/${action.targetPath}"
                    }
                    ActionType.DELETE -> {
                        val existing = root.resolve(action.targetPath)
                        if (existing == null) {
                            steps += "Already gone: ${action.targetPath}"
                        } else {
                            val b = backup(action.destination, action.targetPath, existing.readBytes())
                            if (!existing.delete()) throw FsException("Android did not allow deleting ${action.targetPath}")
                            undo += Undo.RestoreContent(root, action.targetPath, b)
                            steps += "Deleted ${action.destination.label}/${action.targetPath}"
                        }
                        registry.removeAll { it.destination == action.destination && it.targetPath.equals(action.targetPath, true) && it.modId == plan.mod.id }
                    }
                    ActionType.RESTORE -> {
                        val source = action.backup!!
                        val data = store.readBackup(source)
                        val existing = root.resolve(action.targetPath)
                        if (existing != null && existing.isFile) {
                            val b = backup(action.destination, action.targetPath, existing.readBytes())
                            undo += Undo.RestoreContent(root, action.targetPath, b)
                        } else {
                            undo += Undo.RemoveCreated(root, action.targetPath)
                        }
                        writeVerified(root, action.targetPath, data)
                        steps += "Restored original ${action.destination.label}/${action.targetPath}"
                    }
                }
            }
            store.saveInstalledFiles(registry)
            val record = OperationRecord(opId, plan.type, plan.mod.id, plan.mod.name, started, clock(), OperationStatus.SUCCEEDED, steps, backups)
            store.saveOperation(record)
            when (plan.type) {
                OperationType.INSTALL -> store.saveMod(plan.mod.copy(enabled = true, installOperationId = opId))
                OperationType.UNINSTALL -> store.saveMod(plan.mod.copy(enabled = false, installOperationId = null))
                OperationType.RESTORE -> Unit
            }
            return OperationResult(true, record, "${plan.type.name.lowercase().replaceFirstChar { it.uppercase() }} of '${plan.mod.name}' completed (${steps.size} step(s))")
        } catch (e: Exception) {
            val error = e.message ?: e.javaClass.simpleName
            steps += "FAILED: $error"
            val rollbackOk = rollback(undo, steps)
            val record = OperationRecord(
                opId, plan.type, plan.mod.id, plan.mod.name, started, clock(),
                if (rollbackOk) OperationStatus.ROLLED_BACK else OperationStatus.FAILED, steps, backups, error,
            )
            runCatching { store.saveOperation(record) }
            val msg = if (rollbackOk) "Failed and rolled back: $error" else "Failed and could not fully roll back: $error — see the operation log and backups"
            return OperationResult(false, record, msg)
        }
    }

    /** Restores every backup of a past operation to its original location. */
    fun restoreOperation(operationId: String, destinations: Map<DestinationKind, VirtualFile>): OperationResult {
        val source = store.operation(operationId) ?: return OperationResult(false, null, "Operation $operationId not found")
        if (source.backups.isEmpty()) return OperationResult(false, null, "That operation has no backups")
        val pseudoMod = ManagedMod(
            id = source.modId ?: "restore", name = source.modName ?: "Backup", kind = ModKind.OTHER,
            sourceName = "backup", importedAt = source.startedAt, files = emptyList(),
        )
        val plan = InstallPlan(
            pseudoMod, OperationType.RESTORE,
            source.backups.map { PlannedAction(ActionType.RESTORE, it.destination, it.targetPath, backup = it) },
            source.backups.filter { destinations[it.destination] == null }.map { "The ${it.destination.label} is not configured" }.distinct(),
            emptyList(), emptyList(),
        )
        return apply(plan, destinations, confirmed = true)
    }

    private fun rollback(undo: List<Undo>, steps: MutableList<String>): Boolean {
        var ok = true
        for (u in undo.asReversed()) {
            try {
                when (u) {
                    is Undo.RemoveCreated -> {
                        u.root.resolve(u.path)?.delete()
                        steps += "Rolled back: removed ${u.path}"
                    }
                    is Undo.RestoreContent -> {
                        writeVerified(u.root, u.path, store.readBackup(u.backup))
                        steps += "Rolled back: restored ${u.path}"
                    }
                }
            } catch (e: Exception) {
                ok = false
                steps += "Rollback step failed for ${(u as? Undo.RemoveCreated)?.path ?: (u as Undo.RestoreContent).path}: ${e.message}"
            }
        }
        return ok
    }

    /**
     * Writes through a temporary file, verifies the bytes by reading them back, then swaps it in.
     */
    private fun writeVerified(root: VirtualFile, relative: String, data: ByteArray) {
        val parentPath = relative.substringBeforeLast('/', "")
        val name = relative.substringAfterLast('/')
        val dir = if (parentPath.isEmpty()) root else root.ensureDirectory(parentPath)
        val tmpName = "$name.rodwave-tmp"
        dir.child(tmpName)?.delete()
        val tmp = dir.createFile(tmpName)
        tmp.writeBytes(data)
        if (!tmp.readBytes().contentEquals(data)) {
            tmp.delete()
            throw FsException("Verification failed while writing $relative")
        }
        dir.child(name)?.let { old ->
            if (!old.delete()) {
                tmp.delete()
                throw FsException("Android did not allow replacing $relative")
            }
        }
        val final = tmp.renameTo(name)
        if (!final.readBytes().contentEquals(data)) throw FsException("Verification failed after renaming $relative")
    }
}
