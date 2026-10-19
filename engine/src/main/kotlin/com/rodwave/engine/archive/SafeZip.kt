package com.rodwave.engine.archive

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipException
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

class ArchiveException(message: String, cause: Throwable? = null) : Exception(message, cause)

data class ArchiveFile(val path: String, val data: ByteArray) {
    val name: String get() = path.substringAfterLast('/')
    val size: Int get() = data.size
}

data class RejectedEntry(val path: String, val reason: String)

data class ArchiveContents(val files: List<ArchiveFile>, val rejected: List<RejectedEntry>, val ignored: List<String>)

/**
 * Reads ZIP archives defensively.
 *
 * Entries with absolute paths, drive letters, `..` segments, control characters, duplicate names or
 * oversized content are rejected before any data is written anywhere. Total and per-entry sizes are
 * capped while decompressing, which stops zip bombs regardless of the sizes the archive claims.
 */
object SafeZip {
    data class Limits(
        val maxEntries: Int = 5_000,
        val maxEntryBytes: Long = 128L * 1024 * 1024,
        val maxTotalBytes: Long = 512L * 1024 * 1024,
        val maxPathLength: Int = 512,
    )

    private val IGNORED_PREFIXES = listOf("__MACOSX/")
    private val IGNORED_NAMES = setOf(".DS_Store", "Thumbs.db", "desktop.ini")

    /** Returns a safe relative path, or null with the reason when the name must be rejected. */
    fun normalize(rawName: String, maxPathLength: Int = 512): Pair<String?, String?> {
        if (rawName.isEmpty()) return null to "empty name"
        if (rawName.any { it.code < 0x20 || it == '\u007F' }) return null to "control characters in name"
        val name = rawName.replace('\\', '/')
        if (name.startsWith("/")) return null to "absolute path"
        if (Regex("^[A-Za-z]:").containsMatchIn(name)) return null to "drive letter in path"
        val segments = name.split('/').filter { it.isNotEmpty() && it != "." }
        if (segments.isEmpty()) return null to "empty path"
        if (segments.any { it == ".." }) return null to "path traversal ('..')"
        if (segments.any { it.length > 255 }) return null to "path segment too long"
        val joined = segments.joinToString("/")
        if (joined.length > maxPathLength) return null to "path too long"
        return joined to null
    }

    fun read(input: InputStream, limits: Limits = Limits()): ArchiveContents {
        val files = ArrayList<ArchiveFile>()
        val rejected = ArrayList<RejectedEntry>()
        val ignored = ArrayList<String>()
        val seen = HashSet<String>()
        var total = 0L
        var entries = 0
        try {
            ZipInputStream(input).use { zip ->
                while (true) {
                    val entry: ZipEntry = zip.nextEntry ?: break
                    if (++entries > limits.maxEntries) throw ArchiveException("The archive has more than ${limits.maxEntries} entries")
                    val raw = entry.name
                    val (path, reason) = normalize(raw, limits.maxPathLength)
                    if (path == null) {
                        rejected += RejectedEntry(raw, reason!!)
                        continue
                    }
                    if (IGNORED_PREFIXES.any { path.startsWith(it) } || path.substringAfterLast('/') in IGNORED_NAMES) {
                        ignored += path
                        continue
                    }
                    if (entry.isDirectory) continue
                    if (!seen.add(path.lowercase())) {
                        rejected += RejectedEntry(raw, "duplicate entry")
                        continue
                    }
                    val buffer = ByteArrayOutputStream()
                    val chunk = ByteArray(64 * 1024)
                    var entryBytes = 0L
                    while (true) {
                        val n = zip.read(chunk)
                        if (n < 0) break
                        entryBytes += n
                        total += n
                        if (entryBytes > limits.maxEntryBytes) throw ArchiveException("'$path' expands beyond ${limits.maxEntryBytes / (1024 * 1024)} MB")
                        if (total > limits.maxTotalBytes) throw ArchiveException("The archive expands beyond ${limits.maxTotalBytes / (1024 * 1024)} MB")
                        buffer.write(chunk, 0, n)
                    }
                    files += ArchiveFile(path, buffer.toByteArray())
                }
            }
        } catch (e: ZipException) {
            throw ArchiveException("Not a valid ZIP archive: ${e.message}", e)
        }
        if (entries == 0) throw ArchiveException("The archive is empty or not a ZIP file")
        return ArchiveContents(files, rejected, ignored)
    }

    fun write(output: OutputStream, files: List<ArchiveFile>) {
        ZipOutputStream(output).use { zip ->
            for (f in files) {
                val (path, reason) = normalize(f.path)
                requireNotNull(path) { "Refusing to write unsafe entry '${f.path}': $reason" }
                zip.putNextEntry(ZipEntry(path))
                zip.write(f.data)
                zip.closeEntry()
            }
        }
    }

    fun isZip(bytes: ByteArray): Boolean =
        bytes.size >= 4 && bytes[0] == 'P'.code.toByte() && bytes[1] == 'K'.code.toByte() && bytes[2].toInt() == 3 && bytes[3].toInt() == 4
}
