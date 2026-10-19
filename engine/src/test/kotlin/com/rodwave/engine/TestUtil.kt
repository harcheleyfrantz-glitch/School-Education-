package com.rodwave.engine

fun hexBytes(text: String): ByteArray {
    val digits = text.filter { !it.isWhitespace() }
    require(digits.length % 2 == 0) { "odd number of hex digits" }
    return ByteArray(digits.length / 2) { digits.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
}

fun ByteArray.toHex(): String = joinToString(" ") { (it.toInt() and 0xFF).toString(16).uppercase().padStart(2, '0') }
