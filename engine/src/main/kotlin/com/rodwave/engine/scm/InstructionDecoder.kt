package com.rodwave.engine.scm

import com.rodwave.engine.opcode.OpcodeDatabase
import com.rodwave.engine.opcode.ParamType

sealed interface DecodeResult {
    data class Ok(val instruction: Instruction) : DecodeResult
    data class Error(val offset: Int, val message: String, val opcodeWord: Int? = null) : DecodeResult
}

/**
 * Decodes single instructions using an [OpcodeDatabase] for parameter counts.
 *
 * The decoder validates every length and type byte against the buffer bounds and never throws on
 * malformed input; it returns [DecodeResult.Error] with the offset of the first problem instead.
 */
class InstructionDecoder(val database: OpcodeDatabase) {

    fun decode(data: ByteArray, offset: Int, limit: Int = data.size): DecodeResult {
        if (offset < 0 || offset >= limit || limit > data.size) {
            return DecodeResult.Error(offset, "Offset $offset is outside the script (size $limit)")
        }
        val cursor = ByteCursor(data, offset, limit)
        var word: Int? = null
        return try {
            word = cursor.u16("opcode")
            val opcode = word and 0x7FFF
            val negated = word and 0x8000 != 0
            val def = database[opcode]
                ?: return DecodeResult.Error(
                    offset,
                    "Unknown opcode ${opcode.toString(16).uppercase().padStart(4, '0')} — not in the opcode database " +
                        "(${database.info.name}). Import the full Sanny Builder Library for complete coverage.",
                    word,
                )
            val operands = ArrayList<Operand>(def.params.size + 2)
            for (param in def.params) {
                if (param.type == ParamType.ARGUMENTS) {
                    var count = 0
                    while (true) {
                        val op = readOperand(cursor, allowEnd = true)
                        operands += op
                        if (op === EndOfArgs) break
                        if (++count > MAX_VARIADIC_ARGUMENTS) {
                            throw DecodeException(cursor.position, "Variadic argument list is not terminated within $MAX_VARIADIC_ARGUMENTS arguments")
                        }
                    }
                } else {
                    operands += readOperand(cursor, allowEnd = false)
                }
            }
            DecodeResult.Ok(Instruction(offset, opcode, negated, operands, def))
        } catch (e: DecodeException) {
            DecodeResult.Error(e.offset, e.message ?: "Malformed instruction", word)
        }
    }

    companion object {
        const val MAX_VARIADIC_ARGUMENTS = 64

        fun readOperand(cursor: ByteCursor, allowEnd: Boolean): Operand {
            val typeOffset = cursor.position
            val code = cursor.u8("parameter type")
            val type = DataType.fromCode(code)
                ?: throw DecodeException(typeOffset, "Unknown parameter data type 0x${code.toString(16).uppercase().padStart(2, '0')}")
            return when (type) {
                DataType.END_OF_ARGUMENTS ->
                    if (allowEnd) EndOfArgs else throw DecodeException(typeOffset, "Unexpected end-of-arguments marker where a parameter was expected")
                DataType.INT32 -> IntOperand(cursor.s32(), type)
                DataType.INT16 -> IntOperand(cursor.s16(), type)
                DataType.INT8 -> IntOperand(cursor.s8(), type)
                DataType.FLOAT32 -> FloatOperand(cursor.f32())
                DataType.GLOBAL_VAR, DataType.LOCAL_VAR,
                DataType.GLOBAL_STRING8_VAR, DataType.LOCAL_STRING8_VAR,
                DataType.GLOBAL_STRING16_VAR, DataType.LOCAL_STRING16_VAR -> VarOperand(type, cursor.u16("variable index"))
                DataType.GLOBAL_ARRAY, DataType.LOCAL_ARRAY,
                DataType.GLOBAL_STRING8_ARRAY, DataType.LOCAL_STRING8_ARRAY,
                DataType.GLOBAL_STRING16_ARRAY, DataType.LOCAL_STRING16_ARRAY -> {
                    val base = cursor.u16("array base")
                    val index = cursor.u16("array index variable")
                    val size = cursor.u8("array size")
                    val flags = cursor.u8("array flags")
                    ArrayOperand(type, base, index, size, flags and 0x7F, flags and 0x80 != 0)
                }
                DataType.STRING8 -> StringOperand(type, cursor.bytes(8, "8-byte string"))
                DataType.STRING16 -> StringOperand(type, cursor.bytes(16, "16-byte string"))
                DataType.STRING_VARLEN -> {
                    val length = cursor.u8("string length")
                    StringOperand(type, cursor.bytes(length, "string characters"))
                }
            }
        }
    }
}
