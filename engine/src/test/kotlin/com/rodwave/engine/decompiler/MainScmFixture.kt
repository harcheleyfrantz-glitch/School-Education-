package com.rodwave.engine.decompiler

import com.rodwave.engine.scm.BytecodeWriter
import com.rodwave.engine.scm.DataType
import com.rodwave.engine.scm.IntOperand
import com.rodwave.engine.scm.StringOperand

/**
 * Builds a small synthetic main.scm following the San Andreas header layout documented in
 * [com.rodwave.engine.scm.MainScmParser]. It is not a copy of any game file.
 */
object MainScmFixture {
    const val GLOBAL_SPACE = 64

    fun build(): ByteArray {
        val w = BytecodeWriter()
        fun gotoPlaceholder(): Int {
            w.opcode(0x0002, false)
            w.u8(DataType.INT32.code)
            val at = w.size
            w.s32(0)
            return at
        }
        // Segment 1: variables
        val seg1 = gotoPlaceholder()
        w.u8('s'.code)
        repeat(GLOBAL_SPACE) { w.u8(0) }
        w.patchS32(seg1, w.size)
        // Segment 2: models (first entry is empty by convention)
        val seg2 = gotoPlaceholder()
        w.u8(0)
        w.s32(2)
        w.bytes(ByteArray(24))
        w.bytes("CHEETAH".toByteArray().copyOf(24))
        w.patchS32(seg2, w.size)
        // Segment 3: missions (one mission)
        val seg3 = gotoPlaceholder()
        w.u8(1)
        val mainSizeAt = w.size
        w.s32(0) // main size, patched below
        w.s32(16) // largest mission
        w.u16(1) // mission count
        w.u16(0) // exclusive missions
        w.s32(8) // largest mission locals
        val missionOffsetAt = w.size
        w.s32(0)
        w.patchS32(seg3, w.size)
        // Segment 4: streamed scripts (none)
        val seg4 = gotoPlaceholder()
        w.u8(2)
        w.s32(0)
        w.s32(0)
        w.patchS32(seg4, w.size)
        // Segments 5 and 6
        val seg5 = gotoPlaceholder()
        w.u8(3)
        w.s32(0)
        w.patchS32(seg5, w.size)
        val seg6 = gotoPlaceholder()
        w.u8(4)
        w.s32(GLOBAL_SPACE)
        w.u8(0)
        w.u8(0)
        w.patchS32(seg6, w.size)
        // Main code: name the script, start mission 0, loop forever.
        val mainStart = w.size
        w.instruction(0x03A4, false, listOf(StringOperand.of(DataType.STRING8, "MAIN")))
        w.instruction(0x0417, false, listOf(IntOperand.minimal(0)))
        val loop = w.size
        w.instruction(0x0001, false, listOf(IntOperand.minimal(0)))
        w.instruction(0x0002, false, listOf(IntOperand(loop, DataType.INT32))) // absolute target in main
        val missionStart = w.size
        w.patchS32(mainSizeAt, missionStart)
        w.patchS32(missionOffsetAt, missionStart)
        // Mission: wait, then jump back to its own start + 0 (relative -4? use its second instruction)
        w.instruction(0x0001, false, listOf(IntOperand.minimal(100)))
        val second = w.size - missionStart
        w.instruction(0x0001, false, listOf(IntOperand.minimal(0)))
        w.instruction(0x0002, false, listOf(IntOperand(-second, DataType.INT32)))
        check(mainStart > 0)
        return w.toByteArray()
    }
}
