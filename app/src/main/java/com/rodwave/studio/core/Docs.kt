package com.rodwave.studio.core

data class DocArticle(val id: String, val title: String, val summary: String, val body: String)

/** Built-in documentation (simple Markdown: #, ##, - bullets, ``` code blocks). */
object Docs {
    val ARTICLES = listOf(
        DocArticle(
            "start", "Getting started", "Create, compile and install your first CLEO Android script.",
            """
            # Getting started
            Rodwave is a script studio for GTA: San Andreas on Android. A typical workflow:
            - Create a project from a template on the Home screen.
            - Edit main.txt in the editor. Errors and warnings appear while you type.
            - Tap Compile. The compiled .csa or .csi file is saved in the project and can be exported or installed.
            - Install it through the Mod Manager, which shows a dry run before changing any file.

            ## Choosing folders
            Open Game Directory and pick the folders you can access: the CLEO scripts folder, the AML mods folder and an export folder. Android decides which folders an app may open; see "Android storage access".

            ## Script types
            - .csa scripts start automatically when a game is loaded.
            - .csi scripts are started by the player from the CLEO menu.
            The {${'$'}CLEO .csa} or {${'$'}CLEO .csi} line at the top of a script selects the output type.
            """.trimIndent(),
        ),
        DocArticle(
            "syntax", "Script syntax reference", "Everything the Rodwave compiler understands.",
            """
            # Script syntax reference
            Rodwave reads a Sanny Builder–compatible syntax. One statement per line.

            ## Opcodes and commands
            ```
            0001: wait 0 ms
            wait 250
            8256: not is_player_playing ${'$'}PLAYER_CHAR
            not 0256: is_player_playing ${'$'}PLAYER_CHAR
            ```
            After an opcode (0001:) words that are not values are descriptive text and ignored. Command names (wait, get_char_coordinates) come from the opcode library. Opcodes with bit 15 set (8256:) or a leading not are negated conditions.

            ## Values
            - Integers 5, -1, 0x1F; floats 1.0, -0.5
            - Global variables ${'$'}12 (byte offset 48), &48 (raw offset), ${'$'}PLAYER_CHAR, ${'$'}PLAYER_ACTOR
            - Local variables 0@ ... 31@, timers TIMERA (32@) and TIMERB (33@)
            - String variables 0@s, 0@v, s${'$'}12, v${'$'}12
            - Arrays ${'$'}100(0@,10i), 0@(1@,4f), s${'$'}20(0@,3s)
            - 'TEXT' is an 8-byte (up to 7 characters) or 16-byte (up to 15) string, "Text" a variable-length string
            - Labels :NAME and @NAME, models #CHEETAH, enums TouchPoints.Center, true and false

            ## Conditions
            ```
            if and
                0@ > 5
                0256: is_player_playing ${'$'}PLAYER_CHAR
            then
                wait 0
            else
                0@ = 0
            end
            ```
            if alone takes one condition, if and / if or up to eight. The classic form ends the conditions with jf @label instead of then.

            ## Loops
            ```
            while true
                wait 0
                if 0@ > 10 then
                    break
                end
            end
            repeat
                wait 0
                1@ += 1
            until 1@ > 3
            for 2@ = 1 to 10 step 2
                wait 0
            end
            ```

            ## Operators
            =, +=, -=, *=, /=, ++, --, +=@ and -=@ (timed), =# (int/float conversion); comparisons ==, <>, !=, >, >=, <, <=. The opcode is chosen from the operator and the operand kinds. When neither side reveals int or float, declare the variable:
            ```
            int counter = 0
            float speed
            var 3@: Float end
            ```

            ## Declarations and data
            ```
            const DELAY = 500, MODEL = #CHEETAH
            int score = 0
            hex
              01 02 03 04
            end
            {${'$'}INCLUDE helpers.txt}
            ```
            Named variables declared with int or float are given free local slots automatically.
            """.trimIndent(),
        ),
        DocArticle(
            "cleo", "CLEO Android basics", "How CLEO scripts run on the mobile game.",
            """
            # CLEO Android basics
            CLEO Android runs custom scripts alongside the game's own scripts. Scripts have no header; labels are stored as negative offsets from the start of the file.

            ## Rules of thumb
            - Every loop must call wait, otherwise the game freezes. Rodwave warns about loops without wait.
            - End a script with 004E: terminate_this_script. PC CLEO's 0A93 does not exist on Android.
            - A jump to the very first byte of a CLEO script is not possible; start with 0000: nop before the first label.
            - CLEO scripts have 32 local variables (0@ to 31@) plus the timers 32@ and 33@.

            ## Mobile-only commands
            - 0DE0 and 0DE1 read touch zones on a 3x3 grid (1 = left top ... 9 = right bottom).
            - 0DD5 and 0DD6 report the platform and game version; use them to guard version-specific code.
            - 0DD8 and 0DD9 read and write memory; addresses differ between game versions and between 32-bit and 64-bit builds.
            - 0DF2 creates CLEO's touch menu. Shared variable 0 (0DDC/0DDD) is reserved for the CLEO menu state.

            ## Text
            Custom text keys usually live in .fxt files next to the scripts: one KEY text pair per line, keys up to 7 characters. Rodwave validates .fxt files; whether they load depends on your CLEO build.
            """.trimIndent(),
        ),
        DocArticle(
            "storage", "Android storage access", "Why some folders cannot be opened and what to do instead.",
            """
            # Android storage access
            Rodwave uses the Storage Access Framework: you choose a folder in the system picker and Android grants access to that folder only. Rodwave never asks for root and never bypasses these rules.

            ## Android 11 and newer
            The system picker does not allow apps to open Android/data or Android/obb. The game's private folder Android/data/com.rockstargames.gtasa is therefore not selectable on most current phones. Selecting a parent folder does not grant access to it either.

            ## What works
            - AML loads mods from AMLMods/com.rockstargames.gtasa on shared storage, which you can select.
            - Choose an export folder (for example Download/Rodwave) and let Rodwave write compiled scripts there. Move them into the game folder with a file manager that has access, or from a computer.
            - On Android 10 and older you can usually select Android/data/com.rockstargames.gtasa directly.

            ## What Rodwave checks
            Rodwave detects the installed game through the package manager (version and ABI) without needing folder access. Folder scans only read files; installation always shows a dry run first.
            """.trimIndent(),
        ),
        DocArticle(
            "aml", "AML and native mods", "AndroidModLoader, .so mods and the CLEO library.",
            """
            # AML and native mods
            AndroidModLoader (AML) by RusJJ is injected into the game and loads native .so mods. It is a separate system from CLEO: CLEO runs bytecode scripts, AML runs native code. The CLEO library for AML (net.rusjj.cleolib) is an AML mod that adds CLEO script support.

            ## Facts from the AML source (v1.4.1)
            - Mods are loaded from Android/data/<package>/mods/ and AMLMods/<package>/ (the latter first by default).
            - Only files ending in .so are loaded, and each must export __GetModInfo.
            - Mods can declare dependencies (__GetDepsList) and restrict themselves to one game (__INeedASpecificGame).
            - AML writes configs/ModLoaderCore.ini on every launch; Rodwave uses it as evidence that AML ran.
            - AML supports armeabi-v7a and arm64-v8a. A mod must match the game's ABI.

            ## What Rodwave inspects
            Rodwave reads each .so file's ELF header and exported symbols without loading it: the ABI, whether it is an AML mod and which AML callbacks it exports. GUID-like strings found in the file are shown as hints, because the real dependency list is only available at runtime.
            """.trimIndent(),
        ),
        DocArticle(
            "porting", "Porting PC scripts", "Why .cs files from the PC version do not run on Android.",
            """
            # Porting PC scripts
            The mobile game's opcode table differs from the PC game from 0A4E upwards. PC CLEO's extension commands start at 0A8C, where the mobile game already has its own commands:
            ```
            0A8C  PC CLEO: WRITE_MEMORY   SA Mobile: LOAD_ALL_STREAMING_MODELS
            0A8D  PC CLEO: READ_MEMORY    SA Mobile: IS_HID_RELEASED
            0A8E  PC CLEO: INT_ADD        SA Mobile: UNLOCK_ACHIEVEMENT
            ```
            Rodwave decodes every script twice, once with the mobile table and once with a PC view. When a script only makes sense as a PC script, the inspector reports it as a PC CLEO script and lists the commands that need replacing.

            ## Typical replacements
            - 0A93 end_custom_thread -> 004E terminate_this_script
            - 0AB0 is_key_pressed -> 0DE0 get_touch_point_state
            - 0A8C/0A8D memory access -> 0DD9/0DD8 with addresses for your game version
            - 0ACA-0AD1 direct text printing -> an .fxt key with the regular print commands
            """.trimIndent(),
        ),
        DocArticle(
            "states", "Compatibility states", "What each state in the Compatibility Center means.",
            """
            # Compatibility states
            - Compatible: installed and every requirement Rodwave can check was verified (for example ABI and loader).
            - Partially compatible: installed, but something it needs is missing or only partly verified.
            - Installed but unverified: files were found, but Rodwave could not confirm they work. File names alone never count as more than this.
            - Not detected: no evidence in the checked locations.
            - Incompatible: verified not to work in this setup (wrong ABI, PC-only script, not an AML mod).
            - Unknown: Rodwave has no way to check yet, usually because no folder was scanned.
            Every state lists its evidence with a confidence level, and the report can be exported for troubleshooting.
            """.trimIndent(),
        ),
        DocArticle(
            "library", "Opcode library and licensing", "Built-in core set versus the full Sanny Builder Library.",
            """
            # Opcode library and licensing
            Rodwave ships a core set of SA Mobile opcodes: control flow, math, common game commands, the mobile widget commands and the CLEO Android extension. Its signatures were verified against the Sanny Builder Library (v0.517) and its descriptions are Rodwave's own.

            The full Sanny Builder Library (2,700+ commands) is maintained at github.com/sannybuilder/library. Its repository does not publish a license, so Rodwave does not redistribute it. You can import a copy of sa_mobile.json yourself, or let Rodwave download it from the official repository after you confirm. The imported library is stored privately and merged with the core set.
            """.trimIndent(),
        ),
        DocArticle(
            "mods", "Mod Manager safety", "Dry runs, backups and rollback.",
            """
            # Mod Manager safety
            - Importing copies files into Rodwave's library; nothing in the game folders changes.
            - Every install or uninstall starts with a dry run listing each file that would be created, replaced, deleted or restored.
            - Files Rodwave did not install are never replaced without your explicit confirmation, and files owned by another managed mod are never replaced.
            - Before replacing or deleting a file, Rodwave stores a verified backup.
            - Each written file is read back and compared. If any step fails, completed steps are undone.
            - The operation history keeps every step and lets you restore the backups of an operation.
            """.trimIndent(),
        ),
        DocArticle(
            "trouble", "Troubleshooting", "Common errors and how to fix them.",
            """
            # Troubleshooting
            ## Compiler messages
            - C093 label at the very start: add 0000: nop before the first label.
            - C083 cannot tell int or float: declare the variable with int or float.
            - C060 expecting N parameters: the status bar shows the expected parameters for the current line.
            - L005 loop never calls wait: add wait 0 inside the loop.
            - C050 unknown opcode: import the full opcode library or check the number.

            ## A script does not run
            - Check the Compatibility Center for a CLEO loader and its ABI.
            - Make sure the script is in the folder your loader reads (.csa for automatic start).
            - Open the compiled file in the Compiler & Decompiler screen; PC scripts are reported there.
            - Memory addresses (0DD8/0DD9) are version-specific; guard them with 0DD6 get_game_version.
            """.trimIndent(),
        ),
    )

    fun search(query: String): List<DocArticle> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return ARTICLES
        return ARTICLES.filter { it.title.lowercase().contains(q) || it.summary.lowercase().contains(q) || it.body.lowercase().contains(q) }
            .sortedByDescending { (if (it.title.lowercase().contains(q)) 2 else 0) + (if (it.summary.lowercase().contains(q)) 1 else 0) }
    }
}
