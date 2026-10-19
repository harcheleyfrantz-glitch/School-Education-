package com.rodwave.engine.scm

import com.rodwave.engine.hexBytes
import com.rodwave.engine.opcode.CoreOpcodes
import com.rodwave.engine.toHex
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

class OperandCodecTest {

    private fun roundTrip(op: Operand): Operand {
        val w = BytecodeWriter()
        w.operand(op)
        val bytes = w.toByteArray()
        assertEquals(op.encodedSize, bytes.size, "encoded size of $op")
        val cursor = ByteCursor(bytes, 0)
        val back = InstructionDecoder.readOperand(cursor, allowEnd = true)
        assertEquals(bytes.size, cursor.position)
        return back
    }

    @Test
    fun everyDataTypeRoundTrips() {
        val operands = listOf(
            IntOperand(-128, DataType.INT8), IntOperand(127, DataType.INT8),
            IntOperand(-32768, DataType.INT16), IntOperand(300, DataType.INT16),
            IntOperand(Int.MIN_VALUE, DataType.INT32), IntOperand(5, DataType.INT32),
            FloatOperand(1.5f), FloatOperand(-0.0f), FloatOperand(Float.NaN),
            VarOperand(DataType.GLOBAL_VAR, 8), VarOperand(DataType.LOCAL_VAR, 33),
            VarOperand(DataType.GLOBAL_STRING8_VAR, 400), VarOperand(DataType.LOCAL_STRING8_VAR, 2),
            VarOperand(DataType.GLOBAL_STRING16_VAR, 404), VarOperand(DataType.LOCAL_STRING16_VAR, 4),
            ArrayOperand(DataType.GLOBAL_ARRAY, 400, 0, 10, 0, indexIsGlobal = false),
            ArrayOperand(DataType.LOCAL_ARRAY, 2, 12, 4, 1, indexIsGlobal = true),
            ArrayOperand(DataType.GLOBAL_STRING8_ARRAY, 500, 1, 3, 2, indexIsGlobal = false),
            ArrayOperand(DataType.LOCAL_STRING16_ARRAY, 8, 1, 2, 3, indexIsGlobal = false),
            StringOperand.of(DataType.STRING8, "MAIN"),
            StringOperand.of(DataType.STRING16, "LONGERNAME"),
            StringOperand.of(DataType.STRING_VARLEN, "Hello, San Andreas"),
            EndOfArgs,
        )
        for (op in operands) {
            assertEquals(op, roundTrip(op))
        }
    }

    @Test
    fun knownEncodings() {
        fun enc(op: Operand) = BytecodeWriter().apply { operand(op) }.toByteArray().toHex()
        assertEquals("04 FF", enc(IntOperand(-1, DataType.INT8)))
        assertEquals("05 FA 00", enc(IntOperand(250, DataType.INT16)))
        assertEquals("01 FE FF FF FF", enc(IntOperand(-2, DataType.INT32)))
        assertEquals("06 00 00 C0 3F", enc(FloatOperand(1.5f)))
        assertEquals("02 08 00", enc(VarOperand(DataType.GLOBAL_VAR, 8)))
        assertEquals("03 1F 00", enc(VarOperand(DataType.LOCAL_VAR, 31)))
        assertEquals("09 4D 41 49 4E 00 00 00 00", enc(StringOperand.of(DataType.STRING8, "MAIN")))
        assertEquals("0E 02 48 49", enc(StringOperand.of(DataType.STRING_VARLEN, "HI")))
        // Array flags: element type in the low bits, bit 7 set when the index variable is global.
        assertEquals("07 90 01 08 00 0A 81", enc(ArrayOperand(DataType.GLOBAL_ARRAY, 400, 8, 10, 1, indexIsGlobal = true)))
    }

    @Test
    fun minimalIntegerWidths() {
        assertEquals(DataType.INT8, IntOperand.minimal(0).type)
        assertEquals(DataType.INT8, IntOperand.minimal(-128).type)
        assertEquals(DataType.INT16, IntOperand.minimal(128).type)
        assertEquals(DataType.INT16, IntOperand.minimal(-32768).type)
        assertEquals(DataType.INT32, IntOperand.minimal(32768).type)
    }

    @Test
    fun decoderRejectsMalformedInput() {
        val decoder = InstructionDecoder(CoreOpcodes.database)
        // WAIT with a truncated 16-bit parameter.
        val truncated = decoder.decode(hexBytes("01 00 05 FA"), 0)
        assertIs<DecodeResult.Error>(truncated)
        assertTrue(truncated.message.contains("Unexpected end"))
        // Unknown data type 0x20.
        val badType = decoder.decode(hexBytes("01 00 20 00"), 0)
        assertIs<DecodeResult.Error>(badType)
        assertTrue(badType.message.contains("data type"))
        // Unknown opcode.
        val unknown = decoder.decode(hexBytes("FF 7F"), 0)
        assertIs<DecodeResult.Error>(unknown)
        assertTrue(unknown.message.contains("Unknown opcode 7FFF"))
        // End-of-arguments marker where a fixed parameter is required.
        assertIs<DecodeResult.Error>(decoder.decode(hexBytes("01 00 00"), 0))
        // Variable-length string longer than the data.
        assertIs<DecodeResult.Error>(decoder.decode(hexBytes("A4 03 0E 10 41"), 0))
    }

    @Test
    fun decodesNegatedConditionAndVariadicList() {
        val decoder = InstructionDecoder(CoreOpcodes.database)
        val negated = decoder.decode(hexBytes("56 82 02 08 00"), 0)
        assertIs<DecodeResult.Ok>(negated)
        assertEquals(0x0256, negated.instruction.opcode)
        assertTrue(negated.instruction.negated)
        // 004F START_NEW_SCRIPT @-20 with two arguments then the 0x00 terminator.
        val start = decoder.decode(hexBytes("4F 00 01 EC FF FF FF 04 01 06 00 00 80 3F 00"), 0)
        assertIs<DecodeResult.Ok>(start)
        assertEquals(15, start.instruction.length)
        assertEquals(EndOfArgs, start.instruction.operands.last())
    }
}
