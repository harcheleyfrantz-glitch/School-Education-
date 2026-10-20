package com.rodwave.engine.analysis

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class HexDumpTest {
    @Test
    fun `rows show offsets hex and printable ascii`() {
        val bytes = byteArrayOf(0x01, 0x00, 0x04, 0x00) + "WAIT".toByteArray() + ByteArray(10) { 0x7F }
        val rows = HexDump.rows(bytes)
        assertEquals(2, rows.size)
        assertEquals("00000000  01 00 04 00 57 41 49 54  7F 7F 7F 7F 7F 7F 7F 7F  |....WAIT........|", rows[0])
        // Two bytes, then 14 empty slots (3 columns each, plus the extra gap after the 8th byte).
        assertEquals("00000010  7F 7F" + " ".repeat(1 + 14 * 3 + 1 + 1) + "|..|", rows[1])
    }

    @Test
    fun `ranges are clamped and aligned to rows`() {
        val bytes = ByteArray(40) { it.toByte() }
        assertEquals(listOf("00000010", "00000020"), HexDump.rows(bytes, start = 20, length = 100).map { it.take(8) })
        assertEquals(emptyList<String>(), HexDump.rows(bytes, start = 100, length = 10))
        assertEquals(emptyList<String>(), HexDump.rows(ByteArray(0)))
    }
}
