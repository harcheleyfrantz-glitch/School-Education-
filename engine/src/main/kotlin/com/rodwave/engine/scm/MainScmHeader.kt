package com.rodwave.engine.scm

import com.rodwave.engine.diagnostics.Diagnostic
import com.rodwave.engine.diagnostics.DiagnosticSink

/** One header segment: a GOTO over a data block, followed by an id byte (except the first). */
data class ScmSegment(
    val index: Int,
    val offset: Int,
    /** Jump target = first byte after this segment. */
    val end: Int,
    /** Byte following the GOTO: target game id for segment 0, segment number for the others. */
    val marker: Int,
    val title: String,
)

data class StreamedScriptEntry(val name: String, val offset: Int, val size: Int)

data class MainScmHeader(
    val segments: List<ScmSegment>,
    /** Target game identifier byte of the first segment (`'s'` for San Andreas). */
    val targetGame: Int,
    val globalVariableSpace: IntRange,
    val models: List<String>,
    val mainScriptSize: Int?,
    val largestMissionSize: Int?,
    val missionCount: Int,
    val exclusiveMissionCount: Int?,
    val largestMissionLocals: Int?,
    val missionOffsets: List<Int>,
    val largestStreamedScriptSize: Int?,
    val streamedScripts: List<StreamedScriptEntry>,
    /** Offset of the first instruction of the main code. */
    val mainCodeStart: Int,
) {
    val targetGameChar: Char get() = targetGame.toChar()
    val isSanAndreasLayout: Boolean get() = segments.size >= 6 && targetGame == 's'.code

    /** Byte ranges of the code sections: main code, then each mission. */
    fun codeSections(fileSize: Int): List<CodeSection> {
        val sections = mutableListOf<CodeSection>()
        val missionStarts = missionOffsets.filter { it in mainCodeStart until fileSize }.sorted()
        val mainEnd = (mainScriptSize?.takeIf { it in mainCodeStart..fileSize } ?: missionStarts.firstOrNull() ?: fileSize)
        sections += CodeSection("MAIN", mainCodeStart, mainEnd, isMission = false)
        missionOffsets.forEachIndexed { i, start ->
            if (start !in mainCodeStart until fileSize) return@forEachIndexed
            val next = missionStarts.firstOrNull { it > start } ?: fileSize
            sections += CodeSection("MISSION_$i", start, next, isMission = true)
        }
        return sections
    }
}

data class CodeSection(val name: String, val start: Int, val end: Int, val isMission: Boolean) {
    val size: Int get() = end - start
}

data class MainScmParseResult(val header: MainScmHeader?, val diagnostics: List<Diagnostic>)

/**
 * Parses the segmented header of a GTA San Andreas `main.scm`.
 *
 * Layout (each segment starts with `02 00 01 <int32 target>` — a GOTO over the segment):
 * 0. variables: target game byte, then the global variable space
 * 1. models: id 0, int32 count, count x 24-byte names
 * 2. missions: id 1, int32 main size, int32 largest mission, int16 count, int16 exclusive count,
 *    int32 largest local count, count x int32 offsets
 * 3. streamed scripts: id 2, int32 largest size, int32 count, count x (20-byte name, int32, int32)
 * 4./5. two further SA segments (ids 3 and 4) whose payload is shown but not interpreted
 *
 * Parsing stops at the first segment that does not validate; everything parsed up to that point
 * is returned together with a diagnostic explaining what was wrong.
 */
object MainScmParser {
    private const val GOTO_LO = 0x02
    private const val GOTO_HI = 0x00
    private const val MAX_MODELS = 65_535
    private const val MAX_MISSIONS = 1_024
    private const val MAX_STREAMED = 1_024

    private val titles = listOf("Global variables", "Models", "Missions", "Streamed scripts", "Segment 5", "Segment 6")

