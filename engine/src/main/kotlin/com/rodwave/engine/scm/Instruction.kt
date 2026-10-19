package com.rodwave.engine.scm

import com.rodwave.engine.opcode.OpcodeDefinition

/**
 * A decoded instruction.
 *
 * @property offset byte offset of the opcode word within the decoded buffer
 * @property opcode opcode number without the negation bit (0x0000..0x7FFF)
 * @property negated true when the opcode word had bit 15 set ("NOT" condition)
 * @property operands decoded parameters in bytecode order; variadic lists include the [EndOfArgs] marker
 */
data class Instruction(
    val offset: Int,
    val opcode: Int,
    val negated: Boolean,
    val operands: List<Operand>,
    val definition: OpcodeDefinition?,
) {
    val length: Int get() = 2 + operands.sumOf { it.encodedSize }
    val end: Int get() = offset + length
    val word: Int get() = opcode or (if (negated) 0x8000 else 0)
    val hexOpcode: String get() = word.toString(16).uppercase().padStart(4, '0')
}

/** Opcode numbers the engine needs to recognise structurally. */
object Opcodes {
    const val NOP = 0x0000
    const val WAIT = 0x0001
    const val GOTO = 0x0002
    const val GOTO_IF_FALSE = 0x004D
    const val TERMINATE_THIS_SCRIPT = 0x004E
    const val START_NEW_SCRIPT = 0x004F
    const val GOSUB = 0x0050
    const val RETURN = 0x0051
    const val ANDOR = 0x00D6
    const val SCRIPT_NAME = 0x03A4

    // CLEO Android extension
    const val STORE_LABEL_POINTER = 0x0DD0

    /** Instructions after which execution never falls through to the next instruction. */
    val TERMINATORS = setOf(GOTO, TERMINATE_THIS_SCRIPT, RETURN)

    /** ANDOR operand ranges: 0 = single condition, 1..7 = AND of n+1, 21..27 = OR of n-19. */
    fun conditionCount(andOr: Int): Int? = when (andOr) {
        0 -> 1
        in 1..7 -> andOr + 1
        in 21..27 -> andOr - 19
        else -> null
    }
}
