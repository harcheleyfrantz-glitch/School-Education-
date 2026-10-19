package com.rodwave.engine.compat

import com.rodwave.engine.analysis.ScriptVerdict
import com.rodwave.engine.scm.Abi

/** Per-mod verdict used by the Mod Manager and the native mods card. */
data class NativeModVerdict(val mod: FoundNativeMod, val state: ComponentState, val reasons: List<String>)

/**
 * Turns scan evidence and package information into component states.
 *
 * Rules: file presence alone never yields [ComponentState.COMPATIBLE]; that state requires the
 * checkable requirements (ABI, loader presence, file structure) to be verified.
 */
object CompatibilityEvaluator {

    fun evaluate(scan: ScanResult?, game: InstalledGame?): List<ComponentStatus> = listOf(
        gameStatus(scan, game),
        cleoAndroidStatus(scan, game),
        cleoLibraryStatus(scan, game),
        amlStatus(scan, game),
        nativeModsStatus(scan, game),
        fxtStatus(scan),
        pcCleoStatus(scan),
        mainScmStatus(scan),
        fastmanStatus(scan),
        ComponentStatus(ComponentProfiles.DEFINITIVE, ComponentState.INCOMPATIBLE, "Different engine; not supported by CLEO Android, AML or Rodwave."),
    )

    private fun gameStatus(scan: ScanResult?, game: InstalledGame?): ComponentStatus {
        val p = ComponentProfiles.GAME
        val evidence = mutableListOf<Evidence>()
        if (game != null) {
            evidence += Evidence("Package ${game.packageName} is installed (version ${game.versionName ?: "?"}, code ${game.versionCode ?: "?"})", Confidence.HIGH)
            if (game.abis.isNotEmpty()) evidence += Evidence("Native libraries: ${game.abis.joinToString { it.androidName }}", Confidence.HIGH)
            if (!game.apkReadable) evidence += Evidence("The APK contents could not be read, so injected loaders cannot be checked", Confidence.LOW)
            val known = GtaSaVersions.classify(game.versionName)
            return if (known != null) {
                ComponentStatus(p, ComponentState.COMPATIBLE, "Version $known is a recognised SA Mobile version.", evidence)
            } else {
                ComponentStatus(p, ComponentState.INSTALLED_UNVERIFIED, "Installed, but version '${game.versionName}' is not in CLEO Android's version table.", evidence)
            }
        }
        scan?.locationEvidence?.let { evidence += it }
        return if (scan != null && (scan.saveFiles.isNotEmpty() || scan.location == LocationKind.GAME_DATA_FOLDER)) {
            ComponentStatus(p, ComponentState.INSTALLED_UNVERIFIED, "Game files were found, but the installed package could not be checked.", evidence)
        } else {
            ComponentStatus(p, ComponentState.NOT_DETECTED, "The game package is not installed or not visible to Rodwave.", evidence)
        }
    }

    private fun amlStatus(scan: ScanResult?, game: InstalledGame?): ComponentStatus {
        val p = ComponentProfiles.AML
        val evidence = mutableListOf<Evidence>()
        val injected = game?.hasAml == true
        if (injected) evidence += Evidence("libAML.so is packaged in the installed game APK", Confidence.HIGH)
        val core = scan?.amlCore
        if (core != null) {
            evidence += Evidence("ModLoaderCore.ini written by AML ${core.version ?: "(version not recorded)"}", Confidence.HIGH, core.path)
        }
        val abi = game?.primaryAbi
        if (abi == Abi.X86 || abi == Abi.X86_64) {
            return ComponentStatus(p, ComponentState.INCOMPATIBLE, "AML supports ARM builds only; the installed game is ${abi.androidName}.", evidence)
        }
        return when {
            core != null -> ComponentStatus(p, ComponentState.COMPATIBLE, "AML ${core.version ?: ""} has run in this game data folder.".replace("  ", " "), evidence)
            injected -> ComponentStatus(p, ComponentState.INSTALLED_UNVERIFIED, "AML is packaged in the game but has not written its config here yet.", evidence)
            game != null && game.apkReadable -> ComponentStatus(p, ComponentState.NOT_DETECTED, "The installed APK does not contain libAML.so.", evidence)
            else -> ComponentStatus(p, if (scan == null) ComponentState.UNKNOWN else ComponentState.NOT_DETECTED, "No AML files were found in the scanned folder.", evidence)
        }
    }

