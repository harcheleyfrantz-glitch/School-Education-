package com.rodwave.engine.fs

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

/** File-system failure with a user-facing message (permission denied, missing file, ...). */
class FsException(message: String, cause: Throwable? = null) : Exception(message, cause)

/**
 * A file or directory in a tree the user granted access to.
 *
 * On Android this is backed by the Storage Access Framework; in tests and on desktop by
 * [LocalFile]. Implementations throw [FsException] when the platform denies an operation.
 */
interface VirtualFile {
    val name: String
    /** Path relative to the tree root, using '/' separators ("" for the root). */
    val path: String
    val isDirectory: Boolean
    val isFile: Boolean get() = !isDirectory
    val length: Long
    val lastModified: Long
    val canWrite: Boolean
    val exists: Boolean

    fun list(): List<VirtualFile>
    fun child(name: String): VirtualFile?
    fun openInput(): InputStream
    fun openOutput(): OutputStream
    fun createFile(name: String): VirtualFile
    fun createDirectory(name: String): VirtualFile
    fun delete(): Boolean
    fun renameTo(newName: String): VirtualFile
}

/** Upper bound for files read fully into memory. */
const val MAX_IN_MEMORY_BYTES: Long = 64L * 1024 * 1024

fun VirtualFile.readBytes(limit: Long = MAX_IN_MEMORY_BYTES): ByteArray {
    if (isDirectory) throw FsException("$path is a directory")
    if (length > limit) throw FsException("$path is larger than ${limit / (1024 * 1024)} MB")
    return openInput().use { input ->
        val out = ByteArrayOutputStream(length.coerceIn(0, Int.MAX_VALUE.toLong()).toInt().coerceAtMost(1 shl 20))
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            total += n
            if (total > limit) throw FsException("$path is larger than ${limit / (1024 * 1024)} MB")
            out.write(buffer, 0, n)
        }
        out.toByteArray()
    }
}

fun VirtualFile.readText(limit: Long = MAX_IN_MEMORY_BYTES): String = readBytes(limit).toString(Charsets.UTF_8)

fun VirtualFile.writeBytes(data: ByteArray) {
    openOutput().use { it.write(data) }
}

fun VirtualFile.writeText(text: String) = writeBytes(text.toByteArray(Charsets.UTF_8))

/** Resolves a relative '/'-separated path below this directory. */
fun VirtualFile.resolve(relative: String): VirtualFile? {
    var current: VirtualFile = this
    for (segment in relative.split('/').filter { it.isNotEmpty() && it != "." }) {
        if (segment == "..") return null
        current = current.child(segment) ?: return null
    }
    return current
}

/** Returns the directory at [relative], creating missing directories. */
fun VirtualFile.ensureDirectory(relative: String): VirtualFile {
    var current: VirtualFile = this
    for (segment in relative.split('/').filter { it.isNotEmpty() && it != "." }) {
        require(segment != "..") { "Path must not contain '..'" }
        val existing = current.child(segment)
        current = when {
            existing == null -> current.createDirectory(segment)
            existing.isDirectory -> existing
            else -> throw FsException("${existing.path} exists and is not a directory")
        }
    }
    return current
}

/** Creates or overwrites the file at [relative] below this directory. */
fun VirtualFile.writeFile(relative: String, data: ByteArray): VirtualFile {
    val parentPath = relative.substringBeforeLast('/', "")
    val fileName = relative.substringAfterLast('/')
    val dir = if (parentPath.isEmpty()) this else ensureDirectory(parentPath)
    val file = dir.child(fileName)?.also { if (it.isDirectory) throw FsException("${it.path} is a directory") }
        ?: dir.createFile(fileName)
    file.writeBytes(data)
    return file
}

/** Depth-first walk; stops descending after [maxDepth] levels and after [maxEntries] entries. */
fun VirtualFile.walk(maxDepth: Int = 8, maxEntries: Int = 20_000): Sequence<VirtualFile> = sequence {
    var count = 0
    val stack = ArrayDeque<Pair<VirtualFile, Int>>()
    stack.addLast(this@walk to 0)
    while (stack.isNotEmpty()) {
        val (dir, depth) = stack.removeLast()
        val children = try {
            dir.list()
        } catch (e: FsException) {
            continue
        }
        for (child in children.sortedBy { it.name.lowercase() }) {
            if (++count > maxEntries) return@sequence
            yield(child)
            if (child.isDirectory && depth + 1 < maxDepth) stack.addLast(child to depth + 1)
        }
    }
}

fun ByteArray.sha256(): String =
    MessageDigest.getInstance("SHA-256").digest(this).joinToString("") { "%02x".format(it) }

/** [VirtualFile] backed by java.io; used on desktop and in tests. */
class LocalFile(private val root: File, private val file: File = root) : VirtualFile {
    init {
        require(file.canonicalPath.startsWith(root.canonicalPath)) { "File escapes the root" }
    }

    override val name: String get() = file.name
    override val path: String get() = file.relativeTo(root).invariantSeparatorsPath
    override val isDirectory: Boolean get() = file.isDirectory
    override val length: Long get() = if (file.isFile) file.length() else 0
    override val lastModified: Long get() = file.lastModified()
    override val canWrite: Boolean get() = file.canWrite()
    override val exists: Boolean get() = file.exists()

    override fun list(): List<VirtualFile> {
        if (!file.isDirectory) throw FsException("$path is not a directory")
        return (file.listFiles() ?: throw FsException("Cannot list $path")).map { LocalFile(root, it) }
    }

    override fun child(name: String): VirtualFile? {
        checkName(name)
        val f = File(file, name)
        return if (f.exists()) LocalFile(root, f) else null
    }

    override fun openInput(): InputStream = try {
        file.inputStream()
    } catch (e: Exception) {
        throw FsException("Cannot read $path: ${e.message}", e)
    }

    override fun openOutput(): OutputStream = try {
        file.outputStream()
    } catch (e: Exception) {
        throw FsException("Cannot write $path: ${e.message}", e)
    }

    override fun createFile(name: String): VirtualFile {
        checkName(name)
        val f = File(file, name)
        if (f.exists()) throw FsException("${f.name} already exists")
        if (!f.createNewFile()) throw FsException("Cannot create $name in $path")
        return LocalFile(root, f)
    }

    override fun createDirectory(name: String): VirtualFile {
        checkName(name)
        val f = File(file, name)
        if (!f.isDirectory && !f.mkdir()) throw FsException("Cannot create directory $name in $path")
        return LocalFile(root, f)
    }

    override fun delete(): Boolean = if (file.isDirectory) file.deleteRecursively() else file.delete()

    override fun renameTo(newName: String): VirtualFile {
        checkName(newName)
        val target = File(file.parentFile, newName)
        if (target.exists()) throw FsException("$newName already exists")
        if (!file.renameTo(target)) throw FsException("Cannot rename $path to $newName")
        return LocalFile(root, target)
    }

    private fun checkName(name: String) {
        if (name.isEmpty() || name == "." || name == ".." || '/' in name || '\\' in name || '\u0000' in name) {
            throw FsException("Invalid file name '$name'")
        }
    }

    override fun toString(): String = "LocalFile($path)"
}
