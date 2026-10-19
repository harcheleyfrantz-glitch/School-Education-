package com.rodwave.engine.opcode

/** Broad category of a parameter, derived from the library type name. */
enum class ParamType {
    INT, FLOAT, BOOL, STRING, LABEL, ARGUMENTS, ANY,
    /** Model id (`model_any`, `model_char`, `model_vehicle`, `model_object`). */
    MODEL,
    /** Text key into GXT/FXT tables (`gxt_key`, `zone_key`). */
    TEXT_KEY,
    /** Script/entity handle or enum value; encoded as an integer. */
    HANDLE,
    /** Long literal string (`string128`). */
    LONG_STRING;

    val isNumeric: Boolean get() = this == INT || this == FLOAT || this == BOOL || this == MODEL || this == HANDLE
    val isStringLike: Boolean get() = this == STRING || this == TEXT_KEY || this == LONG_STRING

    companion object {
        fun fromLibraryType(type: String): ParamType = when (type) {
            "int", "script_id" -> INT
            "float" -> FLOAT
            "bool" -> BOOL
            "string" -> STRING
            "gxt_key", "zone_key" -> TEXT_KEY
            "string128" -> LONG_STRING
            "label" -> LABEL
            "arguments" -> ARGUMENTS
            "any" -> ANY
            "model_any", "model_char", "model_vehicle", "model_object" -> MODEL
            else -> HANDLE
        }
    }
}

/** Where a parameter value may come from, as declared by the opcode library. */
enum class ParamSource(val libraryName: String?) {
    ANY(null), VAR_ANY("var_any"), VAR_GLOBAL("var_global"), VAR_LOCAL("var_local"), LITERAL("literal");

    val requiresVariable: Boolean get() = this == VAR_ANY || this == VAR_GLOBAL || this == VAR_LOCAL

    companion object {
        fun fromLibrary(name: String?): ParamSource = entries.firstOrNull { it.libraryName == name } ?: ANY
    }
}

data class ParamDefinition(
    val name: String,
    /** Type name as written in the opcode library, e.g. `int`, `Char`, `model_vehicle`. */
    val typeName: String,
    val source: ParamSource = ParamSource.ANY,
    val isOutput: Boolean = false,
) {
    val type: ParamType = ParamType.fromLibraryType(typeName)

    /** Human-readable name used in tooltips; falls back to the type name. */
    val displayName: String get() = name.ifBlank { typeName }
}

data class OpcodeDefinition(
    val id: Int,
    val name: String,
    /** Parameters in bytecode order: inputs first, then outputs. */
    val params: List<ParamDefinition> = emptyList(),
    val description: String = "",
    val extension: String = EXTENSION_DEFAULT,
    val className: String? = null,
    val member: String? = null,
    /** Operator symbol for math commands (`=`, `+`, `>`, `==`, `+=@`, `=#` ...). */
    val operator: String? = null,
    val isCondition: Boolean = false,
    val isBranch: Boolean = false,
    val isSegment: Boolean = false,
    val isNop: Boolean = false,
    val isUnsupported: Boolean = false,
    val isConstructor: Boolean = false,
    val isDestructor: Boolean = false,
    val isStatic: Boolean = false,
    val isOverload: Boolean = false,
    val platforms: List<String> = emptyList(),
) {
    init {
        require(id in 0..0x7FFF) { "Opcode id out of range: $id" }
        require(params.count { it.type == ParamType.ARGUMENTS } <= 1) { "At most one variadic parameter" }
        require(params.indexOfFirst { it.type == ParamType.ARGUMENTS }.let { it == -1 || it == params.lastIndex || params.drop(it + 1).all { p -> p.isOutput } }) {
            "Variadic argument list must come after all inputs"
        }
    }

    val hexId: String get() = id.toString(16).uppercase().padStart(4, '0')
    val isVariadic: Boolean get() = params.any { it.type == ParamType.ARGUMENTS }

    /** Number of fixed (non-variadic) parameters. */
    val fixedParamCount: Int get() = params.count { it.type != ParamType.ARGUMENTS }

    /** `wait`, `is_player_playing` — the keyword spelling used in source code. */
    val keyword: String get() = name.lowercase()

    /** One-line signature for tooltips: `0001: wait {time: int}`. */
    val signature: String
        get() = buildString {
            append(hexId).append(": ").append(keyword)
            params.forEach { p ->
                append(' ')
                append(if (p.isOutput) "[" else "{")
                append(p.displayName)
                if (p.name.isNotBlank()) append(": ").append(p.typeName)
                append(if (p.isOutput) "]" else "}")
            }
        }

    companion object {
        const val EXTENSION_DEFAULT = "default"
        const val EXTENSION_CLEO = "CLEO"
    }
}
