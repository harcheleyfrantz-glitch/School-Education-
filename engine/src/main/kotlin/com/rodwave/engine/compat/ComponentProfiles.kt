package com.rodwave.engine.compat

/**
 * Knowledge base for the Compatibility Center.
 *
 * Every statement is backed by a source listed in [ComponentProfile.sources]. Where Rodwave could
 * not verify something (for example the folder a particular CLEO build reads scripts from), the
 * profile says so instead of guessing.
 */
object ComponentProfiles {
    private const val AML_REPO = "https://github.com/RusJJ/AndroidModLoader"
    private const val AML_MODS_ORG = "https://github.com/AndroidModLoader"
    private const val SBL = "https://library.sannybuilder.com/#/sa_mobile"

    val GAME = ComponentProfile(
        id = "gtasa-android",
        name = "GTA: San Andreas (Android)",
        category = ComponentCategory.GAME,
        summary = "The mobile port of San Andreas (package com.rockstargames.gtasa). Scripts are compiled for its " +
            "SA Mobile opcode table, which differs from the PC game from opcode 0A4E upwards.",
        supportedVersions = "Recognised versions: " + GtaSaVersions.KNOWN.joinToString(", "),
        supportedAbis = "armeabi-v7a; newer builds also ship arm64-v8a. Rodwave reads the ABI from the installed APK.",
        requirements = listOf("A legitimately installed copy of the game"),
        installSteps = listOf("Install the game from your store. Rodwave never modifies the game APK."),
        limitations = listOf(
            "Game data lives in the APK/OBB and in Android/data, which Android 11+ hides from other apps' folder pickers.",
            "GTA: San Andreas – Definitive Edition is a different game (Unreal Engine); none of the tools below apply to it.",
        ),
        sources = listOf(
            "Version list: CLEO Android's GameVerInternal enumeration (Sanny Builder Library sa_mobile enums, v0.517)",
            "Opcode differences: comparison of the sa and sa_mobile opcode tables in the Sanny Builder Library",
        ),
    )

    val CLEO_ANDROID = ComponentProfile(
        id = "cleo-android",
        name = "CLEO Android",
        category = ComponentCategory.SCRIPT_LOADER,
        summary = "Script loader by Alexander Blade that runs custom scripts in the mobile GTA games. Scripts are " +
            "headerless bytecode files: .csa start automatically, .csi are started from the CLEO menu.",
        supportedVersions = "Its version table covers SA 1.00–1.08 and \"2.00 or higher\" (GET_GAME_VERSION, 0DD6).",
        supportedAbis = "Depends on the loader build; check the library with Rodwave's native inspector.",
        requirements = listOf("A CLEO-enabled game installation (standalone CLEO Android or the CLEO library for AML)"),
        installSteps = listOf(
            "Install a CLEO loader that matches your game version and ABI.",
            "Copy .csa/.csi scripts (and .fxt text files if used) to the scripts folder your loader reads.",
            "Start the game; open the CLEO menu to launch .csi scripts.",
        ),
        limitations = listOf(
            "Adds opcodes 0DD0–0DF3 (memory, touch, menu) and touch support for 00E1; PC CLEO opcodes (0A8C+) are not available.",
            "Memory addresses used with 0DD8/0DD9/0DD2/0DDE are specific to one game version and ABI.",
            "Shared CLEO variable 0 is reserved for the CLEO menu state.",
            "The exact script folder depends on the loader build; Rodwave detects it from scripts already on your device or lets you choose it.",
        ),
        links = listOf(ExternalLink("Opcode reference (Sanny Builder Library)", SBL)),
        sources = listOf(
            "Opcodes and their notes: Sanny Builder Library sa_mobile, CLEO extension (v0.517)",
            ".csa/.csi meaning: CLEO Android convention used by Sanny Builder's {\$CLEO} directive",
        ),
    )

