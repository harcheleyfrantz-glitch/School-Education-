package com.rodwave.studio.core

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import com.rodwave.engine.compiler.CompileOptions
import com.rodwave.engine.compiler.CompileResult
import com.rodwave.engine.compiler.IncludeResolver
import com.rodwave.engine.compiler.IncludedSource
import com.rodwave.engine.compiler.ScriptCompiler
import com.rodwave.engine.diagnostics.Diagnostic
import com.rodwave.engine.editor.EditorSnapshot
import com.rodwave.engine.editor.UndoHistory
import com.rodwave.engine.fs.VirtualFile
import com.rodwave.engine.fs.readText
import com.rodwave.engine.fs.resolve
import com.rodwave.engine.fs.writeFile
import com.rodwave.engine.project.FxtFile
import com.rodwave.engine.project.Project
import com.rodwave.engine.scm.ScriptFormat
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
sealed interface DocumentSource {
    @Serializable
    data class ProjectFile(val projectName: String, val fileName: String) : DocumentSource

    @Serializable
    data class Scratch(val name: String) : DocumentSource
}

/** One open editor tab. */
class EditorDocument(
    val id: String,
    title: String,
    val source: DocumentSource,
    initialText: String,
    val readOnly: Boolean = false,
    defaultFormat: ScriptFormat = ScriptFormat.CLEO_ANDROID_AUTO,
) {
    var title by mutableStateOf(title)
    var value by mutableStateOf(TextFieldValue(initialText))
    var savedText by mutableStateOf(initialText)
    var diagnostics by mutableStateOf<List<Diagnostic>>(emptyList())
    var lastResult by mutableStateOf<CompileResult?>(null)
    var format by mutableStateOf(defaultFormat)
    val history = UndoHistory()

    val isDirty: Boolean get() = value.text != savedText

    /** File name on disk for project files; the tab title otherwise. */
    val fileName: String get() = (source as? DocumentSource.ProjectFile)?.fileName ?: title
    val isText: Boolean get() = fileName.endsWith(".fxt", ignoreCase = true)
    val text: String get() = value.text

    val canUndo: Boolean get() = history.canUndo
    val canRedo: Boolean get() = history.canRedo
}

/** Resolves {$INCLUDE} paths against the project folder. */
fun projectIncludeResolver(project: Project) = IncludeResolver { path, _ ->
    val file = project.directory.resolve(path) ?: return@IncludeResolver null
    if (file.isDirectory) null else IncludedSource(path, file.readText())
}

@Serializable
private data class RecoveryEntry(val id: String, val title: String, val source: DocumentSource, val text: String, val savedAt: Long)

/** Open documents, saving, compiling and crash recovery. */
class EditorWorkspace(private val studio: Studio) {
    val documents = mutableStateListOf<EditorDocument>()
    var activeId by mutableStateOf<String?>(null)
    var recoverable by mutableStateOf<List<Pair<String, String>>>(emptyList())
        private set

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private var counter = 0

    val active: EditorDocument? get() = documents.firstOrNull { it.id == activeId }

    fun openProjectFile(project: Project, fileName: String): EditorDocument {
        documents.firstOrNull { (it.source as? DocumentSource.ProjectFile)?.let { s -> s.projectName == project.name && s.fileName == fileName } == true }
            ?.let { activeId = it.id; return it }
        val file = project.directory.child(fileName) ?: throw IllegalStateException("$fileName not found in ${project.name}")
        val doc = EditorDocument(newId(), fileName, DocumentSource.ProjectFile(project.name, fileName), file.readText(), defaultFormat = project.format)
        documents += doc
        activeId = doc.id
        refreshDiagnostics(doc)
        return doc
    }

    fun openText(title: String, text: String, readOnly: Boolean = false, format: ScriptFormat = ScriptFormat.CLEO_ANDROID_AUTO): EditorDocument {
        val doc = EditorDocument(newId(), title, DocumentSource.Scratch(title), text, readOnly, format)
        documents += doc
        activeId = doc.id
        return doc
    }

    fun activate(doc: EditorDocument) {
        activeId = doc.id
    }

    fun close(doc: EditorDocument) {
        val index = documents.indexOf(doc)
        documents.remove(doc)
        deleteRecovery(doc.id)
        if (activeId == doc.id) activeId = documents.getOrNull(index.coerceAtMost(documents.lastIndex))?.id
    }

    /** Applies an edit coming from the text field and records it for undo. Read-only documents only move the selection. */
    fun update(doc: EditorDocument, newValue: TextFieldValue, now: Long = System.currentTimeMillis()) {
        val old = doc.value
        if (old.text != newValue.text) {
            if (doc.readOnly) return
            doc.history.record(EditorSnapshot(old.text, old.selection.start, old.selection.end), EditorSnapshot(newValue.text, newValue.selection.start, newValue.selection.end), now)
        } else if (old.selection != newValue.selection) {
            doc.history.breakCoalescing()
        }
        doc.value = newValue
    }

    fun undo(doc: EditorDocument) {
        val current = EditorSnapshot(doc.text, doc.value.selection.start, doc.value.selection.end)
        doc.history.undo(current)?.let { doc.value = TextFieldValue(it.text, TextRange(it.selectionStart, it.selectionEnd)) }
    }