    fun judgeNativeMod(mod: FoundNativeMod, game: InstalledGame?, amlPresent: Boolean, installedGuids: Set<String>): NativeModVerdict {
        val info = mod.info
        val reasons = mutableListOf<String>()
        if (!info.isElf || info.error != null) {
            return NativeModVerdict(mod, ComponentState.INCOMPATIBLE, listOf(info.error ?: "Not an ELF library"))
        }
        if (!info.isSharedObject) return NativeModVerdict(mod, ComponentState.INCOMPATIBLE, listOf("Not a shared library (ELF type is not ET_DYN)"))
        if (!info.isLoaderCompatibleAbi) {
            return NativeModVerdict(mod, ComponentState.INCOMPATIBLE, listOf("Built for ${info.abi?.androidName ?: "an unknown CPU"}; AML loads ARM libraries only"))
        }
        if (!info.isAmlMod) {
            return NativeModVerdict(mod, ComponentState.INCOMPATIBLE, listOf("Does not export __GetModInfo, so AML will not load it as a mod"))
        }
        reasons += "AML mod for ${info.abi!!.androidName}"
        val gameAbis = game?.abis.orEmpty()
        if (gameAbis.isNotEmpty() && info.abi !in gameAbis) {
            return NativeModVerdict(mod, ComponentState.INCOMPATIBLE, reasons + "The game runs as ${gameAbis.joinToString { it.androidName }}")
        }
        val missingDeps = if (info.declaresDependencies) {
            info.guidCandidates.filter { it in KnownGuids.names.keys && it !in installedGuids && it != KnownGuids.AML_CORE }
        } else {
            emptyList()
        }
        return when {
            gameAbis.isEmpty() -> NativeModVerdict(mod, ComponentState.INSTALLED_UNVERIFIED, reasons + "Game ABI unknown, so the ABI match could not be verified")
            !amlPresent -> NativeModVerdict(mod, ComponentState.PARTIALLY_COMPATIBLE, reasons + "AML was not detected; the mod cannot load without it")
            missingDeps.isNotEmpty() -> NativeModVerdict(
                mod, ComponentState.PARTIALLY_COMPATIBLE,
                reasons + "May depend on ${missingDeps.joinToString { KnownGuids.names[it] ?: it }} (hint from strings in the file)",
            )
            else -> NativeModVerdict(mod, ComponentState.COMPATIBLE, reasons + "ABI matches the game and AML is present")
        }
    }

    /**
     * GUIDs of mods that have demonstrably run: AML mods using MYMODCFG write `configs/<guid>.ini`.
     * GUID strings inside other libraries are not counted — they are often dependency references.
     */
    private fun installedGuids(scan: ScanResult?): Set<String> =
        scan?.configFiles.orEmpty().map { it.substringAfterLast('/').substringBeforeLast('.').lowercase() }.toSet()

    private fun nativeModsStatus(scan: ScanResult?, game: InstalledGame?): ComponentStatus {
        val p = ComponentProfiles.NATIVE_MODS
        val mods = scan?.nativeMods.orEmpty().filter { !it.info.fileName.equals("libAML.so", true) }
        if (mods.isEmpty()) return ComponentStatus(p, if (scan == null) ComponentState.UNKNOWN else ComponentState.NOT_DETECTED, "No .so files in the scanned folder.")
        val amlPresent = scan?.amlCore != null || game?.hasAml == true
        val verdicts = mods.map { judgeNativeMod(it, game, amlPresent, installedGuids(scan)) }
        val byState = verdicts.groupBy { it.state }
        val summary = byState.entries.sortedBy { it.key.ordinal }.joinToString { "${it.value.size} ${it.key.label.lowercase()}" }
        val state = when {
            verdicts.all { it.state == ComponentState.COMPATIBLE } -> ComponentState.COMPATIBLE
            verdicts.any { it.state == ComponentState.COMPATIBLE || it.state == ComponentState.PARTIALLY_COMPATIBLE } -> ComponentState.PARTIALLY_COMPATIBLE
            verdicts.all { it.state == ComponentState.INCOMPATIBLE } -> ComponentState.INCOMPATIBLE
            else -> ComponentState.INSTALLED_UNVERIFIED
        }
        val evidence = verdicts.map { v -> Evidence("${v.mod.info.fileName}: ${v.state.label} — ${v.reasons.joinToString("; ")}", Confidence.HIGH, v.mod.path) }
        return ComponentStatus(p, state, "${mods.size} native librar${if (mods.size == 1) "y" else "ies"}: $summary.", evidence)
    }

    private fun cleoLibraryStatus(scan: ScanResult?, game: InstalledGame?): ComponentStatus {
        val p = ComponentProfiles.CLEO_LIBRARY
        val evidence = mutableListOf<Evidence>()
        val configPresent = scan?.hasConfigFor(KnownGuids.CLEO_LIBRARY) == true
        if (configPresent) evidence += Evidence("configs/${KnownGuids.CLEO_LIBRARY}.ini exists: the library has been loaded by AML", Confidence.HIGH)
        val candidates = scan?.nativeMods.orEmpty().filter { m ->
            m.info.isAmlMod && "cleo" in m.info.fileName.lowercase() && KnownGuids.CLEO_LIBRARY in m.info.guidCandidates
        }
        candidates.forEach { evidence += Evidence("${it.info.fileName} is an AML mod referencing ${KnownGuids.CLEO_LIBRARY}", Confidence.MEDIUM, it.path) }
        val gameAbis = game?.abis.orEmpty()
        val abiMismatch = candidates.firstOrNull { gameAbis.isNotEmpty() && it.info.abi !in gameAbis }
        return when {
            abiMismatch != null -> ComponentStatus(
                p, ComponentState.INCOMPATIBLE,
                "${abiMismatch.info.fileName} is ${abiMismatch.info.abi?.androidName}, but the game is ${gameAbis.joinToString { it.androidName }}.", evidence,
            )
            configPresent && candidates.isNotEmpty() && gameAbis.isNotEmpty() -> ComponentStatus(p, ComponentState.COMPATIBLE, "Installed, ABI verified and loaded at least once.", evidence)
            configPresent -> ComponentStatus(p, ComponentState.PARTIALLY_COMPATIBLE, "Its config shows it has loaded; the library file or game ABI could not be checked.", evidence)
            candidates.isNotEmpty() -> ComponentStatus(p, ComponentState.INSTALLED_UNVERIFIED, "A matching library file was found but has not run yet.", evidence)
            else -> ComponentStatus(p, if (scan == null) ComponentState.UNKNOWN else ComponentState.NOT_DETECTED, "No CLEO library for AML was found.", evidence)
        }
    }

