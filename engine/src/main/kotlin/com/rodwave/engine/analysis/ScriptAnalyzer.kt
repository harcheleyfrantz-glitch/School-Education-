package com.rodwave.engine.analysis

import com.rodwave.engine.decompiler.DecompileOptions
import com.rodwave.engine.decompiler.ScriptDecompiler
import com.rodwave.engine.diagnostics.Severity
import com.rodwave.engine.elf.ElfFile
import com.rodwave.engine.opcode.OpcodeDatabase
import com.rodwave.engine.opcode.OpcodeDefinition
import com.rodwave.engine.scm.ArrayOperand
import com.rodwave.engine.scm.MainScmParser
import com.rodwave.engine.scm.ScriptFormat
import com.rodwave.engine.scm.StringOperand
import com.rodwave.engine.scm.VarOperand

enum class ScriptVerdict(val label: String) {
    READY("Uses only commands known for SA Mobile"),
    NEEDS_REVIEW("Needs review"),
    PC_SCRIPT("PC CLEO script — needs porting"),
    MAIN_SCM("main.scm file"),
    NOT_A_SCRIPT("Not a compiled script"),
}

data class Finding(val severity: Severity, val title: String, val detail: String)

data class PcCommandUse(val opcode: Int, val pcName: String, val mobileName: String?)

/** Static facts about a compiled script, used by the inspector and the mod manager. */
data class ScriptReport(
    val fileName: String?,
    val size: Int,
    val format: ScriptFormat?,
    val verdict: ScriptVerdict,
    val scriptName: String?,
    val instructionCount: Int,
    val dataBytes: Int,
    val coverage: Double,
    val opcodeCounts: Map<Int, Int>,
    val unknownOpcodes: Set<Int>,
    val pcCommands: List<PcCommandUse>,
    val cleoAndroidCommands: Set<Int>,
    val usesNativeMemory: Boolean,
    val usesTouch: Boolean,
    val usesCleoMenu: Boolean,
    val localVariables: Set<Int>,
    val globalVariables: Set<Int>,
    val findings: List<Finding>,
)

object ScriptAnalyzer {
    private val MEMORY_OPCODES = setOf(0x0DD2, 0x0DD3, 0x0DD4, 0x0DD7, 0x0DD8, 0x0DD9, 0x0DDA, 0x0DDE)
    private val TOUCH_OPCODES = setOf(0x0DE0, 0x0DE1, 0x00E1) + (0x0A51..0x0A56)
    private val MENU_OPCODES = setOf(0x0DF2, 0x0DF3)

