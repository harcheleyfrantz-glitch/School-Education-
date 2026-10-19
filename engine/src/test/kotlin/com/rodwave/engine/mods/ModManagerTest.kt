package com.rodwave.engine.mods

import com.rodwave.engine.compat.InstalledGame
import com.rodwave.engine.compiler.ScriptCompiler
import com.rodwave.engine.elf.ElfBuilder
import com.rodwave.engine.fs.FsException
import com.rodwave.engine.fs.LocalFile
import com.rodwave.engine.fs.VirtualFile
import com.rodwave.engine.opcode.CoreOpcodes
import com.rodwave.engine.project.Templates
import com.rodwave.engine.scm.Abi
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ModManagerTest {
    private val db = CoreOpcodes.database
    private var ids = 0
    private var time = 1_000L

    private class Env(val storeDir: File, val cleoDir: File, val modsDir: File) {
        val store = ModStore(LocalFile(storeDir))
        val destinations: Map<DestinationKind, VirtualFile> = mapOf(
            DestinationKind.CLEO_SCRIPTS to LocalFile(cleoDir),
            DestinationKind.AML_MODS to LocalFile(modsDir),
        )
    }

    private fun env(): Env {
        val base = Files.createTempDirectory("rw-mods").toFile()
        return Env(File(base, "store").apply { mkdirs() }, File(base, "cleo").apply { mkdirs() }, File(base, "mods").apply { mkdirs() })
    }

    private fun importer(e: Env) = ModImporter(e.store, db, { time++ }, { "mod${ids++}" })
    private fun installer(e: Env) = ModInstaller(e.store, { time++ }, { "op${ids++}" })
    private fun script(name: String) = ScriptCompiler(db).compile(Templates.HEAL.source(name)).bytes!!

    @Test
    fun importPlanInstallAndUninstall() {
        val e = env()
        val bytes = script("Heal")
        val imported = importer(e).import("heal.csi", bytes)
        val mod = assertNotNull(imported.mod, imported.messages.toString())
        assertEquals(ModKind.CLEO_SCRIPT, mod.kind)
        assertTrue(mod.findings.any { it.contains("Uses only commands") })

        val planner = InstallPlanner(e.store)
        val plan = planner.planInstall(mod, e.destinations, PlanContext(cleoLoaderDetected = false))
        assertEquals(listOf(ActionType.CREATE), plan.actions.map { it.type })
        assertTrue(plan.warnings.any { it.contains("No CLEO loader") })
        assertTrue(plan.canApply(confirmed = false))
        assertFalse(File(e.cleoDir, "heal.csi").exists(), "a dry run must not write")

        val result = installer(e).apply(plan, e.destinations, confirmed = false)
        assertTrue(result.success, result.message)
        assertContentEquals(bytes, File(e.cleoDir, "heal.csi").readBytes())
        assertEquals(1, e.store.installedFiles().size)
        assertTrue(e.store.mod(mod.id)!!.enabled)
        assertFalse(File(e.cleoDir, "heal.csi.rodwave-tmp").exists())

        // Installing again finds an identical file and changes nothing.
        val again = planner.planInstall(e.store.mod(mod.id)!!, e.destinations)
        assertEquals(listOf(ActionType.SKIP_IDENTICAL), again.actions.map { it.type })

        val uninstall = planner.planUninstall(e.store.mod(mod.id)!!, e.destinations)
        assertEquals(listOf(ActionType.DELETE), uninstall.actions.map { it.type })
        assertTrue(installer(e).apply(uninstall, e.destinations, confirmed = false).success)
        assertFalse(File(e.cleoDir, "heal.csi").exists())
        assertTrue(e.store.installedFiles().isEmpty())
        assertFalse(e.store.mod(mod.id)!!.enabled)
        // The deleted file was backed up first.
        assertEquals(1, e.store.operations().first().backups.size)
    }

    @Test
    fun replacingUnmanagedFilesNeedsConfirmationAndIsReversible() {
        val e = env()
        val original = "user's own script".toByteArray()
        File(e.cleoDir, "heal.csi").writeBytes(original)
        val mod = importer(e).import("heal.csi", script("Heal")).mod!!
        val planner = InstallPlanner(e.store)
        val plan = planner.planInstall(mod, e.destinations)
        assertEquals(ActionType.REPLACE, plan.actions.single().type)
        assertEquals(1, plan.confirmations.size)
        assertFalse(plan.canApply(confirmed = false))
        val refused = installer(e).apply(plan, e.destinations, confirmed = false)
        assertFalse(refused.success)
        assertContentEquals(original, File(e.cleoDir, "heal.csi").readBytes())

        val done = installer(e).apply(plan, e.destinations, confirmed = true)
        assertTrue(done.success, done.message)
        assertFalse(File(e.cleoDir, "heal.csi").readBytes().contentEquals(original))

        // Uninstall removes the mod file and puts the user's original back.
        val uninstall = planner.planUninstall(e.store.mod(mod.id)!!, e.destinations)
        assertEquals(listOf(ActionType.DELETE, ActionType.RESTORE), uninstall.actions.map { it.type })
        assertTrue(installer(e).apply(uninstall, e.destinations, confirmed = false).success)
        assertContentEquals(original, File(e.cleoDir, "heal.csi").readBytes())
    }

    @Test
    fun filesOfOtherModsAreNeverReplaced() {
        val e = env()
        val first = importer(e).import("heal.csi", script("Heal")).mod!!
        assertTrue(installer(e).apply(InstallPlanner(e.store).planInstall(first, e.destinations), e.destinations, false).success)
        val second = importer(e).import("heal.csi", script("Other")).mod!!
        val plan = InstallPlanner(e.store).planInstall(second, e.destinations)
        assertTrue(plan.blockers.any { it.contains("belongs to the installed mod") }, plan.describe())
        assertFalse(installer(e).apply(plan, e.destinations, confirmed = true).success)
    }

    @Test
    fun missingDestinationsAndBadNativeModsBlockInstallation() {
        val e = env()
        val mod = importer(e).import("heal.csi", script("Heal")).mod!!
        val plan = InstallPlanner(e.store).planInstall(mod, emptyMap())
        assertTrue(plan.blockers.any { it.contains("Choose a CLEO scripts folder") })

        val so64 = importer(e).import("libmod.so", ElfBuilder.amlMod(abi64 = true, guid = "net.test.mod")).mod!!
        val game32 = InstalledGame("com.rockstargames.gtasa", "2.00", 1, setOf(Abi.ARMEABI_V7A), emptyList(), true)
        val abiPlan = InstallPlanner(e.store).planInstall(so64, e.destinations, PlanContext(game = game32, amlDetected = true))
        assertTrue(abiPlan.blockers.any { it.contains("does not match the game") }, abiPlan.describe())

        val notAml = importer(e).import("libhelper.so", ElfBuilder.build(true, 183, exports = listOf("helper"))).mod!!
        val notAmlPlan = InstallPlanner(e.store).planInstall(notAml, e.destinations, PlanContext(amlDetected = true))
        assertTrue(notAmlPlan.blockers.any { it.contains("not an AML mod") }, notAmlPlan.describe())

        assertNull(importer(e).import("source.csa", "wait 0\nend_thread\n".toByteArray()).mod)
    }

    @Test
    fun archiveImportUsesManifestAndReadme() {
        val e = env()
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { z ->
            fun put(name: String, data: ByteArray) { z.putNextEntry(ZipEntry(name)); z.write(data); z.closeEntry() }
            put("MyPack/cleo/heal.csi", script("Heal"))
            put("MyPack/cleo/heal.fxt", "HEAL1 Healed!\n".toByteArray())
            put("MyPack/readme.txt", "Install with Rodwave".toByteArray())
            put("MyPack/rodwave-mod.json", """{"name":"Heal Pack","version":"1.2","requires":["cleo-android"]}""".toByteArray())
            put("../escape.csa", byteArrayOf(1))
        }
        val result = importer(e).import("pack.zip", out.toByteArray())
        val mod = assertNotNull(result.mod, result.messages.toString())
        assertEquals("Heal Pack", mod.name)
        assertEquals("1.2", mod.version)
        assertEquals(ModKind.BUNDLE, mod.kind)
        assertEquals(setOf("heal.csi", "heal.fxt"), mod.files.map { it.targetPath }.toSet())
        assertEquals("Install with Rodwave", mod.instructions)
        assertEquals(listOf("../escape.csa"), result.rejectedEntries)
        val plan = InstallPlanner(e.store).planInstall(mod, e.destinations, PlanContext(cleoLoaderDetected = true))
        assertTrue(plan.warnings.any { it.contains("cleo-android") })
        assertTrue(installer(e).apply(plan, e.destinations, false).success)
        assertTrue(File(e.cleoDir, "heal.fxt").exists())
    }

    @Test
    fun failuresRollBackCompletedSteps() {
        val e = env()
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { z ->
            z.putNextEntry(ZipEntry("a.csi")); z.write(script("A")); z.closeEntry()
            z.putNextEntry(ZipEntry("b.csi")); z.write(script("B")); z.closeEntry()
        }
        val mod = importer(e).import("two.zip", out.toByteArray()).mod!!
        val failing = FailingDir(LocalFile(e.cleoDir), failOn = "b.csi.rodwave-tmp")
        val destinations = mapOf<DestinationKind, VirtualFile>(DestinationKind.CLEO_SCRIPTS to failing)
        val plan = InstallPlanner(e.store).planInstall(mod, destinations)
        val result = installer(e).apply(plan, destinations, confirmed = false)
        assertFalse(result.success)
        assertEquals(OperationStatus.ROLLED_BACK, result.record!!.status)
        assertFalse(File(e.cleoDir, "a.csi").exists(), "a.csi must be removed by the rollback")
        assertTrue(e.store.installedFiles().isEmpty())
        assertFalse(e.store.mod(mod.id)!!.enabled)
    }

    @Test
    fun restoreOperationPutsBackReplacedFiles() {
        val e = env()
        File(e.cleoDir, "heal.csi").writeBytes("v1".toByteArray())
        val mod = importer(e).import("heal.csi", script("Heal")).mod!!
        val install = installer(e).apply(InstallPlanner(e.store).planInstall(mod, e.destinations), e.destinations, confirmed = true)
        assertTrue(install.success)
        val restored = installer(e).restoreOperation(install.record!!.id, e.destinations)
        assertTrue(restored.success, restored.message)
        assertEquals("v1", File(e.cleoDir, "heal.csi").readText())
    }

    /** Wraps a directory and fails when a file with [failOn] is created, to exercise rollback. */
    private class FailingDir(private val inner: VirtualFile, private val failOn: String) : VirtualFile by inner {
        override fun createFile(name: String): VirtualFile {
            if (name == failOn) throw FsException("Simulated storage failure")
            return inner.createFile(name)
        }
        override fun child(name: String): VirtualFile? = inner.child(name)
        override fun list(): List<VirtualFile> = inner.list()
        override fun openInput(): InputStream = inner.openInput()
        override fun openOutput(): OutputStream = inner.openOutput()
    }
}
