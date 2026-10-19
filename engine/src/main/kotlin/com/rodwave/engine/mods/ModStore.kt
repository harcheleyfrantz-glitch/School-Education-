package com.rodwave.engine.mods

import com.rodwave.engine.fs.FsException
import com.rodwave.engine.fs.VirtualFile
import com.rodwave.engine.fs.ensureDirectory
import com.rodwave.engine.fs.readBytes
import com.rodwave.engine.fs.readText
import com.rodwave.engine.fs.resolve
import com.rodwave.engine.fs.sha256
import com.rodwave.engine.fs.writeFile
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/**
 * Persistent state of the Mod Manager inside Rodwave's private storage:
 *
 * ```
 * library/<modId>/mod.json, library/<modId>/files/...
 * state/installed.json
 * backups/<operationId>/<n>.bak
 * operations/<operationId>.json
 * ```
 */
class ModStore(private val root: VirtualFile) {
    private val json = Json { prettyPrint = true; ignoreUnknownKeys = true; encodeDefaults = true }

    // ------------------------------------------------------------------ library

    fun mods(): List<ManagedMod> {
        val dir = root.resolve("library") ?: return emptyList()
        return dir.list().filter { it.isDirectory }.mapNotNull { modDir ->
            modDir.child("mod.json")?.let { f ->
                runCatching { json.decodeFromString(ManagedMod.serializer(), f.readText()) }.getOrNull()
            }
        }.sortedByDescending { it.importedAt }
    }

    fun mod(id: String): ManagedMod? = mods().firstOrNull { it.id == id }

    fun saveMod(mod: ManagedMod) {
        root.writeFile("library/${mod.id}/mod.json", json.encodeToString(ManagedMod.serializer(), mod).toByteArray())
    }

    fun writeLibraryFile(modId: String, relative: String, data: ByteArray) {
        root.writeFile("library/$modId/files/$relative", data)
    }

    /** Reads a library file and checks it still matches the hash recorded at import. */
    fun readLibraryFile(mod: ManagedMod, file: ModFile): ByteArray {
        val f = root.resolve("library/${mod.id}/files/${file.libraryPath}")
            ?: throw FsException("Library copy of ${file.libraryPath} is missing")
        val data = f.readBytes()
        if (data.sha256() != file.sha256) throw FsException("Library copy of ${file.libraryPath} is corrupted (hash mismatch)")
        return data
    }

    fun deleteMod(id: String) {
        root.resolve("library/$id")?.delete()
    }

    // ------------------------------------------------------------------ ownership registry

    fun installedFiles(): List<InstalledFileRecord> {
        val f = root.resolve("state/installed.json") ?: return emptyList()
        return runCatching { json.decodeFromString(ListSerializer(InstalledFileRecord.serializer()), f.readText()) }.getOrDefault(emptyList())
    }

    fun saveInstalledFiles(records: List<InstalledFileRecord>) {
        root.writeFile("state/installed.json", json.encodeToString(ListSerializer(InstalledFileRecord.serializer()), records).toByteArray())
    }

    fun owner(destination: DestinationKind, targetPath: String): InstalledFileRecord? =
        installedFiles().firstOrNull { it.destination == destination && it.targetPath.equals(targetPath, ignoreCase = true) }

    // ------------------------------------------------------------------ backups and operations

    fun writeBackup(operationId: String, index: Int, data: ByteArray): String {
        val name = "backups/$operationId/$index.bak"
        root.writeFile(name, data)
        return name
    }

    fun readBackup(entry: BackupEntry): ByteArray {
        val f = root.resolve(entry.backupFile) ?: throw FsException("Backup ${entry.backupFile} is missing")
        val data = f.readBytes()
        if (data.sha256() != entry.sha256) throw FsException("Backup ${entry.backupFile} is corrupted (hash mismatch)")
        return data
    }

    fun saveOperation(record: OperationRecord) {
        root.ensureDirectory("operations")
        root.writeFile("operations/${record.id}.json", json.encodeToString(OperationRecord.serializer(), record).toByteArray())
    }

    fun operations(): List<OperationRecord> {
        val dir = root.resolve("operations") ?: return emptyList()
        return dir.list().filter { it.name.endsWith(".json") }.mapNotNull {
            runCatching { json.decodeFromString(OperationRecord.serializer(), it.readText()) }.getOrNull()
        }.sortedByDescending { it.startedAt }
    }

    fun operation(id: String): OperationRecord? = root.resolve("operations/$id.json")?.let {
        runCatching { json.decodeFromString(OperationRecord.serializer(), it.readText()) }.getOrNull()
    }
}
