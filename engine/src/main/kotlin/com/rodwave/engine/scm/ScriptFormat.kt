package com.rodwave.engine.scm

/** Script container formats Rodwave understands. */
enum class ScriptFormat(val extension: String, val title: String, val description: String) {
    CLEO_ANDROID_AUTO(
        "csa",
        "CLEO Android script (.csa)",
        "Headerless CLEO script that CLEO Android starts automatically when a game is loaded.",
    ),
    CLEO_ANDROID_INVOKED(
        "csi",
        "CLEO Android script (.csi)",
        "Headerless CLEO script that the player starts from the CLEO Android menu.",
    ),
    CLEO_PC(
        "cs",
        "CLEO PC script (.cs)",
        "Headerless CLEO script for Windows CLEO. CLEO Android does not load .cs files, and PC CLEO opcodes " +
            "(0A8C and up) mean different commands in the mobile game.",
    ),
    MAIN_SCM(
        "scm",
        "Main script (main.scm)",
        "The game's main script: a segmented header followed by the main code and missions.",
    );

    /** CLEO scripts have no header; labels are encoded as negative offsets from the script start. */
    val isHeaderless: Boolean get() = this != MAIN_SCM
    val isCleoAndroid: Boolean get() = this == CLEO_ANDROID_AUTO || this == CLEO_ANDROID_INVOKED

    companion object {
        fun fromExtension(ext: String): ScriptFormat? = entries.firstOrNull { it.extension.equals(ext.trimStart('.'), ignoreCase = true) }

        fun fromFileName(name: String): ScriptFormat? =
            name.substringAfterLast('.', "").takeIf { it.isNotEmpty() && name.contains('.') }?.let(::fromExtension)
    }
}

/** Android ABIs relevant to GTA SA mobile and its native mod loaders. */
enum class Abi(val androidName: String, val bits: Int) {
    ARMEABI_V7A("armeabi-v7a", 32),
    ARM64_V8A("arm64-v8a", 64),
    X86("x86", 32),
    X86_64("x86_64", 64);

    companion object {
        fun fromAndroidName(name: String): Abi? = entries.firstOrNull { it.androidName == name }
    }
}
