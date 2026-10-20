package com.rodwave.studio.core

import com.rodwave.engine.fs.VirtualFile
import com.rodwave.engine.fs.readText
import com.rodwave.engine.fs.resolve
import com.rodwave.engine.fs.writeFile
import com.rodwave.engine.opcode.CoreOpcodes
import com.rodwave.engine.opcode.LibraryImportException
import com.rodwave.engine.opcode.OpcodeDatabase
import com.rodwave.engine.opcode.SannyLibraryImporter

data class LibraryState(
    val database: OpcodeDatabase,
    /** The imported library on its own, if one is installed. */
    val imported: OpcodeDatabase?,
    val message: String,
)

/**
 * Manages the opcode database: the built-in core set, optionally merged with a Sanny Builder Library
 * file the user imported or downloaded. The library is never bundled with Rodwave.
 */
class OpcodeLibrary(private val storage: VirtualFile) {

    fun load(useImported: Boolean): LibraryState {
        val core = CoreOpcodes.database
        val commands = storage.resolve(COMMANDS)?.let { runCatching { it.readText() }.getOrNull() }
            ?: return LibraryState(core, null, "Built-in core set: ${core.size} commands")
        val enums = storage.resolve(ENUMS)?.let { runCatching { it.readText() }.getOrNull() }
        return try {
            val imported = SannyLibraryImporter.parse(commands, enums)
            if (useImported) {
                LibraryState(core.mergedWith(imported), imported, "${imported.info.name} ${imported.info.version}: ${imported.size} commands")
            } else {
                LibraryState(core, imported, "Imported library is installed but switched off")
            }
        } catch (e: LibraryImportException) {
            LibraryState(core, null, "The stored library could not be read (${e.message}); using the core set")
        }
    }

    /** Validates and stores library files; throws [LibraryImportException] for invalid input. */
    fun install(commandsJson: String, enumsJson: String?): OpcodeDatabase {
        val parsed = SannyLibraryImporter.parse(commandsJson, enumsJson)
        if (parsed.info.game != "sa_mobile") {
            throw LibraryImportException("This library is for '${parsed.info.game}', not 'sa_mobile' (GTA SA Mobile)")
        }
        storage.writeFile(COMMANDS, commandsJson.toByteArray())
        if (enumsJson != null) storage.writeFile(ENUMS, enumsJson.toByteArray())
        return parsed
    }

    /** Adds or replaces the enums file next to an installed commands file. */
    fun installEnums(enumsJson: String): OpcodeDatabase {
        val commands = storage.resolve(COMMANDS)?.readText() ?: throw LibraryImportException("Import the commands file (sa_mobile.json) first")
        val parsed = SannyLibraryImporter.parse(commands, enumsJson)
        if (parsed.enums.isEmpty()) throw LibraryImportException("No enums found in this file")
        storage.writeFile(ENUMS, enumsJson.toByteArray())
        return parsed
    }

    fun remove() {
        storage.resolve(COMMANDS)?.delete()
        storage.resolve(ENUMS)?.delete()
    }

    companion object {
        const val COMMANDS = "library/sa_mobile.json"
        const val ENUMS = "library/enums.json"
    }
}
