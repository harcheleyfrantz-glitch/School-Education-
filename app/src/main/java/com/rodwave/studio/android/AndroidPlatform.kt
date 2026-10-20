package com.rodwave.studio.android

import android.app.Application
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.widget.Toast
import androidx.activity.result.ActivityResultLauncher
import com.rodwave.engine.compat.InstalledGame
import com.rodwave.engine.fs.FsException
import com.rodwave.engine.fs.LocalFile
import com.rodwave.engine.fs.MAX_IN_MEMORY_BYTES
import com.rodwave.engine.fs.VirtualFile
import com.rodwave.studio.BuildConfig
import com.rodwave.studio.core.FolderPurpose
import com.rodwave.studio.core.FolderRef
import com.rodwave.studio.core.PickedFile
import com.rodwave.studio.core.PlatformServices
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.net.URI
import javax.net.ssl.HttpsURLConnection

/**
 * Android implementation of [PlatformServices]: Storage Access Framework pickers and trees,
 * package-manager game detection, sharing and HTTPS downloads. Picker results arrive through the
 * launchers [MainActivity][com.rodwave.studio.MainActivity] registers with [attach].
 */
class AndroidPlatform(private val app: Application) : PlatformServices {
    private val scope = MainScope()

    private var folderLauncher: ActivityResultLauncher<Uri?>? = null
    private var fileLauncher: ActivityResultLauncher<Array<String>>? = null
    private var createLauncher: ActivityResultLauncher<CreateDocumentContract.Request>? = null

    private var pendingFolder: ((FolderRef?) -> Unit)? = null
    private var pendingFile: ((PickedFile?) -> Unit)? = null
    private var pendingSave: PendingSave? = null

    private class PendingSave(val name: String, val data: ByteArray, val onResult: (Boolean, String?) -> Unit)

    override val platformName: String = "Android ${Build.VERSION.RELEASE}"
    override val sdkInt: Int = Build.VERSION.SDK_INT
    override val appStorage: VirtualFile = LocalFile(File(app.filesDir, "rodwave").apply { mkdirs() })
    override val deviceInfo: Map<String, String> = linkedMapOf(
        "Device" to "${Build.MANUFACTURER} ${Build.MODEL}",
        "Android" to "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
        "Device ABIs" to Build.SUPPORTED_ABIS.joinToString(),
        "Rodwave" to BuildConfig.VERSION_NAME,
    )

    fun attach(
        folder: ActivityResultLauncher<Uri?>,
        file: ActivityResultLauncher<Array<String>>,
        create: ActivityResultLauncher<CreateDocumentContract.Request>,
    ) {
        folderLauncher = folder
        fileLauncher = file
        createLauncher = create
    }

    /** Called when the activity that registered [folder] is destroyed. */
    fun detach(folder: ActivityResultLauncher<Uri?>) {
        if (folderLauncher !== folder) return
        folderLauncher = null
        fileLauncher = null
        createLauncher = null
    }

    override fun installedGame(): InstalledGame? = GameDetector.detect(app.packageManager)

    // ------------------------------------------------------------------ folders

    override fun pickFolder(purpose: FolderPurpose, onResult: (FolderRef?) -> Unit) {
        val launcher = folderLauncher ?: return onResult(null)
        pendingFolder = onResult
        try {
            launcher.launch(initialUri(purpose))
        } catch (e: ActivityNotFoundException) {
            pendingFolder = null
            toast("No folder picker is available on this device")
            onResult(null)
        }
    }

    fun onFolderPicked(uri: Uri?) {
        val callback = pendingFolder ?: return
        pendingFolder = null
        if (uri == null) return callback(null)
        val resolver = app.contentResolver
        val read = Intent.FLAG_GRANT_READ_URI_PERMISSION
        val write = Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        // Keep access across restarts; fall back to read-only when writing is not grantable.
        val persisted = runCatching { resolver.takePersistableUriPermission(uri, read or write) }.isSuccess ||
            runCatching { resolver.takePersistableUriPermission(uri, read) }.isSuccess
        if (!persisted) {
            toast("Android did not grant lasting access to that folder")
            return callback(null)
        }
        callback(FolderRef(uri.toString(), describeTree(uri)))
    }

