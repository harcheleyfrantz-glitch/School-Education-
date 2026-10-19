package com.rodwave.engine.compat

import com.rodwave.engine.analysis.ScriptAnalyzer
import com.rodwave.engine.analysis.ScriptReport
import com.rodwave.engine.fs.FsException
import com.rodwave.engine.fs.VirtualFile
import com.rodwave.engine.fs.readBytes
import com.rodwave.engine.fs.readText
import com.rodwave.engine.fs.walk
import com.rodwave.engine.opcode.OpcodeDatabase
import com.rodwave.engine.scm.ScriptFormat

/** A native library found during a scan. */
data class FoundNativeMod(val path: String, val info: NativeModInfo)

/** A compiled script found during a scan. */
data class FoundScript(val path: String, val format: ScriptFormat, val size: Long, val report: ScriptReport?)

/** State read from AML's `configs/ModLoaderCore.ini`. */
data class AmlCoreConfig(val path: String, val version: String?, val lastLaunchEpochSeconds: Long?, val internalModsFolder: String?)

data class ScanResult(
    val rootName: String,
    val location: LocationKind,
    val locationConfidence: Confidence,
    val locationEvidence: List<Evidence>,
    val saveFiles: List<String>,
    val scripts: List<FoundScript>,
    val fxtFiles: List<String>,
    val pcScripts: List<String>,
    val mainScmFiles: List<String>,
    val nativeMods: List<FoundNativeMod>,
    val configFiles: List<String>,
    val amlCore: AmlCoreConfig?,
    val notableFiles: List<String>,
    val filesScanned: Int,
    val truncated: Boolean,
    val errors: List<String>,
) {
    val scriptFolders: List<String> get() = scripts.map { it.path.substringBeforeLast('/', "") }.distinct()
    val modFolders: List<String> get() = nativeMods.map { it.path.substringBeforeLast('/', "") }.distinct()

    fun hasConfigFor(guid: String): Boolean = configFiles.any { it.substringAfterLast('/').equals("$guid.ini", ignoreCase = true) }
}

/**
 * Scans a folder the user granted access to and collects evidence about the game and its mods.
 *
 * The scan only reads files. Scripts and native libraries are inspected statically; nothing is
 * executed. Limits keep scans of large folders bounded.
 */