    private fun cleoAndroidStatus(scan: ScanResult?, game: InstalledGame?): ComponentStatus {
        val p = ComponentProfiles.CLEO_ANDROID
        val evidence = mutableListOf<Evidence>()
        val packaged = game?.nativeLibraries.orEmpty().filter { it.lowercase().startsWith("libcleo") }
        packaged.forEach { evidence += Evidence("$it is packaged in the installed game APK", Confidence.MEDIUM) }
        val scripts = scan?.scripts.orEmpty()
        if (scripts.isNotEmpty()) {
            evidence += Evidence("${scripts.size} CLEO script(s) found in: ${scan!!.scriptFolders.joinToString().ifEmpty { "/" }}", Confidence.LOW)
        }
        val pcScripts = scripts.filter { it.report?.verdict == ScriptVerdict.PC_SCRIPT }
        pcScripts.forEach { evidence += Evidence("${it.path} is a PC CLEO script and will not run", Confidence.HIGH, it.path) }
        val summary = buildString {
            when {
                packaged.isNotEmpty() -> append("A CLEO library is packaged in the game APK, but Rodwave cannot confirm it runs. ")
                scripts.isNotEmpty() -> append("Scripts are present, but no loader could be verified. ")
                else -> append("No CLEO Android loader or scripts were found. ")
            }
            if (pcScripts.isNotEmpty()) append("${pcScripts.size} script(s) are PC CLEO scripts. ")
        }.trim()
        val state = when {
            packaged.isNotEmpty() || scripts.isNotEmpty() -> ComponentState.INSTALLED_UNVERIFIED
            scan == null && game == null -> ComponentState.UNKNOWN
            else -> ComponentState.NOT_DETECTED
        }
        return ComponentStatus(p, state, summary, evidence)
    }

    private fun fxtStatus(scan: ScanResult?): ComponentStatus {
        val files = scan?.fxtFiles.orEmpty()
        return if (files.isEmpty()) {
            ComponentStatus(ComponentProfiles.FXT, if (scan == null) ComponentState.UNKNOWN else ComponentState.NOT_DETECTED, "No .fxt files found.")
        } else {
            ComponentStatus(
                ComponentProfiles.FXT, ComponentState.INSTALLED_UNVERIFIED, "${files.size} .fxt file(s) found; whether they load depends on your CLEO build.",
                files.map { Evidence("Found $it", Confidence.LOW, it) },
            )
        }
    }

    private fun pcCleoStatus(scan: ScanResult?): ComponentStatus {
        val files = scan?.pcScripts.orEmpty()
        val pcByContent = scan?.scripts.orEmpty().filter { it.report?.verdict == ScriptVerdict.PC_SCRIPT }.map { it.path }
        val all = files + pcByContent
        return ComponentStatus(
            ComponentProfiles.PC_CLEO, ComponentState.INCOMPATIBLE,
            if (all.isEmpty()) "PC CLEO scripts need porting before they run on Android." else "${all.size} PC script(s) found; they need porting.",
            all.map { Evidence("$it targets PC CLEO", Confidence.HIGH, it) },
        )
    }

    private fun mainScmStatus(scan: ScanResult?): ComponentStatus {
        val files = scan?.mainScmFiles.orEmpty()
        return ComponentStatus(
            ComponentProfiles.MAIN_SCM, if (files.isEmpty()) ComponentState.NOT_DETECTED else ComponentState.UNKNOWN,
            if (files.isEmpty()) "No main.scm or script.img in the scanned folder." else "Found ${files.joinToString()}. Rodwave can inspect but not install them.",
            files.map { Evidence("Found $it", Confidence.LOW, it) },
        )
    }

    private fun fastmanStatus(scan: ScanResult?): ComponentStatus {
        val files = scan?.notableFiles.orEmpty().filter { "fastman92" in it.lowercase() }
        return if (files.isEmpty()) {
            ComponentStatus(ComponentProfiles.FASTMAN92, if (scan == null) ComponentState.UNKNOWN else ComponentState.NOT_DETECTED, "No files named after Fastman92's tools were found.")
        } else {
            ComponentStatus(ComponentProfiles.FASTMAN92, ComponentState.INSTALLED_UNVERIFIED, "Files with matching names were found (name match only).", files.map { Evidence("Found $it", Confidence.LOW, it) })
        }
    }
}
