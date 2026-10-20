package com.rodwave.desktop

import com.rodwave.engine.compat.InstalledGame
import com.rodwave.engine.fs.LocalFile
import com.rodwave.engine.fs.VirtualFile
import com.rodwave.studio.core.FolderPurpose
import com.rodwave.studio.core.FolderRef
import com.rodwave.studio.core.PickedFile
import com.rodwave.studio.core.PlatformServices
import java.awt.Desktop
import java.awt.Toolkit
import java.awt.datatransfer.StringSelection
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.URI
import javax.swing.JFileChooser

/** java.io-backed platform for the desktop preview harness. There is no game on desktop. */
class DesktopPlatform(home: File, private val game: InstalledGame? = null) : PlatformServices {
    override val platformName: String = "Desktop preview (${System.getProperty("os.name")})"
    override val sdkInt: Int? = null
    override val appStorage: VirtualFile = LocalFile(home.apply { mkdirs() })
    override val deviceInfo: Map<String, String> = mapOf(
        "Platform" to platformName,
        "Java" to System.getProperty("java.version"),
    )

    override fun installedGame(): InstalledGame? = game

    override fun pickFolder(purpose: FolderPurpose, onResult: (FolderRef?) -> Unit) {
        val chooser = JFileChooser().apply {
            fileSelectionMode = JFileChooser.DIRECTORIES_ONLY
            dialogTitle = purpose.title
        }
        val ok = chooser.showOpenDialog(null) == JFileChooser.APPROVE_OPTION
        onResult(if (ok) chooser.selectedFile?.let { FolderRef(it.absolutePath, it.name) } else null)
    }

    override fun pickFile(mimeTypes: List<String>, onResult: (PickedFile?) -> Unit) {
        val chooser = JFileChooser()
        val ok = chooser.showOpenDialog(null) == JFileChooser.APPROVE_OPTION
        onResult(if (ok) chooser.selectedFile?.let { PickedFile(it.name, it.readBytes()) } else null)
    }

    override fun saveDocument(suggestedName: String, mimeType: String, data: ByteArray, onResult: (Boolean, String?) -> Unit) {
        val chooser = JFileChooser().apply { selectedFile = File(suggestedName) }
        if (chooser.showSaveDialog(null) == JFileChooser.APPROVE_OPTION) {
            val target = chooser.selectedFile
            runCatching { target.writeBytes(data) }
                .onSuccess { onResult(true, target.absolutePath) }
                .onFailure { onResult(false, null) }
        } else {
            onResult(false, null)
        }
    }

    override fun openFolder(ref: FolderRef): VirtualFile? = File(ref.uri).takeIf { it.isDirectory }?.let { LocalFile(it) }

    override fun releaseFolder(ref: FolderRef) = Unit

    override fun openUrl(url: String) {
        runCatching { Desktop.getDesktop().browse(URI(url)) }
    }

    override fun share(title: String, text: String) = copyToClipboard(title, text)

    override fun copyToClipboard(label: String, text: String) {
        runCatching { Toolkit.getDefaultToolkit().systemClipboard.setContents(StringSelection(text), null) }
    }

    override fun downloadText(url: String, maxBytes: Int): String {
        require(url.startsWith("https://")) { "Only HTTPS downloads are allowed" }
        URI(url).toURL().openStream().use { input ->
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                if (out.size() + n > maxBytes) throw IllegalStateException("Download exceeds ${maxBytes / (1024 * 1024)} MB")
                out.write(buffer, 0, n)
            }
            return out.toString(Charsets.UTF_8)
        }
    }
}
