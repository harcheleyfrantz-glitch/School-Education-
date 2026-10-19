package com.rodwave.engine.elf

import com.rodwave.engine.scm.Abi

class ElfException(message: String) : Exception(message)

data class ElfSymbol(val name: String, val isFunction: Boolean, val isGlobal: Boolean, val isDefined: Boolean)

data class ElfSection(val name: String, val type: Int, val offset: Long, val size: Long, val link: Int, val entrySize: Long)

/**
 * Minimal, bounds-checked reader for little-endian ELF shared objects (Android native libraries).
 *
 * Only metadata is read: header, section table, dynamic symbols, DT_NEEDED entries and printable
 * strings from `.rodata`. Nothing is executed or loaded.
 */
class ElfFile private constructor(private val data: ByteArray) {
    val is64Bit: Boolean
    val type: Int
    val machine: Int
    val sections: List<ElfSection>
    val dynamicSymbols: List<ElfSymbol>
    val neededLibraries: List<String>
    val soName: String?

    init {
        if (data.size < 52 || data[0] != 0x7F.toByte() || data[1] != 'E'.code.toByte() || data[2] != 'L'.code.toByte() || data[3] != 'F'.code.toByte()) {
            throw ElfException("Not an ELF file (missing \\x7FELF signature)")
        }
        is64Bit = when (data[4].toInt()) {
            1 -> false
            2 -> true
            else -> throw ElfException("Unknown ELF class ${data[4]}")
        }
        if (data[5].toInt() != 1) throw ElfException("Only little-endian ELF files are supported")
        if (is64Bit && data.size < 64) throw ElfException("Truncated ELF header")
        type = u16(16)
        machine = u16(18)
        val shoff = if (is64Bit) u64(40) else u32(32)
        val shentsize = u16(if (is64Bit) 58 else 46)
        val shnum = u16(if (is64Bit) 60 else 48)
        val shstrndx = u16(if (is64Bit) 62 else 50)
        sections = readSections(shoff, shentsize, shnum, shstrndx)
        val dynsym = sections.firstOrNull { it.type == SHT_DYNSYM }
        dynamicSymbols = if (dynsym != null) readSymbols(dynsym) else emptyList()
        val dynamic = sections.firstOrNull { it.type == SHT_DYNAMIC }
        val (needed, so) = if (dynamic != null) readDynamic(dynamic) else emptyList<String>() to null
        neededLibraries = needed
        soName = so
    }

    val abi: Abi?
        get() = when (machine) {
            EM_ARM -> Abi.ARMEABI_V7A
            EM_AARCH64 -> Abi.ARM64_V8A
            EM_386 -> Abi.X86
            EM_X86_64 -> Abi.X86_64
            else -> null
        }

    val isSharedObject: Boolean get() = type == ET_DYN

    val exportedSymbols: List<String>
        get() = dynamicSymbols.filter { it.isGlobal && it.isDefined && it.name.isNotEmpty() }.map { it.name }

    fun exports(symbol: String): Boolean = dynamicSymbols.any { it.name == symbol && it.isGlobal && it.isDefined }

    /** Printable ASCII strings (length >= [minLength]) from read-only data sections. */
    fun readOnlyStrings(minLength: Int = 4, limit: Int = 20_000): List<String> {
        val out = ArrayList<String>()
        for (section in sections.filter { it.name == ".rodata" || it.name.startsWith(".rodata.") || it.name == ".data.rel.ro" }) {
            val start = section.offset
            val end = (section.offset + section.size).coerceAtMost(data.size.toLong())
            if (start < 0 || start >= end) continue
            var runStart = -1
            var i = start.toInt()
            while (i < end.toInt()) {
                val c = data[i].toInt() and 0xFF
                val printable = c in 0x20..0x7E
                if (printable && runStart < 0) runStart = i
                if (!printable && runStart >= 0) {
                    if (i - runStart >= minLength) {
                        out += String(data, runStart, i - runStart, Charsets.ISO_8859_1)
                        if (out.size >= limit) return out
                    }
                    runStart = -1
                }
                i++
            }
        }
        return out
    }

    // ------------------------------------------------------------------ parsing

    private fun readSections(shoff: Long, entSize: Int, count: Int, strIndex: Int): List<ElfSection> {
        if (shoff == 0L || count == 0) return emptyList()
        val expected = if (is64Bit) 64 else 40
        if (entSize < expected) throw ElfException("Unexpected section header size $entSize")
        if (count > MAX_SECTIONS) throw ElfException("Too many sections ($count)")
        if (shoff < 0 || shoff + entSize.toLong() * count > data.size) throw ElfException("Section table lies outside the file")
        val raw = (0 until count).map { i ->
            val base = (shoff + i.toLong() * entSize).toInt()
            if (is64Bit) {
                RawSection(u32i(base), u32i(base + 4), u64(base + 24), u64(base + 32), u32i(base + 40), u64(base + 56))
            } else {
                RawSection(u32i(base), u32i(base + 4), u32(base + 16), u32(base + 20), u32i(base + 24), u32(base + 36))
            }
        }
        val names = raw.getOrNull(strIndex)
        return raw.map { s ->
            ElfSection(names?.let { cString(it.offset, it.size, s.nameOffset.toLong()) } ?: "", s.type, s.offset, s.size, s.link, s.entSize)
        }
    }