    fun redo(doc: EditorDocument) {
        val current = EditorSnapshot(doc.text, doc.value.selection.start, doc.value.selection.end)
        doc.history.redo(current)?.let { doc.value = TextFieldValue(it.text, TextRange(it.selectionStart, it.selectionEnd)) }
    }

    /** Moves the selection without editing; works on read-only documents too. */
    fun select(doc: EditorDocument, start: Int, end: Int = start) {
        val length = doc.text.length
        doc.history.breakCoalescing()
        doc.value = doc.value.copy(selection = TextRange(start.coerceIn(0, length), end.coerceIn(0, length)))
    }

    /** Replaces [range] (end exclusive) with [replacement] as one undoable step and puts the caret after it. */
    fun replaceRange(doc: EditorDocument, start: Int, end: Int, replacement: String) {
        if (doc.readOnly) return
        val text = doc.text
        val s = start.coerceIn(0, text.length)
        val e = end.coerceIn(s, text.length)
        doc.history.breakCoalescing()
        update(doc, TextFieldValue(text.substring(0, s) + replacement + text.substring(e), TextRange(s + replacement.length)))
        doc.history.breakCoalescing()
    }

    /** Replaces the whole text as one undoable step (format, replace all, ...). */
    fun replaceAll(doc: EditorDocument, text: String, caret: Int = doc.value.selection.start) {
        if (doc.readOnly || text == doc.text) return
        doc.history.breakCoalescing()
        update(doc, TextFieldValue(text, TextRange(caret.coerceIn(0, text.length))))
        doc.history.breakCoalescing()
    }

    fun projectOf(doc: EditorDocument): Project? =
        (doc.source as? DocumentSource.ProjectFile)?.let { s -> studio.projectList.firstOrNull { it.name == s.projectName } }

    /** Saves a project document; scratch documents need [saveToProject]. Returns false on failure. */
    fun save(doc: EditorDocument): Boolean {
        val source = doc.source as? DocumentSource.ProjectFile ?: return false
        val project = projectOf(doc) ?: return false
        return try {
            project.directory.writeFile(source.fileName, doc.text.toByteArray())
            doc.savedText = doc.text
            deleteRecovery(doc.id)
            true
        } catch (e: Exception) {
            studio.console.error("editor", "Saving ${doc.title} failed: ${e.message}")
            false
        }
    }

    fun saveAll(): Int = documents.filter { it.isDirty && it.source is DocumentSource.ProjectFile }.count(::save)

    // ------------------------------------------------------------------ compile

    fun includeResolver(doc: EditorDocument): IncludeResolver? = projectOf(doc)?.let(::projectIncludeResolver)

    fun compileOptions(doc: EditorDocument) = CompileOptions(
        format = doc.format,
        fileName = doc.title,
        includeResolver = includeResolver(doc),
    )

    fun compile(doc: EditorDocument): CompileResult {
        val result = ScriptCompiler(studio.database).compile(doc.text, compileOptions(doc))
        doc.diagnostics = result.diagnostics
        doc.lastResult = result
        return result
    }

    /** Diagnostics for [text] without writing anything; safe to call off the main thread. */
    fun diagnosticsFor(doc: EditorDocument, text: String): List<Diagnostic> =
        if (doc.isText) {
            FxtFile.parse(text, doc.title).second
        } else {
            ScriptCompiler(studio.database).compile(text, compileOptions(doc)).diagnostics
        }

    fun refreshDiagnostics(doc: EditorDocument) {
        doc.diagnostics = diagnosticsFor(doc, doc.text)
    }

    // ------------------------------------------------------------------ recovery

    private fun recoveryDir(): VirtualFile? = studio.storage.resolve(RECOVERY)

    /** Writes snapshots of unsaved documents so they survive a crash or a killed process. */
    fun writeRecovery(now: Long = System.currentTimeMillis()) {
        for (doc in documents.filter { it.isDirty && !it.readOnly }) {
            val entry = RecoveryEntry(doc.id, doc.title, doc.source, doc.text, now)
            runCatching { studio.storage.writeFile("$RECOVERY/${doc.id}.json", json.encodeToString(RecoveryEntry.serializer(), entry).toByteArray()) }
        }
    }

    fun scanRecovery() {
        recoverable = recoveryDir()?.list()?.mapNotNull { f ->
            runCatching { json.decodeFromString(RecoveryEntry.serializer(), f.readText()) }.getOrNull()?.let { it.id to it.title }
        }.orEmpty()
    }

    fun restoreRecovered() {
        val dir = recoveryDir() ?: return
        for (f in dir.list()) {
            val entry = runCatching { json.decodeFromString(RecoveryEntry.serializer(), f.readText()) }.getOrNull() ?: continue
            val doc = EditorDocument(newId(), entry.title + " (recovered)", entry.source, entry.text)
            // Mark as unsaved so the user decides whether to keep it.
            doc.savedText = ""
            documents += doc
            activeId = doc.id
            f.delete()
        }
        recoverable = emptyList()
    }

    fun discardRecovered() {
        recoveryDir()?.list()?.forEach { it.delete() }
        recoverable = emptyList()
    }

    private fun deleteRecovery(id: String) {
        runCatching { studio.storage.resolve("$RECOVERY/$id.json")?.delete() }
    }

    private fun newId(): String = "doc${System.currentTimeMillis()}_${counter++}"

    companion object {
        const val RECOVERY = "recovery"
    }
}
