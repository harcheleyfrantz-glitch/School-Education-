package com.rodwave.engine.project

import com.rodwave.engine.compiler.CompileOptions
import com.rodwave.engine.compiler.ScriptCompiler
import com.rodwave.engine.fs.FsException
import com.rodwave.engine.fs.LocalFile
import com.rodwave.engine.fs.readText
import com.rodwave.engine.opcode.CoreOpcodes
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class ProjectTest {
    private val compiler = ScriptCompiler(CoreOpcodes.database)

    @Test
    fun everyTemplateCompilesWithoutWarnings() {
        for (t in Templates.ALL) {
            val r = compiler.compile(t.source("Sample"), CompileOptions(format = t.format))
            assertTrue(r.success, "${t.id}: ${r.diagnostics.joinToString("\n")}")
            assertEquals(t.format, r.format, t.id)
            assertTrue(r.warnings.isEmpty(), "${t.id} warnings: ${r.warnings}")
        }
    }

    @Test
    fun snippetsCompileInsideAScript() {
        for (s in Templates.SNIPPETS) {
            val src = "{\$CLEO .csa}\n0000: nop\n${s.body}\n004E: terminate_this_script\n"
            val r = compiler.compile(src)
            assertTrue(r.success, "${s.id}: ${r.diagnostics.joinToString("\n")}")
        }
    }

    @Test
    fun projectLifecycle() {
        val root = LocalFile(Files.createTempDirectory("rw-projects").toFile())
        val pm = ProjectManager(root) { 42L }
        val p = pm.create("My Script", Templates.TOUCH_TOGGLE)
        assertEquals("touch-toggle", p.manifest.template)
        assertEquals(listOf("main.txt"), p.sourceFiles().map { it.name })
        assertTrue(p.sourceFiles().single().readText().contains("{\$CLEO .csa}"))
        pm.createFile(p, "texts.fxt", "HELLO Hi\n")
        assertEquals(listOf("main.txt", "texts.fxt"), p.sourceFiles().map { it.name })
        assertFailsWith<FsException> { pm.create("My Script", Templates.EMPTY) }
        assertFailsWith<FsException> { pm.create("../escape", Templates.EMPTY) }
        assertFailsWith<FsException> { pm.createFile(p, "evil.sh") }
        val renamed = pm.rename(p, "Renamed")
        assertEquals(listOf("Renamed"), pm.list().map { it.name })
        assertTrue(pm.delete(renamed))
        assertTrue(pm.list().isEmpty())
    }

    @Test
    fun workspaceBackupRoundTrip() {
        val root = LocalFile(Files.createTempDirectory("rw-ws").toFile())
        val pm = ProjectManager(root)
        pm.create("One", Templates.EMPTY)
        pm.create("Two", Templates.HEAL)
        val zip = WorkspaceArchiver.export(root)

        val target = LocalFile(Files.createTempDirectory("rw-ws2").toFile())
        val plan = WorkspaceArchiver.planRestore(zip, target)
        assertTrue(plan.conflicts.isEmpty())
        assertEquals(4, plan.newFiles.size)
        assertEquals(4, WorkspaceArchiver.restore(plan, target, overwrite = false))
        assertEquals(setOf("One", "Two"), ProjectManager(target).list().map { it.name }.toSet())
        // A second restore sees conflicts and skips them unless asked to overwrite.
        val again = WorkspaceArchiver.planRestore(zip, target)
        assertEquals(4, again.conflicts.size)
        assertEquals(0, WorkspaceArchiver.restore(again, target, overwrite = false))
    }

    @Test
    fun fxtValidation() {
        val (entries, diags) = FxtFile.parse("# comment\nHELLO Hello there\nTOOLONGKEY text\nHELLO again\nEMPTY\n")
        assertEquals(listOf("HELLO", "HELLO"), entries.map { it.key })
        assertEquals(listOf("F001", "F003", "F002"), diags.map { it.code })
        assertEquals(3, diags.first().line)
    }
}
