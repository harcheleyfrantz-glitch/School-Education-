package com.rodwave.engine.scm

/** One encoded instruction parameter. [encodedSize] includes the leading type byte. */
sealed class Operand {
    abstract val type: DataType
    abstract val encodedSize: Int
}

/** Immediate integer stored as 8, 16 or 32 bits. */
data class IntOperand(val value: Int, override val type: DataType) : Operand() {
    init {
        require(type.isImmediateInt) { "IntOperand requires an integer data type, got $type" }
        require(fits(value, type)) { "Value $value does not fit in $type" }
    }

    override val encodedSize: Int
        get() = 1 + when (type) {
            DataType.INT8 -> 1
            DataType.INT16 -> 2
            else -> 4
        }

    companion object {
        /** Smallest encoding, matching the choice made by Sanny Builder. */
        fun minimal(value: Int): IntOperand = IntOperand(value, minimalType(value))

        fun minimalType(value: Int): DataType = when (value) {
            in Byte.MIN_VALUE..Byte.MAX_VALUE -> DataType.INT8
            in Short.MIN_VALUE..Short.MAX_VALUE -> DataType.INT16
            else -> DataType.INT32
        }

        fun fits(value: Int, type: DataType): Boolean = when (type) {
            DataType.INT8 -> value in Byte.MIN_VALUE..Byte.MAX_VALUE
            DataType.INT16 -> value in Short.MIN_VALUE..Short.MAX_VALUE
            DataType.INT32 -> true
            else -> false
        }
    }
}

data class FloatOperand(val value: Float) : Operand() {
    override val type: DataType get() = DataType.FLOAT32
    override val encodedSize: Int get() = 5

    // Compare bit patterns so that -0.0, NaN payloads etc. round-trip exactly.
    override fun equals(other: Any?): Boolean = other is FloatOperand && other.value.toRawBits() == value.toRawBits()
    override fun hashCode(): Int = value.toRawBits()
}

/**
 * A plain variable. For globals [index] is the byte offset into the script's variable space
 * (Sanny Builder writes `$N` for offset N*4); for locals it is the local slot index (`N@`).
 */
data class VarOperand(override val type: DataType, val index: Int) : Operand() {
    init {
        require(type.isVariable && !type.isArray) { "VarOperand requires a non-array variable type, got $type" }
        require(index in 0..0xFFFF) { "Variable index $index out of range" }
    }

    override val encodedSize: Int get() = 3
}

/** Array element reference: `base[indexVar]` with a declared [size] and element type. */
data class ArrayOperand(
    override val type: DataType,
    val base: Int,
    val indexVar: Int,
    val size: Int,
    val elementTypeCode: Int,
    val indexIsGlobal: Boolean,
) : Operand() {
    init {
        require(type.isArray) { "ArrayOperand requires an array type, got $type" }
        require(base in 0..0xFFFF && indexVar in 0..0xFFFF) { "Array base/index out of range" }
        require(size in 0..0xFF) { "Array size $size out of range" }
        require(elementTypeCode in 0..0x7F) { "Array element type $elementTypeCode out of range" }
    }

    val elementType: ArrayElementType? get() = ArrayElementType.fromCode(elementTypeCode)
    val flagsByte: Int get() = (elementTypeCode and 0x7F) or (if (indexIsGlobal) 0x80 else 0)
    override val encodedSize: Int get() = 7
}

/**
 * String literal. For fixed-size strings [raw] holds the exact 8 or 16 bytes as stored (including
 * the zero padding and anything after the terminator); for variable-length strings it holds the
 * characters without the length byte.
 */
class StringOperand(override val type: DataType, raw: ByteArray) : Operand() {
    private val bytes: ByteArray = raw.copyOf()

    init {
        require(type.isStringLiteral) { "StringOperand requires a string literal type, got $type" }
        when (type) {
            DataType.STRING8 -> require(bytes.size == 8) { "8-byte string must be exactly 8 bytes" }
            DataType.STRING16 -> require(bytes.size == 16) { "16-byte string must be exactly 16 bytes" }
            else -> require(bytes.size <= 255) { "Variable-length string is limited to 255 bytes" }
        }
    }

    val raw: ByteArray get() = bytes.copyOf()

    /** Text up to the first NUL byte, decoded as Latin-1 (the game's text encoding is single-byte). */
    val text: String
        get() {
            val end = bytes.indexOf(0).let { if (it < 0) bytes.size else it }
            return String(bytes, 0, end, Charsets.ISO_8859_1)
        }

    /** True when the stored bytes are exactly what [of] would produce for [text]. */
    val isCanonical: Boolean get() = of(type, text).bytes.contentEquals(bytes)

    override val encodedSize: Int
        get() = when (type) {
            DataType.STRING8 -> 9
            DataType.STRING16 -> 17
            else -> 2 + bytes.size
        }

    override fun equals(other: Any?): Boolean = other is StringOperand && other.type == type && other.bytes.contentEquals(bytes)
    override fun hashCode(): Int = type.hashCode() * 31 + bytes.contentHashCode()
    override fun toString(): String = "StringOperand($type, \"$text\")"

    companion object {
        fun of(type: DataType, text: String): StringOperand {
            val encoded = text.toByteArray(Charsets.ISO_8859_1)
            return when (type) {
                DataType.STRING8 -> {
                    require(encoded.size <= 8) { "8-byte string literal is too long" }
                    StringOperand(type, encoded.copyOf(8))
                }
                DataType.STRING16 -> {
                    require(encoded.size <= 16) { "16-byte string literal is too long" }
                    StringOperand(type, encoded.copyOf(16))
                }
                DataType.STRING_VARLEN -> StringOperand(type, encoded)
                else -> throw IllegalArgumentException("Not a string literal type: $type")
            }
        }
    }
}

/** The 0x00 byte that terminates a variadic argument list. */
data object EndOfArgs : Operand() {
    override val type: DataType get() = DataType.END_OF_ARGUMENTS
    override val encodedSize: Int get() = 1
}
