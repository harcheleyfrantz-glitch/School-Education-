package com.rodwave.engine.compiler

import com.rodwave.engine.hexBytes
import com.rodwave.engine.opcode.CoreOpcodes
import com.rodwave.engine.scm.ScriptFormat
import com.rodwave.engine.toHex
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CompilerTest {
    private val compiler = ScriptCompiler(CoreOpcodes.database)

    private fun compileOk(source: String, options: CompileOptions = CompileOptions()): CompileResult {
        val r = compiler.compile(source, options)
        assertTrue(r.success, "expected success, got:\n" + r.diagnostics.joinToString("\n") { it.render() })
        return r
    }

    private fun bytesOf(source: String): String = compileOk(source).bytes!!.toHex()

    private fun errorCodes(source: String): List<String> {
        val r = compiler.compile(source)
        assertFalse(r.success, "expected failure for:\n$source")
        assertNull(r.bytes)
        return r.errors.map { it.code }
    }

    @Test
    fun minimalLoopMatchesHandEncodedBytes() {
        val r = compileOk(
            """
            {${'$'}CLEO .csa}
            0000: nop
            :MAIN
            0001: wait 0 ms
            0002: jump @MAIN
            """.trimIndent(),
        )
        // nop | wait INT8 0 | goto INT32 -2 (label MAIN at offset 2)
        assertEquals("00 00 01 00 04 00 02 00 01 FE FF FF FF", r.bytes!!.toHex())
        assertEquals(ScriptFormat.CLEO_ANDROID_AUTO, r.format)
        assertEquals(mapOf("MAIN" to 2), r.labels)
        assertEquals(3, r.instructionCount)
    }

    @Test
    fun cleoDirectiveSelectsFormat() {
        assertEquals(ScriptFormat.CLEO_ANDROID_INVOKED, compileOk("{\$CLEO .csi}\nwait 0\nterminate_this_script").format)
        val pc = compileOk("{\$CLEO .cs}\nwait 0\nterminate_this_script")
        assertEquals(ScriptFormat.CLEO_PC, pc.format)
        assertTrue(pc.warnings.any { it.code == "C011" })
    }

    @Test
    fun keywordFormAndIntegerWidths() {
        assertEquals("01 00 05 FA 00 4E 00", bytesOf("wait 250\nterminate_this_script"))
        assertEquals("01 00 01 A0 86 01 00 4E 00", bytesOf("wait 100000\nend_thread"))
        assertEquals("01 00 04 FF 4E 00", bytesOf("WAIT -1\nTERMINATE_THIS_SCRIPT"))
    }

    @Test
    fun stringLiteralEncodings() {
        // 03A4 SCRIPT_NAME 'TEST' -> 8-byte string
        assertEquals("A4 03 09 54 45 53 54 00 00 00 00 4E 00", bytesOf("03A4: script_name 'TEST'\n004E: terminate"))
        // Double quotes produce a variable-length string.
        assertEquals("A4 03 0E 03 41 42 43 4E 00", bytesOf("script_name \"ABC\"\nterminate_this_script"))
    }

    @Test
    fun assignmentOperatorsPickTheRightOpcode() {
        // 0006 SET_LVAR_INT 0@ = 5
        assertEquals("06 00 03 00 00 04 05 4E 00", bytesOf("0@ = 5\nterminate_this_script"))
        // 000A ADD_VAL_TO_INT_LVAR 0@ += 1 (type inferred from the literal)
        assertEquals("0A 00 03 00 00 04 01 4E 00", bytesOf("0@ += 1\nterminate_this_script"))
        // 0005 SET_VAR_FLOAT $12 = 1.5 (global byte offset 48)
        assertEquals("05 00 02 30 00 06 00 00 C0 3F 4E 00", bytesOf("\$12 = 1.5\nterminate_this_script"))
        // 0007 with an integer literal converted to float because 1@ is declared float
        assertEquals("07 00 03 01 00 06 00 00 80 3F 4E 00", bytesOf("float 1@\n1@ = 1\nterminate_this_script"))
        // 0085 lvar = lvar with the type known from declarations
        assertEquals("85 00 03 00 00 03 01 00 4E 00", bytesOf("int 0@, 1@\n0@ = 1@\nterminate_this_script"))
        // TIMERA is local 32
        assertEquals("06 00 03 20 00 04 00 4E 00", bytesOf("TIMERA = 0\nterminate_this_script"))
        // ++ on an int
        assertEquals("0A 00 03 02 00 04 01 4E 00", bytesOf("int 2@\n2@++\nterminate_this_script"))
        // =# stores a float local into an int local (0092 CSET_LVAR_INT_TO_LVAR_FLOAT)
        assertEquals("92 00 03 01 00 03 00 00 4E 00", bytesOf("float 0@\nint 1@\n1@ =# 0@\nterminate_this_script"))
    }

    @Test
    fun conditionsAndStructuredIf() {
        val r = compileOk(
            """
            {${'$'}CLEO}
            0000: nop
            :LOOP
            wait 0
            if
                0@ < 5
            then
                0@ += 1
            else
                0@ = 0
            end
            jump @LOOP
            """.trimIndent(),
        )
        // Offsets: nop 0-1, wait 2-5, if 6-9, "5 > 0@" (0@ < 5 swapped, 001B) 10-16, jf 17-23,
        // then-body 24-30, goto end 31-37, else-body 38-44, endif 45, jump @LOOP 45-51.
        val bytes = r.bytes!!.toHex()
        assertTrue(bytes.startsWith("00 00 01 00 04 00 D6 00 04 00 1B 00 04 05 03 00 00 4D 00 01"), bytes)
        // jf -> else block at 38 (encoded -38 = DA FF FF FF); goto -> end at 45 (-45 = D3 FF FF FF)
        assertTrue(bytes.contains("4D 00 01 DA FF FF FF 0A 00 03 00 00 04 01 02 00 01 D3 FF FF FF 06 00 03 00 00 04 00 02 00 01 FE FF FF FF"), bytes)
    }

    @Test
    fun andOrConditionCounts() {
        val and = bytesOf(
            """
            0000:
            :A
            wait 0
            if and
              0@ > 1
              0@ <> 3
            jf @A
            terminate_this_script
            """.trimIndent(),
        )
        // if 1 (two conditions AND), second condition is a negated 0039
        assertTrue(and.contains("D6 00 04 01 19 00 03 00 00 04 01 39 80 03 00 00 04 03 4D 00 01 FE FF FF FF"), and)
        val or = bytesOf("0000:\n:A\nwait 0\nif or\n0@ == 1\n0@ == 2\n0@ == 3\njf @A\nend_thread")
        assertTrue(or.contains("D6 00 04 16"), or) // 21 + 2 - 1 + ... = 22 (0x16) for three OR conditions
    }

    @Test
    fun whileLoopWithBreak() {
        val r = compileOk(
            """
            int counter = 0
            while true
                wait 0
                counter += 1
                if counter >= 10
                then
                    break
                end
            end
            terminate_this_script
            """.trimIndent(),
        )
        assertTrue(r.warnings.none { it.code == "L005" })
        assertTrue(r.bytes!!.toHex().endsWith("4E 00"))
    }

    @Test
    fun loopWithoutWaitIsReported() {
        val r = compileOk("0000: nop\n:SPIN\n0@ += 1\njump @SPIN")
        assertTrue(r.warnings.any { it.code == "L005" }, r.diagnostics.toString())
    }

    @Test
    fun forLoopAndRepeat() {
        val r = compileOk(
            """
            for 0@ = 1 to 5
                wait 10
            end
            repeat
                wait 0
                1@ += 1
            until 1@ > 3
            terminate_this_script
            """.trimIndent(),
        )
        assertTrue(r.success)
        val down = compileOk("float 2@\nfor 2@ = 10.0 downto 0.0 step 0.5\nwait 0\nend\nend_thread")
        assertTrue(down.success)
    }

    @Test
    fun arraysAndStringVariables() {
        // 0004 $ARR(0@,10i) = 5 where $100 -> byte offset 400 (0x190)
        assertEquals("04 00 07 90 01 00 00 0A 00 04 05 4E 00", bytesOf("\$100(0@,10i) = 5\nterminate_this_script"))
        // 05AA SET_LVAR_TEXT_LABEL 0@s = 'ABC'
        assertEquals("AA 05 0B 00 00 09 41 42 43 00 00 00 00 00 4E 00", bytesOf("0@s = 'ABC'\nterminate_this_script"))
        // 06D1 SET_VAR_TEXT_LABEL16 v$10 = "LONG"
        assertEquals("D1 06 10 28 00 0E 04 4C 4F 4E 47 4E 00", bytesOf("v\$10 = \"LONG\"\nterminate_this_script"))
    }

    @Test
    fun constantsEnumsAndModels() {
        val src = """
            const
              DELAY = 500
              ZONE = 5, PLAYER = ${'$'}PLAYER_CHAR
            end
            wait DELAY
            0DE0: get_touch_point_state TouchPoints.Center mintime 100 store_to 0@
            0247: request_model #CHEETAH
            0256: is_player_playing PLAYER
            0001: wait ZONE
            terminate_this_script
        """.trimIndent()
        val hex = bytesOf(src)
        assertTrue(hex.startsWith("01 00 05 F4 01"), hex)                 // wait 500
        assertTrue(hex.contains("E0 0D 04 05 04 64 03 00 00"), hex)      // touch point 5, 100 ms, 0@
        assertTrue(hex.contains("47 02 05 9F 01"), hex)                  // CHEETAH = 415
        assertTrue(hex.contains("56 02 02 08 00"), hex)                  // $PLAYER_CHAR = $2 = offset 8
    }

    @Test
    fun hexBlocksAndLabelPointers() {
        val r = compileOk(
            """
            0DD0: store_label_pointer 0@ @DATA
            terminate_this_script
            :DATA
            hex
              01 02 03 04
              0A0B
            end
            """.trimIndent(),
        )
        // DATA at offset 9: 0DD0 (2) + local (3) + label (5) = 10? store_label_pointer 0@ @DATA -> 2+3+5 = 10, terminate 2 -> DATA at 12
        assertEquals("D0 0D 03 00 00 01 F4 FF FF FF 4E 00 01 02 03 04 0A 0B", r.bytes!!.toHex())
    }

    @Test
    fun negatedCommandsInClassicConditionBlocks() {
        val hex = bytesOf(
            """
            0000: nop
            :WAITING
            0001: wait 100
            00D6: if 0
            8256:   not player ${'$'}PLAYER_CHAR defined
            004D: jump_if_false @WAITING
            0001: wait 0
            004E: end_thread
            """.trimIndent(),
        )
        assertTrue(hex.contains("D6 00 04 00 56 82 02 08 00 4D 00 01 FE FF FF FF"), hex)
    }

    @Test
    fun startNewScriptPassesArguments() {
        val hex = bytesOf(
            """
            0000: nop
            004F: start_new_script @WORKER 5 1.0
            004E: end_thread
            :WORKER
            0001: wait 0
            004E: end_thread
            """.trimIndent(),
        )
        // label WORKER at 2 + 15 + 2 = 19 -> -19 = ED FF FF FF; args INT8 5, FLOAT 1.0, end marker 00
        assertTrue(hex.startsWith("00 00 4F 00 01 ED FF FF FF 04 05 06 00 00 80 3F 00 4E 00"), hex)
    }

    @Test
    fun errorsAreReportedWithLocations() {
        assertEquals(listOf("C052"), errorCodes("wiat 0"))
        assertEquals(listOf("C060"), errorCodes("0001: wait"))
        assertEquals(listOf("C092"), errorCodes("jump @NOWHERE"))
        assertEquals(listOf("C093"), errorCodes(":START\nwait 0\njump @START"))
        assertEquals(listOf("C083"), errorCodes("0@ = 1@\nend_thread"))
        assertEquals(listOf("C068"), errorCodes("wait 1.5"))
        assertEquals(listOf("C031"), errorCodes("0256: is_player_playing \$UNKNOWN_VAR\nend_thread"))
        assertEquals(listOf("C050"), errorCodes("0A92: create_custom_thread 'x.cs'"))
        assertEquals(listOf("C051"), errorCodes("end_custom_thread"))
        assertEquals(listOf("C062"), errorCodes("0006: 0@ 1@"))
        assertEquals(listOf("C042"), errorCodes("0000:\n:A\n:A\nwait 0\njump @A"))
        assertTrue(errorCodes("if\n0@ > 1\n0@ > 2\nthen\nend\nend_thread").contains("C044"))
        val r = compiler.compile("0000: nop\n\n0001: wait 'X'")
        val e = r.errors.single()
        assertEquals(3, e.line)
        assertEquals("C069", e.code)
    }

    @Test
    fun parserErrors() {
        val r = compiler.compile("if 0@ > 1\nwait 0")
        assertTrue(r.errors.any { it.code == "P027" })
        val unterminated = compiler.compile("while true\nwait 0")
        assertTrue(unterminated.errors.any { it.code == "P033" })
        val hexOdd = compiler.compile("hex 0 end")
        assertTrue(hexOdd.errors.any { it.code == "P043" })
    }

    @Test
    fun includesAreResolvedThroughTheResolver() {
        val files = mapOf("lib.txt" to "const DELAY = 250\n:HELPER\nwait DELAY\nreturn")
        val options = CompileOptions(includeResolver = IncludeResolver { path, _ -> files[path]?.let { IncludedSource(path, it) } })
        val r = compiler.compile("0000:\ngosub @HELPER\nend_thread\n{\$INCLUDE lib.txt}", options)
        assertTrue(r.success, r.diagnostics.toString())
        // nop (0-1), gosub (2-8), end_thread (9-10), HELPER at 11 -> -11 = F5 FF FF FF
        assertEquals("00 00 50 00 01 F5 FF FF FF 4E 00 01 00 05 FA 00 51 00", r.bytes!!.toHex())
        val missing = compiler.compile("{\$INCLUDE nope.txt}\nend_thread", options)
        assertTrue(missing.errors.any { it.code == "C004" })
    }

    @Test
    fun outputNeverContainsUnvalidatedBytes() {
        // A failing script yields no bytes at all.
        val r = compiler.compile("wait 0\njump @MISSING")
        assertNull(r.bytes)
        assertFalse(r.success)
    }

    @Test
    fun handEncodedFixtureDecodesToTheSameInstructions() {
        val bytes = hexBytes("00 00 01 00 04 00 02 00 01 FE FF FF FF")
        val decoder = com.rodwave.engine.scm.InstructionDecoder(CoreOpcodes.database)
        var off = 0
        val ops = mutableListOf<Int>()
        while (off < bytes.size) {
            val r = decoder.decode(bytes, off) as com.rodwave.engine.scm.DecodeResult.Ok
            ops += r.instruction.opcode
            off = r.instruction.end
        }
        assertEquals(listOf(0x0000, 0x0001, 0x0002), ops)
    }
}
