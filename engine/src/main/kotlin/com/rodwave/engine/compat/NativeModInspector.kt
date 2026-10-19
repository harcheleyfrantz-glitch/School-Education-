package com.rodwave.engine.compat

import com.rodwave.engine.elf.ElfException
import com.rodwave.engine.elf.ElfFile
import com.rodwave.engine.scm.Abi

/** What Rodwave can tell about a native `.so` file without loading it. */
data class NativeModInfo(
    val fileName: String,
    val size: Long,
    val isElf: Boolean,
    val isSharedObject: Boolean,
    val abi: Abi?,
    /** Exports `__GetModInfo`, the symbol AML requires from every mod. */
    val isAmlMod: Boolean,
    /** Exports `__GetDepsList` (dependency list readable only at runtime by AML). */
    val declaresDependencies: Boolean,
    /** Exports `__INeedASpecificGame` (the mod restricts itself to one package). */
    val restrictsGame: Boolean,
    /** AML entry points the library exports (OnModLoad, ...). */
    val amlCallbacks: List<String>,
    val neededLibraries: List<String>,
    /** Reverse-domain strings found in read-only data (heuristic: own GUID and/or dependencies). */
    val guidCandidates: List<String>,
    /** The GTA SA package name appears in the library's strings (heuristic). */
    val mentionsGtaSa: Boolean,
    val error: String?,
) {
    val isLoaderCompatibleAbi: Boolean get() = abi == Abi.ARMEABI_V7A || abi == Abi.ARM64_V8A
}

object NativeModInspector {
    val AML_CALLBACKS = listOf(
        "OnModPreLoad", "OnModLoad", "OnAllModsLoaded", "OnModUnload", "OnGameCrash", "OnInterfaceAdded", "OnUpdaterURLRequested",
    )
    private val GUID_PATTERN = Regex("^[a-z][a-z0-9_]*(\\.[a-z0-9_][a-z0-9_-]*){2,}$")
    private val NOT_GUIDS = listOf("android.", "java.", "javax.", "dalvik.", "com.android.", "kotlin.", "libc.", "org.apache.")

    fun inspect(fileName: String, bytes: ByteArray): NativeModInfo {
        if (!ElfFile.isElf(bytes)) {
            return NativeModInfo(fileName, bytes.size.toLong(), false, false, null, false, false, false, emptyList(), emptyList(), emptyList(), false, "Not an ELF shared library")
        }
        return try {
            val elf = ElfFile.parse(bytes)
            val strings = elf.readOnlyStrings(minLength = 5)
            val guids = strings.asSequence()
                .map { it.trim() }
                .filter { it.length in 5..100 && GUID_PATTERN.matches(it) && NOT_GUIDS.none { p -> it.startsWith(p) } }
                .filter { !it.endsWith(".so") && !it.endsWith(".ini") && !it.endsWith(".txt") && !it.endsWith(".cpp") && !it.endsWith(".h") }
                .distinct()
                .take(50)
                .toList()
            NativeModInfo(
                fileName = fileName,
                size = bytes.size.toLong(),
                isElf = true,
                isSharedObject = elf.isSharedObject,
                abi = elf.abi,
                isAmlMod = elf.exports("__GetModInfo"),
                declaresDependencies = elf.exports("__GetDepsList"),
                restrictsGame = elf.exports("__INeedASpecificGame"),
                amlCallbacks = AML_CALLBACKS.filter { elf.exports(it) },
                neededLibraries = elf.neededLibraries,
                guidCandidates = guids.filter { it != KnownGuids.GTA_SA_PACKAGE },
                mentionsGtaSa = strings.any { KnownGuids.GTA_SA_PACKAGE in it },
                error = null,
            )
        } catch (e: ElfException) {
            NativeModInfo(fileName, bytes.size.toLong(), true, false, null, false, false, false, emptyList(), emptyList(), emptyList(), false, e.message)
        }
    }
}

/** Identifiers confirmed from the AML sources and documentation. */
object KnownGuids {
    const val GTA_SA_PACKAGE = "com.rockstargames.gtasa"
    const val AML_CORE = "net.rusjj.aml"
    const val CLEO_LIBRARY = "net.rusjj.cleolib"
    const val BASS_LIBRARY = "net.rusjj.basslib"

    /** AML core writes `configs/ModLoaderCore.ini` on every launch. */
    const val AML_CORE_CONFIG = "ModLoaderCore.ini"

    val names = mapOf(
        AML_CORE to "AML core",
        CLEO_LIBRARY to "CLEO library for AML",
        BASS_LIBRARY to "BASS audio library for AML",
    )
}
