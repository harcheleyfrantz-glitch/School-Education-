package com.rodwave.engine.scm

/** Thrown internally when bytecode cannot be decoded; [offset] points at the problem. */
class DecodeException(val offset: Int, message: String) : Exception(message)

/** Little-endian reader over `data[start until limit]` that never reads past [limit]. */
class ByteCursor(private val data: ByteArray, start: Int, private val limit: Int = data.size) {
    init {
        require(start in 0..limit && limit <= data.size) { "Invalid cursor range $start..$limit (size ${data.size})" }
    }

    var position: Int = start
        private set

    val remaining: Int get() = limit - position

    private fun need(count: Int, what: String) {
        if (count < 0 || limit - position < count) {
            throw DecodeException(position, "Unexpected end of data while reading $what (need $count byte(s), ${limit - position} left)")
        }
    }

    fun u8(what: String = "byte"): Int {
        need(1, what)
        return data[position++].toInt() and 0xFF
    }

    fun s8(what: String = "8-bit integer"): Int {
        need(1, what)
        return data[position++].toInt()
    }

    fun u16(what: String = "16-bit value"): Int {
        need(2, what)
        val v = (data[position].toInt() and 0xFF) or ((data[position + 1].toInt() and 0xFF) shl 8)
        position += 2
        return v
    }

    fun s16(what: String = "16-bit integer"): Int = u16(what).toShort().toInt()

    fun s32(what: String = "32-bit integer"): Int {
        need(4, what)
        val v = (data[position].toInt() and 0xFF) or
            ((data[position + 1].toInt() and 0xFF) shl 8) or
            ((data[position + 2].toInt() and 0xFF) shl 16) or
            ((data[position + 3].toInt() and 0xFF) shl 24)
        position += 4
        return v
    }

    fun f32(what: String = "float"): Float = Float.fromBits(s32(what))

    fun bytes(count: Int, what: String = "bytes"): ByteArray {
        need(count, what)
        val out = data.copyOfRange(position, position + count)
        position += count
        return out
    }

    fun seek(newPosition: Int) {
        require(newPosition in 0..limit) { "Seek outside range: $newPosition" }
        position = newPosition
    }
}

/** Reads little-endian values from a byte array without a cursor. Returns null when out of range. */
object LittleEndian {
    fun u16(data: ByteArray, at: Int): Int? =
        if (at < 0 || at + 2 > data.size) null else (data[at].toInt() and 0xFF) or ((data[at + 1].toInt() and 0xFF) shl 8)

    fun s32(data: ByteArray, at: Int): Int? =
        if (at < 0 || at + 4 > data.size) null else (data[at].toInt() and 0xFF) or
            ((data[at + 1].toInt() and 0xFF) shl 8) or
            ((data[at + 2].toInt() and 0xFF) shl 16) or
            ((data[at + 3].toInt() and 0xFF) shl 24)
}