    override fun openFolder(ref: FolderRef): VirtualFile? {
        val uri = Uri.parse(ref.uri)
        val granted = app.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }
        if (!granted) return null
        return runCatching { SafFile.openTree(app.contentResolver, uri) }.getOrNull()
    }

    override fun releaseFolder(ref: FolderRef) {
        val uri = Uri.parse(ref.uri)
        val permission = app.contentResolver.persistedUriPermissions.firstOrNull { it.uri == uri } ?: return
        val flags = (if (permission.isReadPermission) Intent.FLAG_GRANT_READ_URI_PERMISSION else 0) or
            (if (permission.isWritePermission) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else 0)
        runCatching { app.contentResolver.releasePersistableUriPermission(uri, flags) }
    }

    /** Where the picker opens. Only a hint: the user can navigate anywhere the picker allows. */
    private fun initialUri(purpose: FolderPurpose): Uri? {
        val path = when (purpose) {
            FolderPurpose.AML_MODS -> "AMLMods/${GameDetector.PACKAGE}"
            // Android 11+ blocks Android/data in the picker; pointing there would only show an error.
            FolderPurpose.GAME_DATA -> if (Build.VERSION.SDK_INT < 30) "Android/data/${GameDetector.PACKAGE}" else null
            FolderPurpose.EXPORT -> "Download"
            FolderPurpose.CLEO_SCRIPTS -> null
        } ?: return null
        return DocumentsContract.buildDocumentUri(EXTERNAL_STORAGE_AUTHORITY, "primary:$path")
    }

    /** "primary:AMLMods/x" becomes "AMLMods/x"; other volumes keep their id. */
    private fun describeTree(uri: Uri): String {
        val id = runCatching { DocumentsContract.getTreeDocumentId(uri) }.getOrNull() ?: return uri.toString()
        val volume = id.substringBefore(':')
        val relative = id.substringAfter(':', "")
        return when {
            volume == "primary" -> relative.ifEmpty { "Internal storage" }
            relative.isEmpty() -> "Storage $volume"
            else -> "$volume/$relative"
        }
    }

    // ------------------------------------------------------------------ files

    override fun pickFile(mimeTypes: List<String>, onResult: (PickedFile?) -> Unit) {
        val launcher = fileLauncher ?: return onResult(null)
        pendingFile = onResult
        try {
            launcher.launch(mimeTypes.ifEmpty { listOf("*/*") }.toTypedArray())
        } catch (e: ActivityNotFoundException) {
            pendingFile = null
            toast("No file picker is available on this device")
            onResult(null)
        }
    }

    fun onFilePicked(uri: Uri?) {
        val callback = pendingFile ?: return
        pendingFile = null
        if (uri == null) return callback(null)
        scope.launch {
            val result = withContext(Dispatchers.IO) { runCatching { readPicked(uri) } }
            val picked = result.getOrNull()
            if (picked == null) toast(result.exceptionOrNull()?.message ?: "Could not read the file")
            callback(picked)
        }
    }

    private fun readPicked(uri: Uri): PickedFile {
        val resolver = app.contentResolver
        var name = "file"
        var size = -1L
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val nameIndex = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0 && !c.isNull(nameIndex)) name = c.getString(nameIndex)
                val sizeIndex = c.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && !c.isNull(sizeIndex)) size = c.getLong(sizeIndex)
            }
        }
        if (size > MAX_IN_MEMORY_BYTES) throw FsException("$name is larger than ${MAX_IN_MEMORY_BYTES / MB} MB")
        val bytes = resolver.openInputStream(uri)?.use { readLimited(it, MAX_IN_MEMORY_BYTES, name) }
            ?: throw FsException("Android could not open $name")
        return PickedFile(name, bytes)
    }

    override fun saveDocument(suggestedName: String, mimeType: String, data: ByteArray, onResult: (Boolean, String?) -> Unit) {
        val launcher = createLauncher ?: return onResult(false, null)
        pendingSave = PendingSave(suggestedName, data, onResult)
        try {
            launcher.launch(CreateDocumentContract.Request(suggestedName, mimeType))
        } catch (e: ActivityNotFoundException) {
            pendingSave = null
            toast("No app can save documents on this device")
            onResult(false, null)
        }
    }

    fun onDocumentCreated(uri: Uri?) {
        val pending = pendingSave ?: return
        pendingSave = null
        if (uri == null) return pending.onResult(false, null)
        scope.launch {
            val written = withContext(Dispatchers.IO) {
                runCatching {
                    // The document was just created and is empty, so plain "w" is safe for every provider.
                    app.contentResolver.openOutputStream(uri, "w")?.use { it.write(pending.data) } != null
                }.getOrDefault(false)
            }
            if (!written) toast("Writing ${pending.name} failed")
            pending.onResult(written, if (written) displayName(uri) ?: pending.name else null)
        }
    }

    private fun displayName(uri: Uri): String? = runCatching {
        app.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst() && !c.isNull(0)) c.getString(0) else null
        }
    }.getOrNull()

    // ------------------------------------------------------------------ sharing and network

    override fun openUrl(url: String) {
        if (!url.startsWith("https://")) return toast("Only https links are opened")
        try {
            app.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: ActivityNotFoundException) {
            toast("No browser is installed")
        }
    }

    override fun share(title: String, text: String) {
        val send = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_SUBJECT, title)
            .putExtra(Intent.EXTRA_TEXT, text)
        try {
            app.startActivity(Intent.createChooser(send, title).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: ActivityNotFoundException) {
            toast("No app can share text")
        }
    }

    override fun copyToClipboard(label: String, text: String) {
        app.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText(label, text))
    }

    override fun downloadText(url: String, maxBytes: Int): String {
        require(url.startsWith("https://")) { "Only HTTPS downloads are allowed" }
        val connection = URI(url).toURL().openConnection() as HttpsURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        try {
            val code = connection.responseCode
            if (code != HttpsURLConnection.HTTP_OK) throw IOException("The server answered HTTP $code")
            return connection.inputStream.use { readLimited(it, maxBytes.toLong(), url.substringAfterLast('/')) }.toString(Charsets.UTF_8)
        } finally {
            connection.disconnect()
        }
    }

    private fun toast(message: String) {
        Toast.makeText(app, message, Toast.LENGTH_LONG).show()
    }

    private companion object {
        const val EXTERNAL_STORAGE_AUTHORITY = "com.android.externalstorage.documents"
        const val MB = 1024 * 1024

        fun readLimited(input: InputStream, limit: Long, name: String): ByteArray {
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(64 * 1024)
            var total = 0L
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                total += n
                if (total > limit) throw FsException("$name is larger than ${limit / MB} MB")
                out.write(buffer, 0, n)
            }
            return out.toByteArray()
        }
    }
}
