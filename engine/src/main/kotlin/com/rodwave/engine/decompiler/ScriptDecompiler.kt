package com.rodwave.engine.decompiler

import com.rodwave.engine.RodwaveEngine
import com.rodwave.engine.compiler.CompileOptions
import com.rodwave.engine.compiler.PredefinedGlobals
import com.rodwave.engine.compiler.ScriptCompiler
import com.rodwave.engine.diagnostics.Diagnostic
import com.rodwave.engine.diagnostics.DiagnosticSink
import com.rodwave.engine.opcode.OpcodeDatabase
import com.rodwave.engine.opcode.ParamDefinition
import com.rodwave.engine.opcode.ParamSource
import com.rodwave.engine.opcode.ParamType
import com.rodwave.engine.scm.ArrayElementType
import com.rodwave.engine.scm.ArrayOperand
import com.rodwave.engine.scm.DataType
import com.rodwave.engine.scm.DecodeResult
import com.rodwave.engine.scm.EndOfArgs
import com.rodwave.engine.scm.FloatOperand
import com.rodwave.engine.scm.Instruction
import com.rodwave.engine.scm.InstructionDecoder
import com.rodwave.engine.scm.IntOperand
import com.rodwave.engine.scm.MainScmHeader
import com.rodwave.engine.scm.MainScmParser
import com.rodwave.engine.scm.Opcodes
import com.rodwave.engine.scm.Operand
import com.rodwave.engine.scm.ScriptFormat
import com.rodwave.engine.scm.StringOperand
import com.rodwave.engine.scm.VarOperand
import com.rodwave.engine.scm.VarStorage
import java.math.BigDecimal
import java.util.TreeMap

data class DecompileOptions(
    val format: ScriptFormat = ScriptFormat.CLEO_ANDROID_AUTO,
    /** Recompile the produced text and compare it with the input bytes. */
    val verifyRoundTrip: Boolean = true,
    val sourceName: String? = null,
    /** Print `$PLAYER_CHAR`, `TIMERA` and similar names instead of raw numbers. */
    val useAliases: Boolean = true,
)

enum class RoundTripStatus {
    /** Recompiling the output reproduced the input byte for byte. */
    IDENTICAL,
    /** Recompiling worked but produced different bytes. */
    DIFFERENT,
    /** The output could not be recompiled. */
    NOT_RECOMPILABLE,
    NOT_CHECKED,
}

data class DecompileResult(
    val text: String,
    val diagnostics: List<Diagnostic>,
    val instructions: List<Instruction>,
    /** Byte ranges emitted as `hex` data. */
    val dataBlocks: List<IntRange>,
    /** Label names by offset. */
    val labels: Map<Int, String>,
    val roundTrip: RoundTripStatus,
    /** First differing offset when [roundTrip] is [RoundTripStatus.DIFFERENT]. */
    val firstDifference: Int? = null,
    val totalBytes: Int,
    /** Opcodes met on reachable paths that the opcode database does not define. */
    val unknownOpcodes: Set<Int> = emptySet(),
) {
    val codeBytes: Int get() = instructions.sumOf { it.length }
    val coverage: Double get() = if (totalBytes == 0) 1.0 else codeBytes.toDouble() / totalBytes
}

data class MainScmDecompileResult(
    val header: MainScmHeader?,
    val text: String,
    val diagnostics: List<Diagnostic>,
    val instructionCount: Int,
)

/** How jump targets in a code region are encoded. */
enum class LabelMode {
    /** Headerless CLEO script: targets are negative offsets from the script start. */
    CLEO,
    /** main.scm main section: targets are absolute file offsets. */
    MAIN,
    /** main.scm mission: negative = relative to the mission start, positive = absolute. */
    MISSION,
}