    fun parse(data: ByteArray, fileName: String? = null): MainScmParseResult {
        val sink = DiagnosticSink(fileName)
        val segments = mutableListOf<ScmSegment>()
        var pos = 0
        var targetGame = -1
        var models = emptyList<String>()
        var mainSize: Int? = null
        var largestMission: Int? = null
        var missionCount = 0
        var exclusiveCount: Int? = null
        var largestLocals: Int? = null
        var missionOffsets = emptyList<Int>()
        var largestStreamed: Int? = null
        var streamed = emptyList<StreamedScriptEntry>()

        while (segments.size < titles.size) {
            val index = segments.size
            if (pos + 8 > data.size) {
                if (index == 0) sink.binaryError("H001", "File is too small to be a main.scm (${data.size} bytes)", pos)
                break
            }
            val isGoto = (data[pos].toInt() and 0xFF) == GOTO_LO && (data[pos + 1].toInt() and 0xFF) == GOTO_HI &&
                (data[pos + 2].toInt() and 0xFF) == DataType.INT32.code
            if (!isGoto) {
                if (index == 0) {
                    sink.binaryError("H002", "Missing header: the file does not start with a GOTO (02 00 01) — this is not a main.scm, it may be a headerless CLEO script", pos)
                }
                break
            }
            val target = LittleEndian.s32(data, pos + 3)!!
            if (target <= pos + 7 || target > data.size) {
                sink.binaryError("H003", "Header segment ${index + 1} jumps to $target, which is outside the file or backwards", pos)
                break
            }
            val marker = data[pos + 7].toInt() and 0xFF
            if (index > 0 && marker != index - 1) {
                // Not a header segment: the main code starts here.
                break
            }
            val segment = ScmSegment(index, pos, target, marker, titles[index])
            val body = ByteCursor(data, pos + 8, target)
            try {
                when (index) {
                    0 -> targetGame = marker
                    1 -> {
                        val count = body.s32("model count")
                        if (count !in 0..MAX_MODELS || count.toLong() * 24 > body.remaining) {
                            throw DecodeException(pos + 8, "Model count $count does not fit in the segment")
                        }
                        models = (0 until count).map { String(body.bytes(24, "model name"), Charsets.ISO_8859_1).substringBefore('\u0000') }
                    }
                    2 -> {
                        mainSize = body.s32("main script size")
                        largestMission = body.s32("largest mission size")
                        missionCount = body.u16("mission count")
                        exclusiveCount = body.u16("exclusive mission count")
                        if (missionCount > MAX_MISSIONS) throw DecodeException(pos + 8, "Mission count $missionCount is implausible")
                        // San Andreas adds the largest local-variable count before the offsets.
                        if (targetGame == 's'.code) largestLocals = body.s32("largest mission locals")
                        if (body.remaining < missionCount * 4) throw DecodeException(pos + 8, "Mission table is truncated")
                        missionOffsets = (0 until missionCount).map { body.s32("mission offset") }
                    }
                    3 -> {
                        largestStreamed = body.s32("largest streamed script size")
                        val count = body.s32("streamed script count")
                        if (count !in 0..MAX_STREAMED || count.toLong() * 28 > body.remaining) {
                            throw DecodeException(pos + 8, "Streamed script count $count does not fit in the segment")
                        }
                        streamed = (0 until count).map {
                            val name = String(body.bytes(20, "streamed script name"), Charsets.ISO_8859_1).substringBefore('\u0000')
                            StreamedScriptEntry(name, body.s32(), body.s32())
                        }
                    }
                }
            } catch (e: DecodeException) {
                sink.binaryError("H004", "Segment ${index + 1} (${titles[index]}): ${e.message}", e.offset)
                segments += segment
                pos = target
                break
            }
            segments += segment
            pos = target
        }

        if (segments.isEmpty()) return MainScmParseResult(null, sink.diagnostics)
        if (targetGame != 's'.code) {
            sink.binaryWarning("H005", "Target game byte is 0x${targetGame.toString(16)} ('${targetGame.toChar()}'), not 's' (San Andreas)", 7)
        }
        if (segments.size < titles.size) {
            sink.binaryWarning("H006", "Only ${segments.size} of the 6 San Andreas header segments were found", pos)
        }
        missionOffsets.forEachIndexed { i, off ->
            if (off !in pos until data.size) sink.binaryWarning("H007", "Mission $i offset $off is outside the code area", off.coerceAtLeast(0))
        }
        val header = MainScmHeader(
            segments = segments,
            targetGame = targetGame,
            globalVariableSpace = if (segments.isNotEmpty()) 8 until segments[0].end else IntRange.EMPTY,
            models = models,
            mainScriptSize = mainSize,
            largestMissionSize = largestMission,
            missionCount = missionCount,
            exclusiveMissionCount = exclusiveCount,
            largestMissionLocals = largestLocals,
            missionOffsets = missionOffsets,
            largestStreamedScriptSize = largestStreamed,
            streamedScripts = streamed,
            mainCodeStart = pos,
        )
        return MainScmParseResult(header, sink.diagnostics)
    }

    /** Quick check used by format detection. */
    fun looksLikeMainScm(data: ByteArray): Boolean {
        if (data.size < 16) return false
        if ((data[0].toInt() and 0xFF) != GOTO_LO || data[1].toInt() != GOTO_HI || (data[2].toInt() and 0xFF) != 0x01) return false
        val target = LittleEndian.s32(data, 3) ?: return false
        if (target <= 8 || target + 8 > data.size) return false
        // The second segment must also be a GOTO with marker 0.
        return (data[target].toInt() and 0xFF) == GOTO_LO && data[target + 1].toInt() == GOTO_HI &&
            (data[target + 2].toInt() and 0xFF) == 0x01 && data[target + 7].toInt() == 0
    }
}