    val AML = ComponentProfile(
        id = "aml",
        name = "AndroidModLoader (AML)",
        category = ComponentCategory.NATIVE_LOADER,
        summary = "MIT-licensed native mod loader by RusJJ. It is injected into the game APK and loads .so mods " +
            "that export __GetModInfo.",
        supportedVersions = "Game-independent; individual mods target specific game versions.",
        supportedAbis = "armeabi-v7a and arm64-v8a only (AML32/AML64).",
        requirements = listOf("A game APK with libAML.so injected and loaded at startup"),
        installSteps = listOf(
            "Follow the official AML instructions to obtain a game build with AML injected.",
            "Mods (.so) go to Android/data/<package>/mods/ or to the internal folder AMLMods/<package>/ on shared storage.",
            "AML writes its settings to Android/data/<package>/configs/ModLoaderCore.ini on every launch.",
        ),
        limitations = listOf(
            "Only files ending in .so are loaded; each must export __GetModInfo.",
            "Mods must match the game's ABI (32-bit vs 64-bit).",
            "The internal folder AMLMods/<package>/ is loaded first by default (InternalModsFirst=true).",
        ),
        links = listOf(ExternalLink("AML source and releases", AML_REPO), ExternalLink("Official AML mods", AML_MODS_ORG)),
        sources = listOf(
            "AML 1.4.1 source: main.cpp (mod/config paths, LoadMods), mod/amlmod.h (exports), src/icfg.cpp (<config>.ini naming)",
            "AML documentation (docs/DOCUMENTATION_EN.MD): ABIs, mods locations, dependency macros",
        ),
    )

    val NATIVE_MODS = ComponentProfile(
        id = "aml-mods",
        name = "Native AML mods (.so)",
        category = ComponentCategory.NATIVE_MOD,
        summary = "Native libraries loaded by AML. Rodwave inspects their ELF headers and exports without loading them.",
        supportedVersions = "Per mod. Mods may restrict themselves to one game package (__INeedASpecificGame).",
        supportedAbis = "Must equal the game's ABI.",
        requirements = listOf("AML", "Matching ABI", "Declared dependencies (checked by AML at runtime via __GetDepsList)"),
        installSteps = listOf("Import the .so into Rodwave's Mod Manager, review the dry-run plan, then install to your mods folder."),
        limitations = listOf(
            "Dependency lists are only readable at runtime; Rodwave reports dependency GUIDs found in the file as hints.",
        ),
        links = listOf(ExternalLink("Official AML mods", AML_MODS_ORG)),
        sources = listOf("AML mod/amlmod.h: MYMOD, NEEDGAME, BEGIN_DEPLIST macros", "ELF specification for header/symbol parsing"),
    )

    val CLEO_LIBRARY = ComponentProfile(
        id = "cleo-aml",
        name = "CLEO library for AML",
        category = ComponentCategory.SCRIPT_LOADER,
        summary = "An AML mod with the GUID ${KnownGuids.CLEO_LIBRARY} that provides CLEO script support through AML. " +
            "CLEO scripts and AML native mods are separate systems: this library is what lets an AML setup run CLEO scripts.",
        supportedVersions = "Depends on the library build.",
        supportedAbis = "Must match the game's ABI; check the installed .so with Rodwave's inspector.",
        requirements = listOf("AML", "A build of the library matching your game version and ABI"),
        installSteps = listOf(
            "Install AML first.",
            "Place the CLEO library .so in the AML mods folder.",
            "Launch the game once; the library's config appearing in configs/ confirms it was loaded.",
        ),
        limitations = listOf("Rodwave could not verify the script folder used by every build; choose it in Game Directory settings."),
        links = listOf(ExternalLink("Official AML mods", AML_MODS_ORG)),
        sources = listOf("GUID referenced in the AML documentation's dependency example (ADD_DEPENDENCY_VER(net.rusjj.cleolib, ...))"),
    )

