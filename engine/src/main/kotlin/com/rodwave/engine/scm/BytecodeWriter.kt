package com.rodwave.engine.scm

/** Growable little-endian byte buffer for emitting script bytecode. */
class BytecodeWriter(initialCapacity: Int = 256) {
    private var buffer = ByteArray(initialCapacity.coerceAtLeast(16))

    var size: Int = 0
        private set

    private fun ensure(extra: Int) {
        if (size + extra > buffer.size) {
            buffer = buffer.copyOf(maxOf(buffer.size * 2, size + extra))
        }
    }

    fun u8(value: Int) {
        ensure(1)
        buffer[size++] = value.toByte()
    }

    fun u16(value: Int) {
        ensure(2)
        buffer[size++] = value.toByte()
        buffer[size++] = (value shr 8).toByte()
    }

    fun s32(value: Int) {
        ensure(4)
        buffer[size++] = value.toByte()
        buffer[size++] = (value shr 8).toByte()
        buffer[size++] = (value shr 16).toByte()
        buffer[size++] = (value shr 24).toByte()
    }

    fun bytes(data: ByteArray) {
        ensure(data.size)
        data.copyInto(buffer, size)
        size += data.size
    }

    fun opcode(id: Int, negated: Boolean) {
        require(id in 0..0x7FFF) { "Opcode out of range: $id" }
        u16(id or if (negated) 0x8000 else 0)
    }

    fun operand(op: Operand) {
        u8(op.type.code)
        when (op) {
            is IntOperand -> when (op.type) {
                DataType.INT8 -> u8(op.value)
                DataType.INT16 -> u16(op.value)
                else -> s32(op.value)
            }
            is FloatOperand -> s32(op.value.toRawBits())
            is VarOperand -> u16(op.index)
            is ArrayOperand -> {
                u16(op.base)
                u16(op.indexVar)
                u8(op.size)
                u8(op.flagsByte)
            }
            is StringOperand -> {
                val raw = op.raw
                if (op.type == DataType.STRING_VARLEN) u8(raw.size)
                bytes(raw)
            }
            EndOfArgs -> Unit
        }
    }

    fun instruction(opcode: Int, negated: Boolean, operands: List<Operand>) {
        opcode(opcode, negated)
        operands.forEach(::operand)
    }

    /** Overwrites a previously written 32-bit value (used to back-patch label offsets). */
    fun patchS32(at: Int, value: Int) {
        require(at >= 0 && at + 4 <= size) { "Patch position $at outside written data" }
        buffer[at] = value.toByte()
        buffer[at + 1] = (value shr 8).toByte()
        buffer[at + 2] = (value shr 16).toByte()
        buffer[at + 3] = (value shr 24).toByte()
    }

    fun toByteArray(): ByteArray = buffer.copyOf(size)
}
