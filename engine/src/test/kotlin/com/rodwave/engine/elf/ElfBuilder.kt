package com.rodwave.engine.elf

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Builds minimal but well-formed ELF shared objects for tests (no code, just metadata). */
object ElfBuilder {
    fun build(
        is64: Boolean,
        machine: Int,
        exports: List<String> = emptyList(),
        needed: List<String> = emptyList(),
        rodata: List<String> = emptyList(),
        type: Int = ElfFile.ET_DYN,
    ): ByteArray {
        // .dynstr
        val dynstr = ByteArrayOutputStream().apply { write(0) }
        fun addStr(s: String): Int {
            val at = dynstr.size()
            dynstr.write(s.toByteArray())
            dynstr.write(0)
            return at
        }
        val exportOffsets = exports.map(::addStr)
        val neededOffsets = needed.map(::addStr)
        val dynstrBytes = dynstr.toByteArray()

        // .dynsym
        val symSize = if (is64) 24 else 16
        val dynsym = ByteBuffer.allocate(symSize * (exports.size + 1)).order(ByteOrder.LITTLE_ENDIAN)
        dynsym.position(symSize) // null symbol
        for (off in exportOffsets) {
            val info = (ElfFile.STB_GLOBAL shl 4) or ElfFile.STT_FUNC
            if (is64) {
                dynsym.putInt(off); dynsym.put(info.toByte()); dynsym.put(0); dynsym.putShort(1); dynsym.putLong(0); dynsym.putLong(0)
            } else {
                dynsym.putInt(off); dynsym.putInt(0); dynsym.putInt(0); dynsym.put(info.toByte()); dynsym.put(0); dynsym.putShort(1)
            }
        }

        // .dynamic
        val dynEnt = if (is64) 16 else 8
        val dynamic = ByteBuffer.allocate(dynEnt * (needed.size + 1)).order(ByteOrder.LITTLE_ENDIAN)
        for (off in neededOffsets) {
            if (is64) { dynamic.putLong(ElfFile.DT_NEEDED); dynamic.putLong(off.toLong()) } else { dynamic.putInt(1); dynamic.putInt(off) }
        }

        // .rodata
        val ro = ByteArrayOutputStream()
        rodata.forEach { ro.write(it.toByteArray()); ro.write(0) }
        val roBytes = ro.toByteArray()

        // .shstrtab
        val names = listOf("", ".dynstr", ".dynsym", ".dynamic", ".rodata", ".shstrtab")
        val shstr = ByteArrayOutputStream()
        val nameOffsets = names.map { n -> shstr.size().also { shstr.write(n.toByteArray()); shstr.write(0) } }
        val shstrBytes = shstr.toByteArray()

        val headerSize = if (is64) 64 else 52
        val sections = listOf(dynstrBytes, dynsym.array(), dynamic.array(), roBytes, shstrBytes)
        val offsets = ArrayList<Int>()
        var cursor = headerSize
        for (s in sections) {
            offsets += cursor
            cursor += s.size
        }
        val shoff = (cursor + 7) / 8 * 8
        val shentsize = if (is64) 64 else 40
        val total = shoff + shentsize * names.size
        val out = ByteBuffer.allocate(total).order(ByteOrder.LITTLE_ENDIAN)
        // Header
        out.put(byteArrayOf(0x7F, 'E'.code.toByte(), 'L'.code.toByte(), 'F'.code.toByte(), if (is64) 2 else 1, 1, 1, 0))
        out.position(16)
        out.putShort(type.toShort())
        out.putShort(machine.toShort())
        out.putInt(1)
        if (is64) {
            out.putLong(0); out.putLong(0); out.putLong(shoff.toLong()); out.putInt(0)
            out.putShort(64); out.putShort(56); out.putShort(0); out.putShort(shentsize.toShort()); out.putShort(names.size.toShort()); out.putShort(5)
        } else {
            out.putInt(0); out.putInt(0); out.putInt(shoff); out.putInt(0)
            out.putShort(52); out.putShort(32); out.putShort(0); out.putShort(shentsize.toShort()); out.putShort(names.size.toShort()); out.putShort(5)
        }
        // Section bodies
        sections.forEachIndexed { i, s -> out.position(offsets[i]); out.put(s) }
        // Section headers: null, dynstr, dynsym, dynamic, rodata, shstrtab
        data class Sh(val name: Int, val type: Int, val off: Int, val size: Int, val link: Int, val ent: Int)
        val headers = listOf(
            Sh(0, 0, 0, 0, 0, 0),
            Sh(nameOffsets[1], ElfFile.SHT_STRTAB, offsets[0], dynstrBytes.size, 0, 0),
            Sh(nameOffsets[2], ElfFile.SHT_DYNSYM, offsets[1], dynsym.array().size, 1, symSize),
            Sh(nameOffsets[3], ElfFile.SHT_DYNAMIC, offsets[2], dynamic.array().size, 1, dynEnt),
            Sh(nameOffsets[4], 1, offsets[3], roBytes.size, 0, 0),
            Sh(nameOffsets[5], ElfFile.SHT_STRTAB, offsets[4], shstrBytes.size, 0, 0),
        )
        headers.forEachIndexed { i, h ->
            out.position(shoff + i * shentsize)
            if (is64) {
                out.putInt(h.name); out.putInt(h.type); out.putLong(0); out.putLong(0); out.putLong(h.off.toLong()); out.putLong(h.size.toLong())
                out.putInt(h.link); out.putInt(0); out.putLong(1); out.putLong(h.ent.toLong())
            } else {
                out.putInt(h.name); out.putInt(h.type); out.putInt(0); out.putInt(0); out.putInt(h.off); out.putInt(h.size)
                out.putInt(h.link); out.putInt(0); out.putInt(1); out.putInt(h.ent)
            }
        }
        return out.array()
    }

    fun amlMod(abi64: Boolean, guid: String, extraStrings: List<String> = emptyList(), withDeps: Boolean = false): ByteArray = build(
        is64 = abi64,
        machine = if (abi64) ElfFile.EM_AARCH64 else ElfFile.EM_ARM,
        exports = listOfNotNull("__GetModInfo", "OnModLoad", if (withDeps) "__GetDepsList" else null),
        needed = listOf("liblog.so", "libc.so"),
        rodata = listOf(guid, "My Mod", "1.0", "Author") + extraStrings,
    )
}
