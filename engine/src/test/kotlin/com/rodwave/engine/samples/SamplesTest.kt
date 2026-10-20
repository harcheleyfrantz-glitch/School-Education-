package com.rodwave.engine.samples

import com.rodwave.engine.compiler.CompileOptions
import com.rodwave.engine.compiler.ScriptCompiler
import com.rodwave.engine.decompiler.DecompileOptions
import com.rodwave.engine.decompiler.RoundTripStatus
import com.rodwave.engine.decompiler.ScriptDecompiler
import com.rodwave.engine.opcode.CoreOpcodes
import com.rodwave.engine.project.Templates
import org.junit.jupiter.api.Assertions.assertEquals
import kotlin.test.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.io.File

/**
 * Every script under samples/ and every project template must compile with the built-in opcode set
 * without errors, and its decompiled listing must recompile to the same bytes. This verifies the
 * scripts as bytecode; it does not (and cannot) run them in the game.
 */
class SamplesTest {
    private val db = CoreOpcodes.database

    private val samplesDir = File(System.getProperty("rodwave.samplesDir") ?: "../samples")

    @TestFactory
    fun `samples compile and round-trip`(): List<DynamicTest> {
        val files = samplesDir.listFiles { f -> f.extension == "txt" }.orEmpty().sortedBy { it.name }
        assertTrue(files.size >= 4, "expected the sample scripts in ${samplesDir.absolutePath}")
        return files.map { f -> DynamicTest.dynamicTest(f.name) { check(f.name, f.readText()) } }
    }

    @TestFactory
    fun `templates compile and round-trip`(): List<DynamicTest> =
        Templates.ALL.map { t -> DynamicTest.dynamicTest(t.id) { check(t.id, t.source("Example")) } }

    private fun check(name: String, source: String) {
        val result = ScriptCompiler(db).compile(source, CompileOptions(fileName = name))
        assertEquals(emptyList<String>(), result.errors.map { it.render() }, "$name has compile errors")
        assertEquals(emptyList<String>(), result.warnings.map { it.render() }, "$name has warnings")
        val bytes = assertNotNull(result.bytes)
        val decompiled = ScriptDecompiler(db).decompile(bytes, DecompileOptions(format = result.format, sourceName = name))
        assertEquals(RoundTripStatus.IDENTICAL, decompiled.roundTrip, "$name: listing does not reproduce the bytes\n${decompiled.text}")
        assertTrue(decompiled.unknownOpcodes.isEmpty(), "$name uses unknown opcodes")
    }
}
