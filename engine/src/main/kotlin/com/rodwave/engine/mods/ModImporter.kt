package com.rodwave.engine.mods

import com.rodwave.engine.analysis.ScriptAnalyzer
import com.rodwave.engine.analysis.ScriptVerdict
import com.rodwave.engine.archive.ArchiveFile
import com.rodwave.engine.archive.SafeZip
import com.rodwave.engine.compat.NativeModInspector
import com.rodwave.engine.elf.ElfFile
import com.rodwave.engine.fs.sha256
import com.rodwave.engine.opcode.OpcodeDatabase
import kotlinx.serialization.json.Json

data class ImportResult(val mod: ManagedMod?, val messages: List<String>, val rejectedEntries: List<String> = emptyList())

/**
 * Turns user files into managed mods stored in Rodwave's library. Importing never installs anything.
 */
class ModImporter(
    private val store: ModStore,
    private val database: OpcodeDatabase,
    private val clock: () -> Long = System::currentTimeMillis,
    private val newId: () -> String = { java.util.UUID.randomUUID().toString() },
) {
    private val json = Json { ignoreUnknownKeys = true }

    fun import(fileName: String, data: ByteArray): ImportResult {
        val safeName = fileName.substringAfterLast('/').substringAfterLast('\\').ifBlank { "file" }
        return if (SafeZip.isZip(data)) importArchive(safeName, data) else importSingle(safeName, data)
    }

    private fun classify(name: String, data: ByteArray): Pair<ModKind, DestinationKind> {
        val lower = name.lowercase()
        return when {
            ElfFile.isElf(data) || lower.endsWith(".so") -> ModKind.AML_MOD to DestinationKind.AML_MODS
            lower.endsWith(".csa") || lower.endsWith(".csi") -> ModKind.CLEO_SCRIPT to DestinationKind.CLEO_SCRIPTS
            lower.endsWith(".fxt") -> ModKind.CLEO_TEXT to DestinationKind.CLEO_SCRIPTS
            lower.endsWith(".ini") -> ModKind.CONFIG to DestinationKind.AML_CONFIGS
            else -> ModKind.OTHER to DestinationKind.EXPORT
        }
    }

    private fun describe(name: String, data: ByteArray, kind: ModKind): List<String> = when (kind) {
        ModKind.CLEO_SCRIPT -> {
            val r = ScriptAnalyzer.analyze(data, name, database)
            listOf("$name: ${r.verdict.label}") + r.findings.map { "$name: ${it.title} — ${it.detail}" }
        }
        ModKind.AML_MOD -> {
            val info = NativeModInspector.inspect(name, data)
            val parts = mutableListOf<String>()
            parts += when {
                info.error != null -> "$name: ${info.error}"
                info.isAmlMod -> "$name: AML mod for ${info.abi?.androidName ?: "unknown ABI"}"
                else -> "$name: not an AML mod (no __GetModInfo export)"
            }
            if (info.declaresDependencies && info.guidCandidates.isNotEmpty()) {
                parts += "$name: declares dependencies; GUID strings found: ${info.guidCandidates.take(8).joinToString()}"
            }
            parts
        }
        else -> emptyList()
    }

    private fun importSingle(name: String, data: ByteArray): ImportResult {
        if (data.isEmpty()) return ImportResult(null, listOf("$name is empty"))
        val (kind, dest) = classify(name, data)
        if (kind == ModKind.CLEO_SCRIPT && ScriptAnalyzer.analyze(data, name, database).verdict == ScriptVerdict.NOT_A_SCRIPT) {
            return ImportResult(null, listOf("$name is not a compiled script (it looks like source text). Compile it in the editor first."))
        }
        val id = newId()
        store.writeLibraryFile(id, name, data)
        val findings = describe(name, data, kind)
        val mod = ManagedMod(
            id = id,
            name = name.substringBeforeLast('.').ifBlank { name },
            kind = kind,
            category = defaultCategory(kind),
            sourceName = name,
            importedAt = clock(),
            files = listOf(ModFile(name, dest, name, data.sha256(), data.size.toLong(), kind)),
            findings = findings,
        )
        store.saveMod(mod)
        return ImportResult(mod, listOf("Imported $name as ${kind.label}") + findings)
    }

    private fun importArchive(name: String, data: ByteArray): ImportResult {
        val contents = SafeZip.read(data.inputStream())
        val messages = mutableListOf<String>()
        contents.rejected.forEach { messages += "Rejected '${it.path}': ${it.reason}" }
        val manifest = contents.files.firstOrNull { it.name.equals("rodwave-mod.json", true) }?.let {
            runCatching { json.decodeFromString(ModManifest.serializer(), it.data.toString(Charsets.UTF_8)) }
                .onFailure { e -> messages += "Ignored invalid rodwave-mod.json: ${e.message}" }
                .getOrNull()
        }
        val readme = contents.files.firstOrNull { val n = it.name.lowercase(); n.startsWith("readme") && (n.endsWith(".txt") || n.endsWith(".md")) }
        val payload = contents.files.filter { it !== readme && !it.name.equals("rodwave-mod.json", true) }
        if (payload.isEmpty()) return ImportResult(null, messages + "The archive contains no installable files", contents.rejected.map { it.path })

        val id = newId()
        val files = ArrayList<ModFile>()
        val findings = ArrayList<String>()
        // Targets keep their layout relative to the archive's common folder; a leading cleo/, mods/,
        // configs/ or scripts/ folder is dropped because archives often mirror the game's folders.
        val commonPrefix = commonDirectory(payload)
        for (f in payload) {
            val (kind, dest) = classify(f.name, f.data)
            val relative = f.path.removePrefix(commonPrefix)
            val target = stripDestinationFolder(relative)
            store.writeLibraryFile(id, f.path, f.data)
            files += ModFile(f.path, dest, target, f.data.sha256(), f.data.size.toLong(), kind)
            findings += describe(f.name, f.data, kind)
        }
        val kinds = files.map { it.kind }.toSet()
        val mod = ManagedMod(
            id = id,
            name = manifest?.name ?: name.substringBeforeLast('.'),
            kind = if (kinds.size == 1) kinds.first() else ModKind.BUNDLE,
            category = manifest?.category ?: defaultCategory(if (kinds.size == 1) kinds.first() else ModKind.BUNDLE),
            version = manifest?.version,
            author = manifest?.author,
            description = manifest?.description.orEmpty(),
            sourceName = name,
            importedAt = clock(),
            files = files,
            requires = manifest?.requires.orEmpty(),
            findings = findings,
            instructions = readme?.data?.toString(Charsets.UTF_8)?.take(20_000),
        )
        store.saveMod(mod)
        messages += "Imported ${files.size} file(s) from $name"
        return ImportResult(mod, messages + findings, contents.rejected.map { it.path })
    }

    private fun commonDirectory(files: List<ArchiveFile>): String {
        val dirs = files.map { it.path.substringBeforeLast('/', "") }
        if (dirs.any { it.isEmpty() }) return ""
        val first = dirs.first().split('/')
        var n = first.size
        for (d in dirs) {
            val parts = d.split('/')
            n = minOf(n, parts.zip(first).takeWhile { (a, b) -> a == b }.size)
        }
        return if (n == 0) "" else first.take(n).joinToString("/") + "/"
    }

    /** `cleo/x.csa` -> `x.csa`, `mods/y.so` -> `y.so`: archives often mirror the game folder layout. */
    private fun stripDestinationFolder(path: String): String {
        val first = path.substringBefore('/', "")
        return if (first.lowercase() in setOf("cleo", "mods", "configs", "scripts") && path.contains('/')) path.substringAfter('/') else path
    }

    private fun defaultCategory(kind: ModKind) = when (kind) {
        ModKind.CLEO_SCRIPT, ModKind.CLEO_TEXT -> "Scripts"
        ModKind.AML_MOD -> "Native mods"
        ModKind.CONFIG -> "Configs"
        else -> "Other"
    }
}
