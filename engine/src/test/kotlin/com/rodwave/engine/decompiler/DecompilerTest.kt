package com.rodwave.engine.decompiler

import com.rodwave.engine.compiler.CompileOptions
import com.rodwave.engine.compiler.ScriptCompiler
import com.rodwave.engine.hexBytes
import com.rodwave.engine.opcode.CoreOpcodes
import com.rodwave.engine.opcode.ParamType
import com.rodwave.engine.scm.BytecodeWriter
import com.rodwave.engine.scm.DataType
import com.rodwave.engine.scm.EndOfArgs
import com.rodwave.engine.scm.FloatOperand
import com.rodwave.engine.scm.IntOperand
import com.rodwave.engine.scm.Operand
import com.rodwave.engine.scm.ScriptFormat
import com.rodwave.engine.scm.StringOperand
import com.rodwave.engine.scm.VarOperand
import com.rodwave.engine.toHex
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DecompilerTest {
    private val db = CoreOpcodes.database
    private val decompiler = ScriptDecompiler(db)
    private val compiler = ScriptCompiler(db)

    private fun assertRoundTrip(bytes: ByteArray, format: ScriptFormat = ScriptFormat.CLEO_ANDROID_AUTO): DecompileResult {
        val r = decompiler.decompile(bytes, DecompileOptions(format = format))
        assertEquals(
            RoundTripStatus.IDENTICAL, r.roundTrip,
            "round trip failed for ${bytes.toHex()}\n--- text ---\n${r.text}\n--- diagnostics ---\n${r.diagnostics.joinToString("\n")}",
        )
        return r
    }

    @Test
    fun decompilesTheHandEncodedFixture() {
        val r = assertRoundTrip(hexBytes("00 00 01 00 04 00 02 00 01 FE FF FF FF"))
        val lines = r.text.lines().filter { it.isNotBlank() && !it.startsWith("//") }
        assertEquals(
            listOf("{\$CLEO .csa}", "0000: nop", ":LABEL_2", "0001: wait 0", "0002: goto @LABEL_2"),
            lines,
        )
        assertEquals(1.0, r.coverage)
    }

    @Test
    fun compileDecompileCompileIsStable() {
        val source = """
            {${'$'}CLEO .csi}
            0000: nop
            03A4: script_name 'RODWAVE'
            int counter = 0
            float speed = 1.5
            :MAIN
            wait 0
            if and
                0256: is_player_playing ${'$'}PLAYER_CHAR
                counter < 100
            then
                counter += 1
                speed *= 2.0
                0@s = 'ABC'
                v${'$'}20 = "Rodwave"
                ${'$'}100(1@,10i) = -7
            else
                TIMERA = 0
            end
            0DD0: store_label_pointer 2@ @TABLE
            0DE0: get_touch_point_state 5 100 3@
            004F: start_new_script @WORKER 1 2.5 'TXT'
            jump @MAIN
            :WORKER
            wait 1000
            terminate_this_script
            :TABLE
            hex
              48 65 6C 6C 6F 00 FF 7F
            end
        """.trimIndent()
        val first = compiler.compile(source, CompileOptions(format = ScriptFormat.CLEO_ANDROID_INVOKED))
        assertTrue(first.success, first.diagnostics.joinToString("\n"))
        val r = assertRoundTrip(first.bytes!!, ScriptFormat.CLEO_ANDROID_INVOKED)
        assertTrue(r.text.contains("hex"), r.text)
        assertTrue(r.text.contains(":DATA_"), "data label expected:\n${r.text}")
        assertTrue(r.text.contains("\$PLAYER_CHAR"))
        assertTrue(r.text.contains("TIMERA"))
        assertEquals(1, r.dataBlocks.size)
    }

    @Test
    fun unknownOpcodesAreKeptAsData() {
        // wait 0, then an opcode that is not in the core set, then terminate.
        val bytes = hexBytes("01 00 04 00 34 12 04 01 4E 00")
        val r = assertRoundTrip(bytes)
        assertTrue(r.diagnostics.any { it.code == "D023" })
        assertTrue(r.text.contains("Unknown opcode 1234"))
    }

    @Test
    fun nonMinimalEncodingsFallBackToHex() {
        // wait with a 32-bit zero (Sanny Builder would emit 8 bits) and a 16-byte short text.
        val w = BytecodeWriter()
        w.instruction(0x0001, false, listOf(IntOperand(0, DataType.INT32)))
        w.instruction(0x03A4, false, listOf(StringOperand.of(DataType.STRING16, "AB")))
        w.instruction(0x004E, false, emptyList())
        val r = assertRoundTrip(w.toByteArray())
        assertTrue(r.text.contains("hex 01 00 01 00 00 00 00 end"), r.text)
    }

    @Test
    fun randomBytesAlwaysRoundTrip() {
        val random = Random(1234)
        repeat(300) {
            val size = random.nextInt(1, 200)
            val bytes = ByteArray(size) { random.nextInt(256).toByte() }
            assertRoundTrip(bytes)
        }
    }

    @Test
    fun randomValidInstructionStreamsRoundTrip() {
        val random = Random(42)
        val defs = db.all.filter { d -> d.params.none { it.type == ParamType.LABEL } && !d.isUnsupported }
        repeat(200) {
            val w = BytecodeWriter()
            repeat(random.nextInt(1, 25)) {
                val def = defs[random.nextInt(defs.size)]
                val operands = ArrayList<Operand>()
                for (p in def.params) {
                    if (p.type == ParamType.ARGUMENTS) {
                        repeat(random.nextInt(0, 3)) { operands += IntOperand.minimal(random.nextInt(-1000, 1000)) }
                        operands += EndOfArgs
                        continue
                    }
                    operands += when {
                        p.isOutput || p.source.requiresVariable -> {
                            val global = when (p.source) {
                                com.rodwave.engine.opcode.ParamSource.VAR_GLOBAL -> true
                                com.rodwave.engine.opcode.ParamSource.VAR_LOCAL -> false
                                else -> random.nextBoolean()
                            }
                            val storage = if (p.type.isStringLike) com.rodwave.engine.scm.VarStorage.STRING8 else com.rodwave.engine.scm.VarStorage.NUMBER
                            VarOperand(DataType.variable(global, storage), if (global) random.nextInt(0, 500) * 4 else random.nextInt(0, 30))
                        }
                        p.type == ParamType.FLOAT -> FloatOperand(random.nextInt(-100000, 100000) / 64f)
                        p.type.isStringLike -> StringOperand.of(DataType.STRING8, "T" + random.nextInt(0, 999))
                        else -> IntOperand.minimal(random.nextInt())
                    }
                }
                w.instruction(def.id, def.isCondition && random.nextBoolean(), operands)
            }
            w.instruction(0x004E, false, emptyList())
            val r = assertRoundTrip(w.toByteArray())
            // Canonical encodings must decompile to source, never to raw hex.
            assertTrue(r.dataBlocks.isEmpty() && !r.text.contains("\nhex"), "unexpected hex fallback:\n${r.text}")
            assertEquals(1.0, r.coverage)
        }
    }

    @Test
    fun floatFormattingIsExact() {
        for (f in listOf(0f, -0f, 1f, 0.1f, 1.5f, -2.25f, 3.4028235E38f, 1.4E-45f, 123456.79f, 1e-10f)) {
            val text = ScriptDecompiler.formatFloat(f)!!
            assertTrue('e' !in text.lowercase(), text)
            assertEquals(f.toRawBits(), text.toFloat().toRawBits(), text)
        }
        assertEquals(null, ScriptDecompiler.formatFloat(Float.NaN))
    }

    @Test
    fun mainScmIsDetectedAndListed() {
        val bytes = MainScmFixture.build()
        val r = decompiler.decompile(bytes)
        assertTrue(r.diagnostics.any { it.code == "D002" })
        val listing = decompiler.decompileMainScm(bytes, "main.scm")
        assertTrue(listing.header != null)
        assertTrue(listing.text.contains("===== MAIN"), listing.text)
        assertTrue(listing.text.contains("===== MISSION_0"), listing.text)
        assertTrue(listing.instructionCount >= 4, listing.text)
    }
}
