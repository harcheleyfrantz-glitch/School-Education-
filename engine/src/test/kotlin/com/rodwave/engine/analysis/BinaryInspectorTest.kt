package com.rodwave.engine.analysis

import com.rodwave.engine.archive.ArchiveFile
import com.rodwave.engine.archive.SafeZip
import com.rodwave.engine.compiler.ScriptCompiler
import com.rodwave.engine.elf.ElfBuilder
import com.rodwave.engine.elf.ElfFile
import com.rodwave.engine.opcode.CoreOpcodes
import com.rodwave.engine.scm.Abi
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.ByteArrayOutputStream

class BinaryInspectorTest {
    private val db = CoreOpcodes.database

    @Test
    fun `kind comes from content, not from the file name`() {
        val script = ScriptCompiler(db).compile("{\$CLEO .csa}\nwait 100\n004E: terminate_this_script\n").bytes!!
        val asText = BinaryInspector.inspect("readme.txt", script, db)
        assertEquals(BinaryKind.SCRIPT, asText.kind)
        assertEquals(2, asText.script!!.instructionCount)

        val text = "line one\nline two\n".toByteArray()
        val asScript = BinaryInspector.inspect("mod.csa", text, db)
        assertEquals(BinaryKind.TEXT, asScript.kind)
        assertEquals(3, asScript.textLines)
    }

    @Test
    fun `archives list entries and reject traversal`() {
        val out = ByteArrayOutputStream()
        SafeZip.write(out, listOf(ArchiveFile("cleo/a.csa", byteArrayOf(1, 2)), ArchiveFile("readme.txt", "hi\n".toByteArray())))
        val info = BinaryInspector.inspect("pack.zip", out.toByteArray(), db)
        assertEquals(BinaryKind.ZIP, info.kind)
        assertEquals(listOf("cleo/a.csa", "readme.txt"), info.archive!!.files.map { it.path })

        val broken = BinaryInspector.inspect("bad.zip", byteArrayOf('P'.code.toByte(), 'K'.code.toByte(), 3, 4, 0, 0), db)
        assertEquals(BinaryKind.ZIP, broken.kind)
        assertNotNull(broken.archiveError)
    }

    @Test
    fun `elf libraries are inspected statically`() {
        val elf = ElfBuilder.build(true, ElfFile.EM_AARCH64, exports = listOf("__GetModInfo", "OnModLoad"))
        val info = BinaryInspector.inspect("libmod.so", elf, db)
        assertEquals(BinaryKind.ELF, info.kind)
        assertTrue(info.native!!.isAmlMod)
        assertEquals(Abi.ARM64_V8A, info.native!!.abi)
        assertEquals(64, info.sha256.length)
    }
}