/**
 * Turns script bytecode back into editable source.
 *
 * Code is found by following control flow from the entry point (and every jump/call target).
 * Unreferenced bytes are decoded linearly only when they form complete instructions; otherwise
 * they are emitted as `hex ... end` blocks, so arbitrary data embedded in a script is preserved.
 * Instructions whose exact encoding the source syntax cannot express are also emitted as `hex`.
 */
class ScriptDecompiler(
    private val database: OpcodeDatabase,
    private val globals: Map<String, Int> = PredefinedGlobals.SAN_ANDREAS,
) {
    private val decoder = InstructionDecoder(database)

    fun decompile(bytes: ByteArray, options: DecompileOptions = DecompileOptions()): DecompileResult {
        val sink = DiagnosticSink(options.sourceName)
        if (bytes.isEmpty()) {
            sink.error("D001", "The file is empty")
            return DecompileResult("", sink.diagnostics, emptyList(), emptyList(), emptyMap(), RoundTripStatus.NOT_CHECKED, totalBytes = 0)
        }
        if (MainScmParser.looksLikeMainScm(bytes)) {
            sink.binaryWarning("D002", "This file looks like a main.scm (it has a segmented header); use the main.scm inspector instead", 0)
        }
        val analysis = analyze(bytes, 0, bytes.size, LabelMode.CLEO, base = 0, sink = sink, entryPoints = listOf(0))
        val text = buildString {
            appendLine("// Decompiled by ${RodwaveEngine.NAME} ${RodwaveEngine.VERSION}")
            appendLine("// Source: ${options.sourceName ?: "script"} (${bytes.size} bytes) — opcodes: ${database.info.name} ${database.info.version}")
            if (options.format.isHeaderless) {
                appendLine("{\$CLEO .${options.format.extension}}")
            }
            append(render(bytes, analysis, options))
        }
        var status = RoundTripStatus.NOT_CHECKED
        var firstDiff: Int? = null
        if (options.verifyRoundTrip && options.format.isHeaderless) {
            val result = ScriptCompiler(database).compile(text, CompileOptions(format = options.format, fileName = options.sourceName, globals = globals))
            val out = result.bytes
            status = when {
                out == null -> {
                    result.errors.take(3).forEach { e ->
                        sink.warning("D010", "Round-trip check: the decompiled text does not recompile (${e.message}, line ${e.line})")
                    }
                    RoundTripStatus.NOT_RECOMPILABLE
                }
                out.contentEquals(bytes) -> RoundTripStatus.IDENTICAL
                else -> {
                    firstDiff = (0 until minOf(out.size, bytes.size)).firstOrNull { out[it] != bytes[it] } ?: minOf(out.size, bytes.size)
                    sink.warning("D011", "Round-trip check: recompiling the output differs from the input at offset $firstDiff")
                    RoundTripStatus.DIFFERENT
                }
            }
        }
        return DecompileResult(
            text = text,
            diagnostics = sink.diagnostics,
            instructions = analysis.code.values.toList(),
            dataBlocks = analysis.data,
            labels = analysis.labels.mapValues { it.value.name },
            roundTrip = status,
            firstDifference = firstDiff,
            totalBytes = bytes.size,
            unknownOpcodes = analysis.unknownOpcodes,
        )
    }

    /** Read-only listing of a main.scm: header summary, main code and missions. */
    fun decompileMainScm(bytes: ByteArray, sourceName: String? = null): MainScmDecompileResult {
        val sink = DiagnosticSink(sourceName)
        val parsed = MainScmParser.parse(bytes, sourceName)
        sink.addAll(parsed.diagnostics)
        val header = parsed.header ?: return MainScmDecompileResult(null, "", sink.diagnostics, 0)
        val options = DecompileOptions(format = ScriptFormat.MAIN_SCM, verifyRoundTrip = false, sourceName = sourceName)
        var count = 0
        val text = buildString {
            appendLine("// main.scm listing produced by ${RodwaveEngine.NAME} ${RodwaveEngine.VERSION} (read-only: Rodwave does not rebuild main.scm)")
            appendLine("// Target game: '${header.targetGameChar}'  Global variable space: ${header.globalVariableSpace.first}..${header.globalVariableSpace.last}")
            appendLine("// Models: ${header.models.size}  Missions: ${header.missionCount}  Streamed scripts: ${header.streamedScripts.size}")
            header.segments.forEach { s -> appendLine("//   segment ${s.index + 1} @${s.offset}..${s.end}: ${s.title}") }
            for (section in header.codeSections(bytes.size)) {
                appendLine()
                appendLine("// ===== ${section.name} (${section.start}..${section.end}, ${section.size} bytes) =====")
                val mode = if (section.isMission) LabelMode.MISSION else LabelMode.MAIN
                val analysis = analyze(bytes, section.start, section.end, mode, base = section.start, sink = sink, entryPoints = listOf(section.start))
                count += analysis.code.size
                append(render(bytes, analysis, options))
            }
        }
        return MainScmDecompileResult(header, text, sink.diagnostics, count)
    }

    // ------------------------------------------------------------------ analysis

    private data class LabelInfo(val name: String, val isData: Boolean)

    private class Analysis(
        val start: Int,
        val end: Int,
        val code: TreeMap<Int, Instruction>,
        val unreachable: Set<Int>,
        val data: List<IntRange>,
        val labels: TreeMap<Int, LabelInfo>,
        /** Resolved label for (instruction offset, operand index). */
        val operandTargets: Map<Pair<Int, Int>, Int>,
        val decodeErrors: Map<Int, String>,
        val mode: LabelMode,
        val unknownOpcodes: Set<Int>,
    )

    private fun targetOf(value: Int, mode: LabelMode, base: Int): Int? = when (mode) {
        LabelMode.CLEO -> if (value < 0) base - value else null
        LabelMode.MAIN -> if (value >= 0) value else null
        LabelMode.MISSION -> if (value < 0) base - value else value
    }

    private fun analyze(bytes: ByteArray, start: Int, end: Int, mode: LabelMode, base: Int, sink: DiagnosticSink, entryPoints: List<Int>): Analysis {
        val code = TreeMap<Int, Instruction>()
        val labels = TreeMap<Int, LabelInfo>()
        val dataTargets = HashSet<Int>()
        val codeTargets = HashSet<Int>()
        val operandTargets = HashMap<Pair<Int, Int>, Int>()
        val errors = HashMap<Int, String>()
        val unknown = HashSet<Int>()
        val work = ArrayDeque(entryPoints)

        fun inside(off: Int) = off in start until end

        fun collectTargets(ins: Instruction) {
            val def = ins.definition ?: return
            var pi = 0
            for ((oi, op) in ins.operands.withIndex()) {
                val param = def.params.getOrNull(pi)
                val isLabelParam = param?.type == ParamType.LABEL
                if (param?.type != ParamType.ARGUMENTS) pi++
                if (!isLabelParam || op !is IntOperand) continue
                val target = targetOf(op.value, mode, base)
                when {
                    target == null -> sink.binaryWarning("D020", "${ins.hexOpcode}: label value ${op.value} cannot be a target in this context", ins.offset)
                    !inside(target) && (mode == LabelMode.CLEO) -> sink.binaryWarning("D021", "${ins.hexOpcode}: jump target $target is outside the script", ins.offset)
                    else -> {
                        operandTargets[ins.offset to oi] = target
                        if (ins.opcode == Opcodes.STORE_LABEL_POINTER) dataTargets += target else codeTargets += target
                        if (inside(target) && ins.opcode != Opcodes.STORE_LABEL_POINTER) work += target
                    }
                }
            }
        }

        // 1. Follow control flow.
        while (work.isNotEmpty()) {
            val off = work.removeFirst()
            if (!inside(off) || code.containsKey(off) || errors.containsKey(off)) continue
            val prev = code.floorEntry(off)
            if (prev != null && off < prev.value.end) {
                sink.binaryWarning("D022", "A jump lands inside the instruction at ${prev.key}", off)
                continue
            }
            when (val r = decoder.decode(bytes, off, end)) {
                is DecodeResult.Error -> {
                    errors[off] = r.message
                    if (r.offset == off && r.opcodeWord != null && database[r.opcodeWord and 0x7FFF] == null) {
                        unknown += r.opcodeWord and 0x7FFF
                    }
                    sink.binaryWarning("D023", "Could not decode code at $off: ${r.message}", r.offset)
                }
                is DecodeResult.Ok -> {
                    val ins = r.instruction
                    val next = code.ceilingKey(off + 1)
                    if (next != null && next < ins.end) {
                        sink.binaryWarning("D024", "Instruction at $off overlaps the instruction at $next", off)
                        errors[off] = "overlapping instruction"
                        continue
                    }
                    code[off] = ins
                    collectTargets(ins)
                    if (ins.opcode !in Opcodes.TERMINATORS) work += ins.end
                }
            }
        }

        // 2. Classify the gaps between reachable instructions.
        val unreachable = HashSet<Int>()
        val data = ArrayList<IntRange>()
        var cursor = start
        val gaps = ArrayList<IntRange>()
        for ((off, ins) in code) {
            if (off > cursor) gaps += cursor until off
            cursor = maxOf(cursor, ins.end)
        }
        if (cursor < end) gaps += cursor until end
        for (gap in gaps) {
            val referencedAsData = dataTargets.any { it in gap }
            val linear = if (referencedAsData) null else decodeLinear(bytes, gap)
            if (linear != null) {
                linear.forEach { ins ->
                    code[ins.offset] = ins
                    unreachable += ins.offset
                    collectTargets(ins)
                }
            } else {
                data += gap
            }
        }

        // 3. Labels: only at instruction starts or inside data blocks.
        for (t in codeTargets + dataTargets) {
            val isData = data.any { t in it }
            val isInstruction = code.containsKey(t)
            if (isInstruction || isData || t == end) {
                labels[t] = LabelInfo((if (isData && !isInstruction) "DATA_" else "LABEL_") + t, isData && !isInstruction)
            }
        }
        // Drop targets that cannot carry a label (inside an instruction or outside the region).
        val placeable = operandTargets.filterValues { it in labels }

        return Analysis(start, end, code, unreachable, data.sortedBy { it.first }, labels, placeable, errors, mode, unknown)
    }

    /** Decodes [range] instruction by instruction; returns null unless it is filled exactly. */
    private fun decodeLinear(bytes: ByteArray, range: IntRange): List<Instruction>? {
        val out = ArrayList<Instruction>()
        var off = range.first
        while (off <= range.last) {
            val r = decoder.decode(bytes, off, range.last + 1)
            if (r !is DecodeResult.Ok) return null
            out += r.instruction
            off = r.instruction.end
        }
        return if (off == range.last + 1) out else null
    }

    // ------------------------------------------------------------------ rendering

    private fun render(bytes: ByteArray, a: Analysis, options: DecompileOptions): String {
        val sb = StringBuilder()
        val items = TreeMap<Int, Any>()
        a.code.forEach { (off, ins) -> items[off] = ins }
        a.data.forEach { r -> items[r.first] = r }
        var conditionsLeft = 0
        var lastWasUnreachable = false
        for ((off, item) in items) {
            when (item) {
                is Instruction -> {
                    a.labels[off]?.let { sb.append(':').appendLine(it.name) }
                    val unreachable = off in a.unreachable
                    if (unreachable && !lastWasUnreachable) sb.appendLine("// unreachable code (decoded linearly)")
                    lastWasUnreachable = unreachable
                    val indent = if (conditionsLeft > 0) "  " else ""
                    if (conditionsLeft > 0) conditionsLeft--
                    sb.appendLine(formatOrHex(bytes, item, a, indent, options))
                    if (item.opcode == Opcodes.ANDOR) {
                        conditionsLeft = Opcodes.conditionCount((item.operands.firstOrNull() as? IntOperand)?.value ?: -1) ?: 0
                    }
                }
                is IntRange -> {
                    lastWasUnreachable = false
                    renderData(bytes, item, a, sb)
                }
            }
        }
        // A label pointing just past the last byte.
        a.labels[a.end]?.let { sb.append(':').appendLine(it.name) }
        return sb.toString()
    }

    private fun renderData(bytes: ByteArray, range: IntRange, a: Analysis, sb: StringBuilder) {
        // Split at labels that point into the block.
        val cuts = (listOf(range.first) + a.labels.keys.filter { it in range && it != range.first } + listOf(range.last + 1)).distinct().sorted()
        for (i in 0 until cuts.size - 1) {
            val from = cuts[i]
            val to = cuts[i + 1]
            a.labels[from]?.let { sb.append(':').appendLine(it.name) }
            val chunk = bytes.copyOfRange(from, to)
            val note = when {
                String(chunk, Charsets.ISO_8859_1).contains("__SBFTR") -> "Sanny Builder footer (metadata, not code)"
                a.decodeErrors.containsKey(from) -> "could not decode: ${a.decodeErrors[from]}"
                else -> "data (${chunk.size} bytes)"
            }
            sb.appendLine("// $note")
            sb.appendLine("hex")
            chunk.toList().chunked(16).forEach { row ->
                sb.append("  ").appendLine(row.joinToString(" ") { (it.toInt() and 0xFF).toString(16).uppercase().padStart(2, '0') })
            }
            sb.appendLine("end")
        }
    }

    private fun formatOrHex(bytes: ByteArray, ins: Instruction, a: Analysis, indent: String, options: DecompileOptions): String {
        val text = formatInstruction(ins, a, indent, options)
        if (text != null) return text
        val raw = bytes.copyOfRange(ins.offset, ins.end).joinToString(" ") { (it.toInt() and 0xFF).toString(16).uppercase().padStart(2, '0') }
        val def = ins.definition
        return "// ${ins.hexOpcode}: ${def?.keyword ?: "?"} — encoding not expressible in source, kept as raw bytes\nhex $raw end"
    }

    /** Formats one instruction, or returns null when re-compiling the text would not reproduce its bytes. */
    private fun formatInstruction(ins: Instruction, a: Analysis, indent: String, options: DecompileOptions): String? {
        val def = ins.definition ?: return null
        val parts = ArrayList<String>()
        var pi = 0
        for ((oi, op) in ins.operands.withIndex()) {
            if (op === EndOfArgs) continue
            val param = def.params.getOrNull(pi)
            val inVariadic = param?.type == ParamType.ARGUMENTS
            if (!inVariadic) pi++
            val effectiveParam = if (inVariadic) null else param
            val labelTarget = a.operandTargets[ins.offset to oi]
            parts += formatOperand(op, effectiveParam, labelTarget, a, options) ?: return null
        }
        val body = if (parts.isEmpty()) def.keyword else def.keyword + " " + parts.joinToString(" ")
        return "${ins.hexOpcode}: $indent$body"
    }

    private fun formatOperand(op: Operand, param: ParamDefinition?, labelTarget: Int?, a: Analysis, options: DecompileOptions): String? {
        val type = param?.type ?: ParamType.ANY
        // Literal/variable constraints the compiler enforces.
        if (param != null) {
            val isVar = op is VarOperand || op is ArrayOperand
            if (param.isOutput && !isVar) return null
            when (param.source) {
                ParamSource.LITERAL -> if (isVar) return null
                ParamSource.VAR_GLOBAL -> if (!isVar || !op.type.isGlobal) return null
                ParamSource.VAR_LOCAL -> if (!isVar || op.type.isGlobal) return null
                ParamSource.VAR_ANY -> if (!isVar) return null
                ParamSource.ANY -> Unit
            }
        }
        return when (op) {
            is IntOperand -> when {
                type == ParamType.LABEL -> {
                    if (op.type != DataType.INT32) return null
                    labelTarget?.let { a.labels[it]?.name }?.let { "@$it" } ?: op.value.toString()
                }
                type == ParamType.FLOAT || type.isStringLike -> null
                IntOperand.minimalType(op.value) != op.type -> null
                else -> op.value.toString()
            }
            is FloatOperand -> if (type == ParamType.FLOAT || type == ParamType.ANY) formatFloat(op.value) else null
            is StringOperand -> formatString(op, type)
            is VarOperand -> {
                val stringVar = op.type.storage != VarStorage.NUMBER
                if (type.isStringLike && !stringVar || type.isNumeric && stringVar) return null
                formatVar(op.type.isGlobal, op.index, op.type.storage, options)
            }
            is ArrayOperand -> {
                val stringVar = op.type.storage != VarStorage.NUMBER
                if (type.isStringLike && !stringVar || type.isNumeric && stringVar) return null
                val elem = op.elementType ?: return null
                if (op.size == 0) return null
                // The element suffix must agree with the array's string kind.
                val expectedStorage = when (elem) {
                    ArrayElementType.STRING8 -> VarStorage.STRING8
                    ArrayElementType.STRING16 -> VarStorage.STRING16
                    else -> VarStorage.NUMBER
                }
                if (expectedStorage != op.type.storage) return null
                val base = formatVar(op.type.isGlobal, op.base, op.type.storage, options.copy(useAliases = false)) ?: return null
                val index = formatVar(op.indexIsGlobal, op.indexVar, VarStorage.NUMBER, options.copy(useAliases = false)) ?: return null
                "$base($index,${op.size}${elem.suffix})"
            }
            EndOfArgs -> ""
        }
    }

    private fun formatVar(global: Boolean, index: Int, storage: VarStorage, options: DecompileOptions): String? {
        val prefix = when (storage) {
            VarStorage.STRING8 -> "s"
            VarStorage.STRING16 -> "v"
            else -> ""
        }
        return if (global) {
            if (options.useAliases && storage == VarStorage.NUMBER && index % 4 == 0) {
                globals.entries.firstOrNull { it.value * 4 == index }?.let { return "\$${it.key}" }
            }
            if (index % 4 == 0) "$prefix\$${index / 4}" else "$prefix&$index"
        } else {
            if (options.useAliases && storage == VarStorage.NUMBER) {
                if (index == 32) return "TIMERA"
                if (index == 33) return "TIMERB"
            }
            "$index@" + when (storage) {
                VarStorage.STRING8 -> "s"
                VarStorage.STRING16 -> "v"
                else -> ""
            }
        }
    }

    private fun formatString(op: StringOperand, type: ParamType): String? {
        if (type.isNumeric || type == ParamType.LABEL) return null
        if (!op.isCanonical) return null
        val text = op.text
        if (!text.all { it.code in 0x20..0xFF }) return null
        return when (op.type) {
            DataType.STRING_VARLEN -> if ('"' in text) null else "\"$text\""
            DataType.STRING8 -> if ('\'' in text || text.length > 7) null else "'$text'"
            DataType.STRING16 -> if ('\'' in text || text.length !in 8..15) null else "'$text'"
            else -> null
        }
    }

    companion object {
        /** Shortest decimal text that parses back to exactly [value], without exponent notation. */
        fun formatFloat(value: Float): String? {
            if (!value.isFinite()) return null
            if (value == 0f) return if (1f / value < 0) "-0.0" else "0.0"
            val plain = BigDecimal(value.toString()).toPlainString()
            val text = if ('.' in plain) plain else "$plain.0"
            return if (text.toFloat().toRawBits() == value.toRawBits()) text else null
        }
    }
}
