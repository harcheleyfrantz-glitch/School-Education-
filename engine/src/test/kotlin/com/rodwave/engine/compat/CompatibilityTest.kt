package com.rodwave.engine.compat

import com.rodwave.engine.analysis.ScriptAnalyzer
import com.rodwave.engine.analysis.ScriptVerdict
import com.rodwave.engine.compiler.ScriptCompiler
import com.rodwave.engine.elf.ElfBuilder
import com.rodwave.engine.elf.ElfFile
import com.rodwave.engine.fs.LocalFile
import com.rodwave.engine.hexBytes
import com.rodwave.engine.opcode.CoreOpcodes
import com.rodwave.engine.project.Templates
import com.rodwave.engine.scm.Abi
import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class CompatibilityTest {
    private val db = CoreOpcodes.database

    /** PC CLEO: 0A8C write_memory 0x123456 4 0 1, then 0A93 terminate_this_custom_script. */
    private val pcScript = hexBytes("8C 0A 01 56 34 12 00 04 04 04 00 04 01 93 0A")

    private fun fakeGameFolder(): File {
        val base = Files.createTempDirectory("rw-compat").toFile()
        val pkg = File(base, "com.rockstargames.gtasa").apply { mkdirs() }
        File(pkg, "files").mkdirs()
        File(pkg, "files/GTASAsf1.b").writeBytes(ByteArray(100))
        File(pkg, "configs").mkdirs()
        File(pkg, "configs/ModLoaderCore.ini").writeText("[Preferences]\nAuthor=RusJJ\nVersion=1.4.1\nLaunchedTimeStamp=1760000000\n")
        File(pkg, "configs/net.rusjj.cleolib.ini").writeText("[Settings]\n")
        File(pkg, "mods").mkdirs()
        File(pkg, "mods/libCLEOMod.so").writeBytes(ElfBuilder.amlMod(abi64 = true, guid = "net.rusjj.cleolib"))
        File(pkg, "mods/libNeedsBass.so").writeBytes(ElfBuilder.amlMod(abi64 = true, guid = "net.someone.music", extraStrings = listOf("net.rusjj.basslib"), withDeps = true))
        File(pkg, "mods/libx86.so").writeBytes(ElfBuilder.build(false, ElfFile.EM_386, exports = listOf("__GetModInfo")))
        File(pkg, "mods/libhelper.so").writeBytes(ElfBuilder.build(true, ElfFile.EM_AARCH64, exports = listOf("helper")))
        File(pkg, "mods/libCLEO_fake.so").writeBytes("I am not a library".toByteArray())
        File(pkg, "cleo").mkdirs()
        val compiled = ScriptCompiler(db).compile(Templates.HEAL.source("Heal")).bytes!!
        File(pkg, "cleo/heal.csi").writeBytes(compiled)
        File(pkg, "cleo/ported_from_pc.csa").writeBytes(pcScript)
        File(pkg, "cleo/text.fxt").writeText("HELLO Hello world\n")
        File(pkg, "old.cs").writeBytes(pcScript)
        return pkg
    }

    @Test
    fun analyzerSeparatesMobileAndPcScripts() {
        val mobile = ScriptAnalyzer.analyze(ScriptCompiler(db).compile(Templates.TOUCH_TOGGLE.source("T")).bytes!!, "t.csa", db)
        assertEquals(ScriptVerdict.READY, mobile.verdict, mobile.findings.toString())
        assertTrue(mobile.usesTouch)
        assertTrue(0x0DE0 in mobile.cleoAndroidCommands)
        assertEquals("T", mobile.scriptName)

        val pc = ScriptAnalyzer.analyze(pcScript, "pc.cs", db)
        assertEquals(ScriptVerdict.PC_SCRIPT, pc.verdict, pc.findings.toString())
        assertEquals(listOf(0x0A8C, 0x0A93), pc.pcCommands.map { it.opcode })
        assertTrue(pc.findings.any { it.title.contains("0A8C") })

        assertEquals(ScriptVerdict.NOT_A_SCRIPT, ScriptAnalyzer.analyze("wait 0\nend_thread\n".toByteArray(), "x.csa", db).verdict)
        assertEquals(ScriptVerdict.NOT_A_SCRIPT, ScriptAnalyzer.analyze(ElfBuilder.build(true, 183), "x.csa", db).verdict)
    }

    @Test
    fun scansAGameDataFolder() {
        val dir = fakeGameFolder()
        val scan = GameDirectoryScanner(db).scan(LocalFile(dir))
        assertEquals(LocationKind.GAME_DATA_FOLDER, scan.location)
        assertEquals(Confidence.HIGH, scan.locationConfidence)
        assertEquals(listOf("files/GTASAsf1.b"), scan.saveFiles)
        val aml = assertNotNull(scan.amlCore)
        assertEquals("1.4.1", aml.version)
        assertEquals(1760000000L, aml.lastLaunchEpochSeconds)
        assertEquals(2, scan.scripts.size)
        assertEquals(listOf("cleo"), scan.scriptFolders)
        assertEquals(5, scan.nativeMods.size)
        assertTrue(scan.hasConfigFor("net.rusjj.cleolib"))
        assertEquals(listOf("old.cs"), scan.pcScripts)
    }

    @Test
    fun evaluatesStatesFromEvidenceOnly() {
        val scan = GameDirectoryScanner(db).scan(LocalFile(fakeGameFolder()))
        val game = InstalledGame("com.rockstargames.gtasa", "2.00", 200, setOf(Abi.ARM64_V8A), listOf("libGTASA.so", "libAML.so"), apkReadable = true)
        val statuses = CompatibilityEvaluator.evaluate(scan, game).associateBy { it.profile.id }
        assertEquals(ComponentState.COMPATIBLE, statuses.getValue("gtasa-android").state)
        assertEquals(ComponentState.COMPATIBLE, statuses.getValue("aml").state)
        assertEquals(ComponentState.COMPATIBLE, statuses.getValue("cleo-aml").state)
        assertEquals(ComponentState.PARTIALLY_COMPATIBLE, statuses.getValue("aml-mods").state)
        assertEquals(ComponentState.INSTALLED_UNVERIFIED, statuses.getValue("cleo-android").state)
        assertEquals(ComponentState.INSTALLED_UNVERIFIED, statuses.getValue("fxt").state)
        assertEquals(ComponentState.INCOMPATIBLE, statuses.getValue("pc-cleo").state)
        assertEquals(2, statuses.getValue("pc-cleo").evidence.size) // old.cs + ported_from_pc.csa by content

        val verdicts = scan.nativeMods.associate { it.info.fileName to CompatibilityEvaluator.judgeNativeMod(it, game, true, setOf("net.rusjj.cleolib")).state }
        assertEquals(ComponentState.COMPATIBLE, verdicts["libCLEOMod.so"])
        assertEquals(ComponentState.PARTIALLY_COMPATIBLE, verdicts["libNeedsBass.so"]) // hints at the missing BASS library
        assertEquals(ComponentState.INCOMPATIBLE, verdicts["libx86.so"])
        assertEquals(ComponentState.INCOMPATIBLE, verdicts["libhelper.so"])
        // A file named like a CLEO library but containing junk is never treated as one.
        assertEquals(ComponentState.INCOMPATIBLE, verdicts["libCLEO_fake.so"])

        // A 32-bit game makes the 64-bit library incompatible.
        val game32 = game.copy(abis = setOf(Abi.ARMEABI_V7A))
        assertEquals(ComponentState.INCOMPATIBLE, CompatibilityEvaluator.evaluate(scan, game32).first { it.profile.id == "cleo-aml" }.state)
    }

    @Test
    fun withoutPackageInfoNothingIsCompatibleByFileNamesAlone() {
        val dir = Files.createTempDirectory("rw-names").toFile()
        File(dir, "mods").mkdirs()
        File(dir, "mods/libCLEOMod.so").writeBytes(ElfBuilder.amlMod(abi64 = true, guid = "net.rusjj.cleolib"))
        val scan = GameDirectoryScanner(db).scan(LocalFile(dir))
        val statuses = CompatibilityEvaluator.evaluate(scan, null).associateBy { it.profile.id }
        assertEquals(ComponentState.NOT_DETECTED, statuses.getValue("gtasa-android").state)
        assertEquals(ComponentState.INSTALLED_UNVERIFIED, statuses.getValue("cleo-aml").state)
        assertEquals(ComponentState.INSTALLED_UNVERIFIED, statuses.getValue("aml-mods").state)
        assertTrue(statuses.values.none { it.state == ComponentState.COMPATIBLE })
        val report = CompatibilityReport.render(statuses.values.toList(), scan, null, mapOf("Android" to "14"))
        assertTrue(report.contains("Installed but unverified"))
        assertTrue(report.contains("Android: 14"))
    }

    @Test
    fun versionClassification() {
        assertEquals("1.08", GtaSaVersions.classify("1.08"))
        assertEquals("2.00+", GtaSaVersions.classify("2.11.32"))
        assertEquals(null, GtaSaVersions.classify("0.9"))
        assertEquals(null, GtaSaVersions.classify(null))
        assertTrue(GtaSaVersions.isLegacy("1.05"))
        assertEquals("1.4.1", IniFile.parse("; c\n[A]\nVersion = 1.4.1\n").get("version"))
    }
}