    val FXT = ComponentProfile(
        id = "fxt",
        name = "CLEO text files (.fxt)",
        category = ComponentCategory.FORMAT,
        summary = "Plain-text tables of custom text keys (KEY text) used by CLEO scripts with the regular print commands.",
        supportedVersions = "Same as the CLEO loader that reads them.",
        supportedAbis = "Not applicable (text file).",
        requirements = listOf("A CLEO loader that supports .fxt files"),
        installSteps = listOf("Put the .fxt file next to the scripts that use it."),
        limitations = listOf("Keys are limited to 7 characters, like game text keys.", "Rodwave validates the format; loading depends on your CLEO build."),
        sources = listOf("CLEO FXT format (KEY text per line, # comments)"),
    )

    val PC_CLEO = ComponentProfile(
        id = "pc-cleo",
        name = "PC CLEO scripts (.cs)",
        category = ComponentCategory.FORMAT,
        summary = "Scripts written for Windows CLEO. Their extension commands (0A8C–0AEF and up) collide with native " +
            "mobile opcodes, so they do not run on CLEO Android without porting.",
        supportedVersions = "GTA SA PC only.",
        supportedAbis = "Not applicable.",
        requirements = listOf("Porting: replace PC-only commands, re-target memory addresses, use touch input"),
        installSteps = listOf("Open the script in Rodwave's inspector to see which commands need porting."),
        limitations = listOf("Example: 0A8C is WRITE_MEMORY in PC CLEO but LOAD_ALL_STREAMING_MODELS in SA Mobile."),
        sources = listOf("Comparison of the sa (PC) and sa_mobile tables in the Sanny Builder Library v0.517"),
    )

    val MAIN_SCM = ComponentProfile(
        id = "main-scm",
        name = "main.scm / script.img",
        category = ComponentCategory.FORMAT,
        summary = "The game's own mission scripts. Rodwave can inspect a main.scm header and list its code, but does not rebuild it.",
        supportedVersions = "San Andreas header layout (6 segments).",
        supportedAbis = "Not applicable.",
        requirements = listOf("A copy of the file you are allowed to use"),
        installSteps = listOf("Replacing main.scm requires access to the game data, which Android normally restricts; Rodwave does not do this."),
        limitations = listOf("Read-only listing; Rodwave never ships Rockstar's scripts."),
        sources = listOf("San Andreas SCM header layout as parsed by MainScmParser"),
    )

    val FASTMAN92 = ComponentProfile(
        id = "fla",
        name = "Fastman92 Limit Adjuster (Android)",
        category = ComponentCategory.OTHER,
        summary = "A limit adjuster for the mobile game. AML contains special handling for its launcher's data folder.",
        supportedVersions = "Not verified by Rodwave.",
        supportedAbis = "Not verified by Rodwave.",
        requirements = listOf("See the author's documentation"),
        installSteps = listOf("Follow the author's instructions; Rodwave only detects files and does not install it."),
        limitations = listOf("Detection is by file name only, so it is never reported as compatible."),
        sources = listOf("AML 1.4.1 main.cpp (FASTMAN92_CODE path handling)"),
    )

    val DEFINITIVE = ComponentProfile(
        id = "sa-de",
        name = "San Andreas – Definitive Edition",
        category = ComponentCategory.GAME,
        summary = "The Unreal Engine remaster uses its own script table (sa_unreal) and is not supported by CLEO Android or AML.",
        supportedVersions = "Not supported.",
        supportedAbis = "Not applicable.",
        requirements = emptyList(),
        installSteps = emptyList(),
        limitations = listOf("Rodwave targets the classic mobile port only."),
        sources = listOf("Sanny Builder Library keeps sa_unreal as a separate game"),
    )

    val ALL = listOf(GAME, CLEO_ANDROID, CLEO_LIBRARY, AML, NATIVE_MODS, FXT, PC_CLEO, MAIN_SCM, FASTMAN92, DEFINITIVE)
}
