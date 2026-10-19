package com.rodwave.engine.archive

import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class SafeZipTest {
    private fun zip(vararg entries: Pair<String, ByteArray>): ByteArray {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { z ->
            for ((name, data) in entries) {
                z.putNextEntry(ZipEntry(name))
                z.write(data)
                z.closeEntry()
            }
        }
        return out.toByteArray()
    }

    @Test
    fun rejectsTraversalAndAbsolutePaths() {
        val bytes = zip(
            "cleo/ok.csa" to byteArrayOf(1, 2, 3),
            "../evil.txt" to byteArrayOf(9),
            "cleo/../../evil2.txt" to byteArrayOf(9),
            "/etc/passwd" to byteArrayOf(9),
            "C:/Windows/x.dll" to byteArrayOf(9),
            "dir\\..\\..\\evil3" to byteArrayOf(9),
            "__MACOSX/cleo/._ok.csa" to byteArrayOf(0),
            "CLEO/OK.CSA" to byteArrayOf(4),
            "./mods/./a.so" to byteArrayOf(5),
        )
        val contents = SafeZip.read(bytes.inputStream())
        assertEquals(listOf("cleo/ok.csa", "mods/a.so"), contents.files.map { it.path })
        val reasons = contents.rejected.associate { it.path to it.reason }
        assertTrue(reasons.getValue("../evil.txt").contains("traversal"))
        assertTrue(reasons.getValue("cleo/../../evil2.txt").contains("traversal"))
        assertTrue(reasons.getValue("/etc/passwd").contains("absolute"))
        assertTrue(reasons.getValue("C:/Windows/x.dll").contains("drive"))
        assertTrue(reasons.getValue("dir\\..\\..\\evil3").contains("traversal"))
        assertTrue(reasons.getValue("CLEO/OK.CSA").contains("duplicate"))
        assertEquals(listOf("__MACOSX/cleo/._ok.csa"), contents.ignored)
    }

    @Test
    fun stopsOversizedEntries() {
        val big = zip("big.bin" to ByteArray(50_000))
        assertFailsWith<ArchiveException> { SafeZip.read(big.inputStream(), SafeZip.Limits(maxEntryBytes = 10_000)) }
        assertFailsWith<ArchiveException> { SafeZip.read(big.inputStream(), SafeZip.Limits(maxTotalBytes = 10_000)) }
        val many = zip(*(1..20).map { "f$it.txt" to byteArrayOf(1) }.toTypedArray())
        assertFailsWith<ArchiveException> { SafeZip.read(many.inputStream(), SafeZip.Limits(maxEntries = 5)) }
    }

    @Test
    fun rejectsNonZipData() {
        assertFailsWith<ArchiveException> { SafeZip.read("definitely not a zip".toByteArray().inputStream()) }
    }

    @Test
    fun writesAndReadsBack() {
        val out = ByteArrayOutputStream()
        SafeZip.write(out, listOf(ArchiveFile("projects/a/main.txt", "wait 0".toByteArray())))
        val back = SafeZip.read(out.toByteArray().inputStream())
        assertEquals("wait 0", back.files.single().data.toString(Charsets.UTF_8))
        assertFailsWith<IllegalArgumentException> { SafeZip.write(ByteArrayOutputStream(), listOf(ArchiveFile("../x", byteArrayOf()))) }
    }
}
