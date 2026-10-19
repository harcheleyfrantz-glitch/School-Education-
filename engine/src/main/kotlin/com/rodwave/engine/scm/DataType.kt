package com.rodwave.engine.scm

/**
 * Parameter data types of the GTA San Andreas script bytecode (also used by the mobile ports).
 *
 * Every instruction parameter is prefixed with one of these type bytes. The numbering matches the
 * game's own parameter-type enumeration (0x00..0x13 for San Andreas).
 */
enum class DataType(val code: Int, val label: String) {
    END_OF_ARGUMENTS(0x00, "end of argument list"),
    INT32(0x01, "32-bit integer"),
    GLOBAL_VAR(0x02, "global variable"),
    LOCAL_VAR(0x03, "local variable"),
    INT8(0x04, "8-bit integer"),
    INT16(0x05, "16-bit integer"),
    FLOAT32(0x06, "32-bit float"),
    GLOBAL_ARRAY(0x07, "global array"),
    LOCAL_ARRAY(0x08, "local array"),
    STRING8(0x09, "8-byte string"),
    GLOBAL_STRING8_VAR(0x0A, "global 8-byte string variable"),
    LOCAL_STRING8_VAR(0x0B, "local 8-byte string variable"),
    GLOBAL_STRING8_ARRAY(0x0C, "global 8-byte string array"),
    LOCAL_STRING8_ARRAY(0x0D, "local 8-byte string array"),
    STRING_VARLEN(0x0E, "variable-length string"),
    STRING16(0x0F, "16-byte string"),
    GLOBAL_STRING16_VAR(0x10, "global 16-byte string variable"),
    LOCAL_STRING16_VAR(0x11, "local 16-byte string variable"),
    GLOBAL_STRING16_ARRAY(0x12, "global 16-byte string array"),
    LOCAL_STRING16_ARRAY(0x13, "local 16-byte string array");

    val isImmediateInt: Boolean get() = this == INT8 || this == INT16 || this == INT32
    val isImmediate: Boolean get() = isImmediateInt || this == FLOAT32 || isStringLiteral
    val isStringLiteral: Boolean get() = this == STRING8 || this == STRING16 || this == STRING_VARLEN

    val isArray: Boolean
        get() = this == GLOBAL_ARRAY || this == LOCAL_ARRAY || this == GLOBAL_STRING8_ARRAY ||
            this == LOCAL_STRING8_ARRAY || this == GLOBAL_STRING16_ARRAY || this == LOCAL_STRING16_ARRAY

    val isVariable: Boolean
        get() = this == GLOBAL_VAR || this == LOCAL_VAR || this == GLOBAL_STRING8_VAR || this == LOCAL_STRING8_VAR ||
            this == GLOBAL_STRING16_VAR || this == LOCAL_STRING16_VAR || isArray

    val isGlobal: Boolean
        get() = this == GLOBAL_VAR || this == GLOBAL_ARRAY || this == GLOBAL_STRING8_VAR || this == GLOBAL_STRING8_ARRAY ||
            this == GLOBAL_STRING16_VAR || this == GLOBAL_STRING16_ARRAY

    val isLocal: Boolean get() = isVariable && !isGlobal

    /** Storage kind of the value held by a variable or array of this type. */
    val storage: VarStorage
        get() = when (this) {
            GLOBAL_STRING8_VAR, LOCAL_STRING8_VAR, GLOBAL_STRING8_ARRAY, LOCAL_STRING8_ARRAY -> VarStorage.STRING8
            GLOBAL_STRING16_VAR, LOCAL_STRING16_VAR, GLOBAL_STRING16_ARRAY, LOCAL_STRING16_ARRAY -> VarStorage.STRING16
            else -> VarStorage.NUMBER
        }

    companion object {
        private val byCode = entries.associateBy { it.code }
        fun fromCode(code: Int): DataType? = byCode[code]

        fun variable(global: Boolean, storage: VarStorage): DataType = when (storage) {
            VarStorage.NUMBER -> if (global) GLOBAL_VAR else LOCAL_VAR
            VarStorage.STRING8 -> if (global) GLOBAL_STRING8_VAR else LOCAL_STRING8_VAR
            VarStorage.STRING16 -> if (global) GLOBAL_STRING16_VAR else LOCAL_STRING16_VAR
        }

        fun array(global: Boolean, storage: VarStorage): DataType = when (storage) {
            VarStorage.NUMBER -> if (global) GLOBAL_ARRAY else LOCAL_ARRAY
            VarStorage.STRING8 -> if (global) GLOBAL_STRING8_ARRAY else LOCAL_STRING8_ARRAY
            VarStorage.STRING16 -> if (global) GLOBAL_STRING16_ARRAY else LOCAL_STRING16_ARRAY
        }
    }
}

/** What a variable slot holds: a 4-byte number (int or float), an 8-byte or a 16-byte string. */
enum class VarStorage(val slots: Int) { NUMBER(1), STRING8(2), STRING16(4) }

/** Element type stored in the flags byte of an array operand (low 7 bits). */
enum class ArrayElementType(val code: Int, val suffix: Char) {
    INT(0, 'i'), FLOAT(1, 'f'), STRING8(2, 's'), STRING16(3, 'v');

    companion object {
        fun fromCode(code: Int): ArrayElementType? = entries.firstOrNull { it.code == code }
        fun fromSuffix(c: Char): ArrayElementType? = entries.firstOrNull { it.suffix == c.lowercaseChar() }
    }
}
