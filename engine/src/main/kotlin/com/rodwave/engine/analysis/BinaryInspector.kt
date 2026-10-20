package com.rodwave.engine.analysis

import com.rodwave.engine.archive.ArchiveContents
import com.rodwave.engine.archive.ArchiveException
import com.rodwave.engine.archive.SafeZip
import com.rodwave.engine.compat.NativeModInfo
import com.rodwave.engine.compat.NativeModInspector
import com.rodwave.engine.elf.ElfFile
import com.rodwave.engine.fs.sha256
import com.rodwave.engine.opcode.OpcodeDatabase
import com.rodwave.engine.scm.MainScmParser
import java.io.ByteArrayInputStream

enum class BinaryKind(val label: String) {
    ELF("ELF native library"),
    ZIP("ZIP archive"),
    MAIN_SCM("main.scm"),
    SCRIPT("Compiled script"),
    TEXT("Text file"),
    UNKNOWN("Unrecognised data"),
}

/** Everything the binary metadata viewer shows about one file. */
data class BinaryInfo(
    val name: String,
    val size: Int,
    val sha256: String,
    val kind: BinaryKind,
    val native: NativeModInfo? = null,
    val archive: ArchiveContents? = null,
    val archiveError: String? = null,
    val script: ScriptReport? = null,
    val textLines: Int? = null,
)

/**
 * Identifies a file by its content (never by its name alone) and gathers the metadata the
 * specialised inspectors provide. Nothing is executed or loaded.
 */
object BinaryInspector {
    fun inspect(name: String, bytes: ByteArray, database: OpcodeDatabase): BinaryInfo {
        val hash = bytes.sha256()
        return when {
            ElfFile.isElf(bytes) -> BinaryInfo(name, bytes.size, hash, BinaryKind.ELF, native = NativeModInspector.inspect(name, bytes))
            SafeZip.isZip(bytes) -> try {
                BinaryInfo(name, bytes.size, hash, BinaryKind.ZIP, archive = SafeZip.read(ByteArrayInputStream(bytes)))
            } catch (e: ArchiveException) {
                BinaryInfo(name, bytes.size, hash, BinaryKind.ZIP, archiveError = e.message)
            }
            MainScmParser.looksLikeMainScm(bytes) -> BinaryInfo(name, bytes.size, hash, BinaryKind.MAIN_SCM, script = ScriptAnalyzer.analyze(bytes, name, database))
            ScriptAnalyzer.looksLikeText(bytes) -> BinaryInfo(name, bytes.size, hash, BinaryKind.TEXT, textLines = bytes.count { it == '\n'.code.toByte() } + 1)
            else -> {
                val report = ScriptAnalyzer.analyze(bytes, name, database)
                val kind = if (report.verdict == ScriptVerdict.NOT_A_SCRIPT || report.instructionCount == 0) BinaryKind.UNKNOWN else BinaryKind.SCRIPT
                BinaryInfo(name, bytes.size, hash, kind, script = report)
            }
        }
    }

}
