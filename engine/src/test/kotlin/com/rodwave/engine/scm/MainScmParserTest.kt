package com.rodwave.engine.scm

import com.rodwave.engine.decompiler.MainScmFixture
import com.rodwave.engine.hexBytes
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MainScmParserTest {

    @Test
    fun parsesAllSixSanAndreasSegments() {
        val bytes = MainScmFixture.build()
        assertTrue(MainScmParser.looksLikeMainScm(bytes))
        val result = MainScmParser.parse(bytes)
        val header = assertNotNull(result.header, result.diagnostics.toString())
        assertTrue(result.diagnostics.none { it.isError }, result.diagnostics.toString())
        assertEquals(6, header.segments.size)
        assertTrue(header.isSanAndreasLayout)
        assertEquals('s', header.targetGameChar)
        assertEquals(8 until 8 + MainScmFixture.GLOBAL_SPACE, header.globalVariableSpace)
        assertEquals(listOf("", "CHEETAH"), header.models)
        assertEquals(1, header.missionCount)
        assertEquals(8, header.largestMissionLocals)
        assertEquals(header.mainScriptSize, header.missionOffsets.single())
        val sections = header.codeSections(bytes.size)
        assertEquals(listOf("MAIN", "MISSION_0"), sections.map { it.name })
        assertEquals(header.mainCodeStart, sections[0].start)
        assertEquals(bytes.size, sections[1].end)
    }

    @Test
    fun rejectsHeaderlessScripts() {
        val cleo = hexBytes("00 00 01 00 04 00 02 00 01 FE FF FF FF")
        assertTrue(!MainScmParser.looksLikeMainScm(cleo))
        val result = MainScmParser.parse(cleo)
        assertNull(result.header)
        assertTrue(result.diagnostics.any { it.code == "H002" })
    }

    @Test
    fun reportsBrokenSegmentsWithoutCrashing() {
        val bytes = MainScmFixture.build()
        // Corrupt the model count so it no longer fits the segment.
        val modelsSegment = MainScmParser.parse(bytes).header!!.segments[1]
        val corrupted = bytes.copyOf()
        corrupted[modelsSegment.offset + 8] = 0x7F
        corrupted[modelsSegment.offset + 9] = 0x7F
        val result = MainScmParser.parse(corrupted)
        assertTrue(result.diagnostics.any { it.code == "H004" }, result.diagnostics.toString())
        // Truncated file
        val truncated = MainScmParser.parse(bytes.copyOf(20))
        assertTrue(truncated.diagnostics.any { it.isError })
    }

    @Test
    fun fuzzedHeadersNeverThrow() {
        val base = MainScmFixture.build()
        val random = kotlin.random.Random(7)
        repeat(500) {
            val mutated = base.copyOf(random.nextInt(1, base.size + 1))
            repeat(random.nextInt(1, 8)) {
                if (mutated.isNotEmpty()) mutated[random.nextInt(mutated.size)] = random.nextInt(256).toByte()
            }
            MainScmParser.parse(mutated)
        }
    }
}
