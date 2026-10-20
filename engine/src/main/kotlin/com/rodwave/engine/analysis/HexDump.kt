package com.rodwave.engine.analysis

/** Classic 16-bytes-per-row hex dump used by the binary viewers. */
object HexDump {
    const val BYTES_PER_ROW = 16

    /** One row: offset, hex bytes and printable ASCII, e.g. `00000010  01 00 ...  |..|`. */
    fun row(bytes: ByteArray, offset: Int): String {
        val end = minOf(offset + BYTES_PER_ROW, bytes.size)
        return buildString {
            append(offset.toString(16).uppercase().padStart(8, '0')).append("  ")
            for (i in offset until offset + BYTES_PER_ROW) {
                if (i < end) append(HEX[(bytes[i].toInt() shr 4) and 0xF]).append(HEX[bytes[i].toInt() and 0xF]) else append("  ")
                append(if (i - offset == 7) "  " else " ")
            }
            append(" |")
            for (i in offset until end) {
                val c = bytes[i].toInt() and 0xFF
                append(if (c in 0x20..0x7E) c.toChar() else '.')
            }
            append('|')
        }
    }

    /** Rows covering [start] until [start] + [length], clamped to the data. */
    fun rows(bytes: ByteArray, start: Int = 0, length: Int = bytes.size): List<String> {
        val first = start.coerceAtLeast(0)
        if (first >= bytes.size || length <= 0) return emptyList()
        val from = (first / BYTES_PER_ROW) * BYTES_PER_ROW
        val to = (first.toLong() + length).coerceAtMost(bytes.size.toLong()).toInt()
        return (from until to step BYTES_PER_ROW).map { row(bytes, it) }
    }

    private val HEX = "0123456789ABCDEF".toCharArray()
}