class GameDirectoryScanner(
    private val database: OpcodeDatabase,
    private val maxDepth: Int = 6,
    private val maxEntries: Int = 20_000,
    private val maxBytesRead: Long = 256L * 1024 * 1024,
) {
    fun scan(root: VirtualFile): ScanResult {
        val evidence = mutableListOf<Evidence>()
        val saves = mutableListOf<String>()
        val scripts = mutableListOf<FoundScript>()
        val fxt = mutableListOf<String>()
        val pc = mutableListOf<String>()
        val mainScm = mutableListOf<String>()
        val mods = mutableListOf<FoundNativeMod>()
        val configs = mutableListOf<String>()
        val notable = mutableListOf<String>()
        val errors = mutableListOf<String>()
        var amlCore: AmlCoreConfig? = null
        var bytesRead = 0L
        var count = 0

        fun budget(size: Long): Boolean {
            if (bytesRead + size > maxBytesRead) return false
            bytesRead += size
            return true
        }

        val rootLower = root.name.lowercase()
        if (rootLower == KnownGuids.GTA_SA_PACKAGE) {
            evidence += Evidence("The folder is named after the GTA SA package", Confidence.MEDIUM, root.path)
        }

        for (file in root.walk(maxDepth, maxEntries)) {
            count++
            val path = file.path
            val lower = file.name.lowercase()
            val segments = path.lowercase().split('/')
            if (file.isDirectory) {
                if (lower == KnownGuids.GTA_SA_PACKAGE) evidence += Evidence("Contains a folder named after the GTA SA package", Confidence.MEDIUM, path)
                if (lower == "amlmods") evidence += Evidence("Contains AML's internal mods folder (AMLMods)", Confidence.MEDIUM, path)
                continue
            }
            try {
                when {
                    Regex("gtasasf\\d+\\.b").matches(lower) -> saves += path
                    lower.endsWith(".csa") || lower.endsWith(".csi") -> {
                        val format = ScriptFormat.fromFileName(lower)!!
                        val report = if (file.length in 1..(4L * 1024 * 1024) && budget(file.length)) {
                            ScriptAnalyzer.analyze(file.readBytes(), file.name, database)
                        } else {
                            null
                        }
                        scripts += FoundScript(path, format, file.length, report)
                    }
                    lower.endsWith(".cs") -> pc += path
                    lower.endsWith(".fxt") -> fxt += path
                    lower == "main.scm" || lower == "script.img" -> mainScm += path
                    lower.endsWith(".so") -> {
                        val info = if (file.length in 1..(64L * 1024 * 1024) && budget(file.length)) {
                            NativeModInspector.inspect(file.name, file.readBytes())
                        } else {
                            NativeModInspector.inspect(file.name, ByteArray(0)).copy(error = "File too large to inspect")
                        }
                        mods += FoundNativeMod(path, info)
                        if ("fastman92" in lower) notable += path
                    }
                    lower.endsWith(".ini") && segments.contains("configs") -> {
                        configs += path
                        if (lower == KnownGuids.AML_CORE_CONFIG.lowercase() && file.length < 256 * 1024) {
                            val ini = IniFile.parse(file.readText(256 * 1024))
                            amlCore = AmlCoreConfig(
                                path = path,
                                version = ini.get("Version"),
                                lastLaunchEpochSeconds = ini.get("LaunchedTimeStamp")?.toLongOrNull(),
                                internalModsFolder = ini.get("InternalModsFolder"),
                            )
                        }
                    }
                    "fastman92" in lower -> notable += path
                }
            } catch (e: FsException) {
                errors += "${file.path}: ${e.message}"
            }
        }

        if (saves.isNotEmpty()) evidence += Evidence("Found ${saves.size} GTA SA save file(s) (GTASAsf*.b)", Confidence.MEDIUM, saves.first())
        if (amlCore != null) evidence += Evidence("AML core config ModLoaderCore.ini is present", Confidence.HIGH, amlCore!!.path)

        val location = when {
            rootLower == KnownGuids.GTA_SA_PACKAGE && (saves.isNotEmpty() || amlCore != null || configs.isNotEmpty()) -> LocationKind.GAME_DATA_FOLDER
            rootLower == KnownGuids.GTA_SA_PACKAGE && root.path.lowercase().contains("amlmods") -> LocationKind.AML_INTERNAL_MODS
            rootLower == KnownGuids.GTA_SA_PACKAGE -> LocationKind.GAME_DATA_FOLDER
            rootLower == "mods" && mods.isNotEmpty() -> LocationKind.MODS_FOLDER
            rootLower == "configs" -> LocationKind.CONFIGS_FOLDER
            rootLower == "amlmods" -> LocationKind.AML_INTERNAL_MODS
            scripts.isNotEmpty() -> LocationKind.SCRIPTS_FOLDER
            mods.isNotEmpty() -> LocationKind.MODS_FOLDER
            else -> LocationKind.GENERIC
        }
        val confidence = when {
            evidence.any { it.confidence == Confidence.HIGH } -> Confidence.HIGH
            evidence.size >= 2 -> Confidence.MEDIUM
            evidence.isNotEmpty() || location != LocationKind.GENERIC -> Confidence.LOW
            else -> Confidence.LOW
        }
        return ScanResult(
            rootName = root.name,
            location = location,
            locationConfidence = confidence,
            locationEvidence = evidence,
            saveFiles = saves,
            scripts = scripts,
            fxtFiles = fxt,
            pcScripts = pc,
            mainScmFiles = mainScm,
            nativeMods = mods,
            configFiles = configs,
            amlCore = amlCore,
            notableFiles = notable,
            filesScanned = count,
            truncated = count >= maxEntries,
            errors = errors,
        )
    }
}
