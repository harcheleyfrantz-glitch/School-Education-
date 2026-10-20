package com.rodwave.studio.android

import android.content.ContentResolver
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import com.rodwave.engine.fs.FsException
import com.rodwave.engine.fs.VirtualFile
import java.io.InputStream
import java.io.OutputStream

/**
 * [VirtualFile] over a Storage Access Framework tree the user granted with the system folder picker.
 *
 * Metadata comes from a single DocumentsContract query per directory listing; DocumentFile would
 * issue one query per attribute per file, which makes scanning large folders very slow. Instances
 * are snapshots: size and dates are those seen when the file was listed or created.
 */
class SafFile private constructor(
    private val resolver: ContentResolver,
    private val treeUri: Uri,
    private val documentId: String,
    override val path: String,
    private val meta: Meta,
) : VirtualFile {

    private class Meta(val name: String, val mimeType: String, val size: Long, val modified: Long, val flags: Int)

    val uri: Uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)

    override val name: String get() = meta.name
    override val isDirectory: Boolean get() = meta.mimeType == Document.MIME_TYPE_DIR
    override val length: Long get() = if (isDirectory) 0 else meta.size
    override val lastModified: Long get() = meta.modified
    override val canWrite: Boolean
        get() = meta.flags and (if (isDirectory) Document.FLAG_DIR_SUPPORTS_CREATE else Document.FLAG_SUPPORTS_WRITE) != 0
    override val exists: Boolean get() = queryMeta(resolver, uri) != null

    private val display: String get() = path.ifEmpty { "the chosen folder" }

    override fun list(): List<VirtualFile> {
        if (!isDirectory) throw FsException("$display is not a folder")
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
        val cursor = try {
            resolver.query(children, PROJECTION, null, null, null)
        } catch (e: Exception) {
            throw FsException("Cannot list $display: ${e.message}", e)
        } ?: throw FsException("Cannot list $display")
        return cursor.use { c ->
            val out = ArrayList<VirtualFile>(c.count.coerceAtLeast(0))
            while (c.moveToNext()) {
                val (id, m) = c.readMeta() ?: continue
                // Never expose names that could be mistaken for path syntax.
                if (!isSafeName(m.name)) continue
                out += SafFile(resolver, treeUri, id, join(path, m.name), m)
            }
            out
        }
    }

    override fun child(name: String): VirtualFile? {
        checkName(name)
        val all = list()
        // Shared storage is case-insensitive; prefer the exact spelling when both exist.
        return all.firstOrNull { it.name == name } ?: all.firstOrNull { it.name.equals(name, ignoreCase = true) }
    }

    override fun openInput(): InputStream = try {
        resolver.openInputStream(uri) ?: throw FsException("Cannot read $display")
    } catch (e: FsException) {
        throw e
    } catch (e: Exception) {
        throw FsException("Cannot read $display: ${e.message}", e)
    }

    /** Truncates the file before writing ("wt"), so no stale bytes remain after a shorter write. */
    override fun openOutput(): OutputStream = try {
        resolver.openOutputStream(uri, "wt") ?: throw FsException("Cannot write $display")
    } catch (e: FsException) {
        throw e
    } catch (e: Exception) {
        throw FsException("Cannot write $display: ${e.message}", e)
    }

    override fun createFile(name: String): VirtualFile {
        checkName(name)
        if (child(name) != null) throw FsException("$name already exists")
        return create(MIME_BINARY, name)
    }

    override fun createDirectory(name: String): VirtualFile {
        checkName(name)
        child(name)?.let { existing ->
            if (existing.isDirectory) return existing
            throw FsException("$name exists and is not a folder")
        }
        return create(Document.MIME_TYPE_DIR, name)
    }

    override fun delete(): Boolean = try {
        DocumentsContract.deleteDocument(resolver, uri)
    } catch (e: Exception) {
        false
    }

    override fun renameTo(newName: String): VirtualFile {
        checkName(newName)
        if (newName == name) return this
        val renamed = try {
            DocumentsContract.renameDocument(resolver, uri, newName)
        } catch (e: Exception) {
            throw FsException("Cannot rename $display to $newName: ${e.message}", e)
        } ?: throw FsException("Android did not rename $display to $newName (the name may be taken)")
        val file = fromDocumentUri(renamed, parentPath(path))
        if (file.name != newName) throw FsException("Android renamed $display to ${file.name} instead of $newName")
        return file
    }

    private fun create(mimeType: String, name: String): SafFile {
        val created = try {
            DocumentsContract.createDocument(resolver, uri, mimeType, name)
        } catch (e: Exception) {
            throw FsException("Cannot create $name in $display: ${e.message}", e)
        } ?: throw FsException("Android refused to create $name in $display")
        val file = fromDocumentUri(created, path)
        if (file.name != name) {
            // Providers may add "(1)" or an extension; never keep a file under a name nobody asked for.
            runCatching { DocumentsContract.deleteDocument(resolver, created) }
            throw FsException("Android stored '$name' as '${file.name}', so it was removed again")
        }
        return file
    }

    private fun fromDocumentUri(documentUri: Uri, parent: String): SafFile {
        val id = DocumentsContract.getDocumentId(documentUri)
        val meta = queryMeta(resolver, DocumentsContract.buildDocumentUriUsingTree(treeUri, id))?.second
            ?: throw FsException("Android did not report the new file")
        return SafFile(resolver, treeUri, id, join(parent, meta.name), meta)
    }

    override fun toString(): String = "SafFile($path)"

    companion object {
        private const val MIME_BINARY = "application/octet-stream"

        private val PROJECTION = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_SIZE,
            Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_FLAGS,
        )

        /** The root of a granted tree, or null when it no longer exists or is not a folder. */
        fun openTree(resolver: ContentResolver, treeUri: Uri): SafFile? {
            val rootId = DocumentsContract.getTreeDocumentId(treeUri)
            val (_, meta) = queryMeta(resolver, DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId)) ?: return null
            if (meta.mimeType != Document.MIME_TYPE_DIR) return null
            return SafFile(resolver, treeUri, rootId, "", meta)
        }

        private fun queryMeta(resolver: ContentResolver, documentUri: Uri): Pair<String, Meta>? = try {
            resolver.query(documentUri, PROJECTION, null, null, null)?.use { c -> if (c.moveToFirst()) c.readMeta() else null }
        } catch (e: Exception) {
            // Lost permission, deleted document or a provider error all mean "not available".
            null
        }

        private fun Cursor.readMeta(): Pair<String, Meta>? {
            val id = if (isNull(0)) return null else getString(0)
            val name = if (isNull(1)) return null else getString(1)
            val mime = if (isNull(2)) MIME_BINARY else getString(2)
            val size = if (isNull(3)) 0L else getLong(3)
            val modified = if (isNull(4)) 0L else getLong(4)
            val flags = if (isNull(5)) 0 else getInt(5)
            return id to Meta(name, mime, size, modified, flags)
        }

        private fun join(parent: String, name: String): String = if (parent.isEmpty()) name else "$parent/$name"

        private fun parentPath(path: String): String = path.substringBeforeLast('/', "")

        private fun isSafeName(name: String): Boolean =
            name.isNotEmpty() && name != "." && name != ".." && '/' !in name && '\\' !in name && '\u0000' !in name

        private fun checkName(name: String) {
            if (!isSafeName(name)) throw FsException("Invalid file name '$name'")
        }
    }
}