    private class RawSection(val nameOffset: Int, val type: Int, val offset: Long, val size: Long, val link: Int, val entSize: Long)

    private fun readSymbols(section: ElfSection): List<ElfSymbol> {
        val strtab = sections.getOrNull(section.link) ?: return emptyList()
        val entSize = if (is64Bit) 24 else 16
        if (section.offset < 0 || section.offset + section.size > data.size) throw ElfException("Symbol table lies outside the file")
        val count = (section.size / entSize).toInt()
        if (count > MAX_SYMBOLS) throw ElfException("Too many symbols ($count)")
        return (0 until count).map { i ->
            val base = (section.offset + i.toLong() * entSize).toInt()
            val nameOff = u32(base)
            val info: Int
            val shndx: Int
            if (is64Bit) {
                info = data[base + 4].toInt() and 0xFF
                shndx = u16(base + 6)
            } else {
                info = data[base + 12].toInt() and 0xFF
                shndx = u16(base + 14)
            }
            val bind = info shr 4
            val type = info and 0xF
            ElfSymbol(
                name = cString(strtab.offset, strtab.size, nameOff) ?: "",
                isFunction = type == STT_FUNC,
                isGlobal = bind == STB_GLOBAL || bind == STB_WEAK,
                isDefined = shndx != SHN_UNDEF,
            )
        }
    }

    private fun readDynamic(section: ElfSection): Pair<List<String>, String?> {
        val strtab = sections.getOrNull(section.link) ?: return emptyList<String>() to null
        val entSize = if (is64Bit) 16 else 8
        if (section.offset < 0 || section.offset + section.size > data.size) throw ElfException("Dynamic section lies outside the file")
        val needed = ArrayList<String>()
        var soname: String? = null
        val count = (section.size / entSize).toInt().coerceAtMost(MAX_SYMBOLS)
        for (i in 0 until count) {
            val base = (section.offset + i.toLong() * entSize).toInt()
            val tag = if (is64Bit) u64(base) else u32(base)
            val value = if (is64Bit) u64(base + 8) else u32(base + 4)
            when (tag) {
                DT_NULL -> break
                DT_NEEDED -> cString(strtab.offset, strtab.size, value)?.let { needed += it }
                DT_SONAME -> soname = cString(strtab.offset, strtab.size, value)
            }
        }
        return needed to soname
    }

    private fun cString(tableOffset: Long, tableSize: Long, index: Long): String? {
        if (index < 0 || index >= tableSize) return null
        val start = tableOffset + index
        val end = (tableOffset + tableSize).coerceAtMost(data.size.toLong())
        if (start < 0 || start >= end) return null
        var i = start.toInt()
        while (i < end && data[i].toInt() != 0) i++
        if (i - start > 4096) return null
        return String(data, start.toInt(), i - start.toInt(), Charsets.UTF_8)
    }

    private fun check(at: Int, size: Int) {
        if (at < 0 || at + size > data.size) throw ElfException("Read outside the file at $at")
    }

    private fun u16(at: Int): Int {
        check(at, 2)
        return (data[at].toInt() and 0xFF) or ((data[at + 1].toInt() and 0xFF) shl 8)
    }

    private fun u32i(at: Int): Int {
        check(at, 4)
        return (data[at].toInt() and 0xFF) or ((data[at + 1].toInt() and 0xFF) shl 8) or
            ((data[at + 2].toInt() and 0xFF) shl 16) or ((data[at + 3].toInt() and 0xFF) shl 24)
    }

    private fun u32(at: Int): Long = u32i(at).toLong() and 0xFFFF_FFFFL

    private fun u64(at: Int): Long {
        check(at, 8)
        val lo = u32(at)
        val hi = u32(at + 4)
        if (hi > 0x7FFF_FFFFL) throw ElfException("64-bit value out of range at $at")
        return (hi shl 32) or lo
    }

    companion object {
        const val EM_386 = 3
        const val EM_ARM = 40
        const val EM_X86_64 = 62
        const val EM_AARCH64 = 183
        const val ET_DYN = 3
        const val SHT_STRTAB = 3
        const val SHT_DYNAMIC = 6
        const val SHT_DYNSYM = 11
        const val STB_GLOBAL = 1
        const val STB_WEAK = 2
        const val STT_FUNC = 2
        const val SHN_UNDEF = 0
        const val DT_NULL = 0L
        const val DT_NEEDED = 1L
        const val DT_SONAME = 14L
        private const val MAX_SECTIONS = 4096
        private const val MAX_SYMBOLS = 500_000

        fun parse(data: ByteArray): ElfFile = ElfFile(data)

        fun isElf(data: ByteArray): Boolean =
            data.size >= 4 && data[0] == 0x7F.toByte() && data[1] == 'E'.code.toByte() && data[2] == 'L'.code.toByte() && data[3] == 'F'.code.toByte()
    }
}