    fun analyze(bytes: ByteArray, fileName: String?, database: OpcodeDatabase): ScriptReport {
        val format = fileName?.let(ScriptFormat::fromFileName)
        val findings = mutableListOf<Finding>()

        fun simple(verdict: ScriptVerdict, finding: Finding) = ScriptReport(
            fileName, bytes.size, format, verdict, null, 0, bytes.size, 0.0, emptyMap(), emptySet(), emptyList(),
            emptySet(), false, false, false, emptySet(), emptySet(), listOf(finding),
        )

        when {
            bytes.isEmpty() -> return simple(ScriptVerdict.NOT_A_SCRIPT, Finding(Severity.ERROR, "Empty file", "The file contains no data."))
            ElfFile.isElf(bytes) -> return simple(ScriptVerdict.NOT_A_SCRIPT, Finding(Severity.ERROR, "Native library", "This is an ELF library (.so), not a CLEO script. Manage it as an AML mod."))
            bytes.size >= 4 && bytes[0] == 'P'.code.toByte() && bytes[1] == 'K'.code.toByte() && bytes[2].toInt() == 3 && bytes[3].toInt() == 4 ->
                return simple(ScriptVerdict.NOT_A_SCRIPT, Finding(Severity.ERROR, "ZIP archive", "Import archives through the Mod Manager."))
            looksLikeText(bytes) -> return simple(
                ScriptVerdict.NOT_A_SCRIPT,
                Finding(Severity.ERROR, "Source text", "This file contains readable text, not bytecode. Open it in the editor and compile it."),
            )
            MainScmParser.looksLikeMainScm(bytes) -> return simple(
                ScriptVerdict.MAIN_SCM,
                Finding(Severity.INFO, "main.scm", "This file has a main.scm header. Use the main.scm listing to inspect it."),
            )
        }

        val mobile = ScriptDecompiler(database).decompile(bytes, DecompileOptions(verifyRoundTrip = false, sourceName = fileName))
        val pc = ScriptDecompiler(PcCleoOpcodes.pcView(database)).decompile(bytes, DecompileOptions(verifyRoundTrip = false, sourceName = fileName))

        val pcOnly = pc.instructions.filter { it.opcode in PcCleoOpcodes.ids }
        val pcCommands = pcOnly.map { it.opcode }.distinct().sorted().map { id ->
            PcCommandUse(id, PcCleoOpcodes.name(id) ?: "?", database[id]?.name)
        }
        val pcDecodesBetter = pc.codeBytes > mobile.codeBytes + 2 && pcOnly.isNotEmpty()

        val instructions = mobile.instructions
        val counts = instructions.groupingBy { it.opcode }.eachCount()
        val defs: List<OpcodeDefinition> = counts.keys.mapNotNull { database[it] }
        val cleoCommands = defs.filter { it.extension.equals(OpcodeDefinition.EXTENSION_CLEO, true) }.map { it.id }.toSet()
        val usesMemory = counts.keys.any { it in MEMORY_OPCODES }
        val usesTouch = counts.keys.any { it in TOUCH_OPCODES }
        val usesMenu = counts.keys.any { it in MENU_OPCODES }
        val locals = HashSet<Int>()
        val globals = HashSet<Int>()
        instructions.forEach { ins ->
            ins.operands.forEach { op ->
                when {
                    op is VarOperand && op.type.isLocal -> locals += op.index
                    op is VarOperand -> globals += op.index
                    op is ArrayOperand && op.type.isLocal -> locals += op.base
                    op is ArrayOperand -> globals += op.base
                }
            }
        }
        val scriptName = instructions.firstOrNull { it.opcode == 0x03A4 }?.operands?.firstOrNull()?.let { (it as? StringOperand)?.text }

        if (format == ScriptFormat.CLEO_PC) {
            findings += Finding(Severity.WARNING, "PC file extension", ".cs is the Windows CLEO extension. CLEO Android loads .csa (auto-start) and .csi (menu) files.")
        }
        if (pcDecodesBetter) {
            findings += Finding(
                Severity.ERROR, "Written for PC CLEO",
                "The file decodes as a Windows CLEO script (${pcCommands.joinToString { "%04X %s".format(it.opcode, it.pcName) }}). " +
                    "These commands do not exist in CLEO Android; the script must be ported.",
            )
        }
        val collisions = pcCommands.filter { it.opcode in PcCleoOpcodes.COLLIDING_IDS && it.mobileName != null }
        collisions.forEach {
            findings += Finding(
                Severity.WARNING, "Opcode %04X means different things".format(it.opcode),
                "On PC CLEO it is ${it.pcName}; in SA Mobile it is ${it.mobileName}.",
            )
        }
        if (mobile.unknownOpcodes.isNotEmpty()) {
            findings += Finding(
                Severity.WARNING, "Unknown commands",
                "Opcodes not in the current opcode database: ${mobile.unknownOpcodes.sorted().joinToString { "%04X".format(it) }}. " +
                    "Import the full Sanny Builder Library or treat the script as unsupported.",
            )
        }
        val unsupported = defs.filter { it.isUnsupported }
        if (unsupported.isNotEmpty()) {
            findings += Finding(Severity.WARNING, "Commands marked unsupported", unsupported.joinToString { "${it.hexId} ${it.name}" } + " are marked unsupported for this game.")
        }
        if (cleoCommands.isNotEmpty()) {
            findings += Finding(Severity.INFO, "Requires CLEO Android", "Uses CLEO Android extension commands: " + cleoCommands.sorted().joinToString { "%04X".format(it) } + ".")
        }
        if (usesMemory) {
            findings += Finding(
                Severity.WARNING, "Native memory access",
                "Reads/writes game memory or calls native functions. Addresses are specific to one game version and ABI (32-bit vs 64-bit).",
            )
        }
        if (usesMenu) findings += Finding(Severity.INFO, "CLEO menu", "Creates a CLEO Android touch menu (0DF2).")
        if (usesTouch) findings += Finding(Severity.INFO, "Touch input", "Reads touch zones or mobile widgets.")
        if (mobile.dataBlocks.isNotEmpty()) {
            findings += Finding(Severity.INFO, "Embedded data", "${mobile.dataBlocks.sumOf { it.last - it.first + 1 }} byte(s) are data blocks, not code.")
        }
        val localsTooHigh = locals.filter { it > 33 }
        if (format?.isHeaderless != false && localsTooHigh.isNotEmpty()) {
            findings += Finding(Severity.WARNING, "Local variables out of range", "Uses ${localsTooHigh.sorted().joinToString { "$it@" }}; CLEO scripts have 0@-31@ plus timers.")
        }

        val verdict = when {
            pcDecodesBetter -> ScriptVerdict.PC_SCRIPT
            mobile.unknownOpcodes.isNotEmpty() || unsupported.isNotEmpty() || mobile.coverage < 0.5 -> ScriptVerdict.NEEDS_REVIEW
            else -> ScriptVerdict.READY
        }
        return ScriptReport(
            fileName = fileName,
            size = bytes.size,
            format = format,
            verdict = verdict,
            scriptName = scriptName,
            instructionCount = instructions.size,
            dataBytes = mobile.dataBlocks.sumOf { it.last - it.first + 1 },
            coverage = mobile.coverage,
            opcodeCounts = counts,
            unknownOpcodes = mobile.unknownOpcodes,
            pcCommands = pcCommands,
            cleoAndroidCommands = cleoCommands,
            usesNativeMemory = usesMemory,
            usesTouch = usesTouch,
            usesCleoMenu = usesMenu,
            localVariables = locals,
            globalVariables = globals,
            findings = findings,
        )
    }

    /** Heuristic: mostly printable text with line breaks, as source files are. */
    fun looksLikeText(bytes: ByteArray): Boolean {
        if (bytes.size < 8) return false
        val sample = bytes.take(4096)
        val printable = sample.count { val c = it.toInt() and 0xFF; c in 0x20..0x7E || c == 0x0A || c == 0x0D || c == 0x09 }
        return printable >= sample.size * 0.97 && sample.any { it.toInt() == 0x0A }
    }
}
