@file:OptIn(ExperimentalLayoutApi::class)

package com.rodwave.studio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Redo
import androidx.compose.material.icons.automirrored.outlined.Undo
import androidx.compose.material.icons.outlined.AccountTree
import androidx.compose.material.icons.outlined.AutoFixHigh
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material.icons.outlined.FindReplace
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material.icons.outlined.Menu
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Save
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.automirrored.outlined.ManageSearch
import androidx.compose.material.icons.outlined.Difference
import androidx.compose.material.icons.outlined.FormatListNumbered
import androidx.compose.material.icons.outlined.ReportProblem
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rodwave.engine.compiler.CompileResult
import com.rodwave.engine.diagnostics.Diagnostic
import com.rodwave.engine.diagnostics.Severity
import com.rodwave.engine.editor.BlockStructure
import com.rodwave.engine.editor.CommandHelpProvider
import com.rodwave.engine.editor.Completion
import com.rodwave.engine.editor.CompletionEngine
import com.rodwave.engine.editor.CompletionKind
import com.rodwave.engine.editor.LineIndex
import com.rodwave.engine.editor.Outline
import com.rodwave.engine.editor.OutlineKind
import com.rodwave.engine.editor.SearchEngine
import com.rodwave.engine.editor.SearchOptions
import com.rodwave.engine.editor.SearchResult
import com.rodwave.engine.editor.TextDiff
import com.rodwave.engine.fs.sha256
import com.rodwave.engine.project.Project
import com.rodwave.engine.project.ProjectManager
import com.rodwave.engine.project.Templates
import com.rodwave.engine.scm.ScriptFormat
import com.rodwave.studio.core.DocumentSource
import com.rodwave.studio.core.EditorDocument
import com.rodwave.studio.core.PickedFile
import com.rodwave.studio.core.Screen
import com.rodwave.studio.core.Studio
import com.rodwave.studio.ui.LocalOpenDrawer
import com.rodwave.studio.ui.LocalWideLayout
import com.rodwave.studio.ui.components.DiagnosticRow
import com.rodwave.studio.ui.components.EmptyState
import com.rodwave.studio.ui.components.KeyValue
import com.rodwave.studio.ui.components.Tag
import com.rodwave.studio.ui.editor.CodeEditor
import com.rodwave.studio.ui.editor.EditorActions
import com.rodwave.studio.ui.editor.outdentLine
import com.rodwave.studio.ui.theme.CodeFont
import com.rodwave.studio.ui.theme.Palette
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

private sealed interface EditorDialog {
    data object GoToLine : EditorDialog
    data object Outline : EditorDialog
    data object Snippets : EditorDialog
    data object SaveToProject : EditorDialog
    data object Diff : EditorDialog
    data class Compiled(val result: CompileResult) : EditorDialog
}

@Composable
fun EditorScreen(studio: Studio) {
    val editor = studio.editor
    val doc = editor.active
    val settings = studio.settings

    var searchOpen by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var replacement by remember { mutableStateOf("") }
    var options by remember { mutableStateOf(SearchOptions()) }
    var currentMatch by remember { mutableIntStateOf(-1) }
    var reveal by remember { mutableIntStateOf(0) }
    var problemsOpen by remember { mutableStateOf(false) }
    var dialog by remember { mutableStateOf<EditorDialog?>(null) }
    var closing by remember { mutableStateOf<EditorDocument?>(null) }

    // Live diagnostics: recompile a moment after typing stops, off the main thread.
    if (doc != null && settings.liveDiagnostics) {
        val text = doc.text
        LaunchedEffect(doc.id, text, studio.database) {
            delay(700)
            val diagnostics = withContext(Dispatchers.Default) { runCatching { editor.diagnosticsFor(doc, text) }.getOrNull() }
            if (diagnostics != null && doc.text == text) doc.diagnostics = diagnostics
        }
    }

    val search: SearchResult = remember(doc?.id, doc?.text, query, options, searchOpen) {
        if (doc == null || !searchOpen) SearchResult(emptyList()) else SearchEngine.findAll(doc.text, query, options)
    }

    fun jumpTo(target: EditorDocument, line: Int, column: Int = 1) {
        val idx = LineIndex(target.text)
        val l = (line - 1).coerceIn(0, idx.lineCount - 1)
        val start = idx.lineStart(l)
        val end = target.text.indexOf('\n', start).let { if (it < 0) target.text.length else it }
        editor.select(target, (start + (column - 1).coerceAtLeast(0)).coerceAtMost(end))
        reveal++
    }

    fun findNext(target: EditorDocument, forward: Boolean) {
        val matches = search.matches
        if (matches.isEmpty()) return
        val sel = target.value.selection
        val i = if (forward) {
            SearchEngine.nextIndex(matches, if (sel.collapsed) sel.min else sel.min + 1)
        } else {
            SearchEngine.previousIndex(matches, sel.min)
        } ?: return
        currentMatch = i
        editor.select(target, matches[i].first, matches[i].last + 1)
        reveal++
    }

    fun replaceCurrent(target: EditorDocument) {
        val sel = target.value.selection
        val range = search.matches.firstOrNull { it.first == sel.min && it.last + 1 == sel.max }
        val text = range?.let { SearchEngine.replacementFor(target.text, it, query, replacement, options) }
        if (range == null || text == null) {
            findNext(target, true)
            return
        }
        editor.replaceRange(target, range.first, range.last + 1, text)
        reveal++
    }

    fun replaceEverything(target: EditorDocument) {
        val (newText, count) = SearchEngine.replaceAll(target.text, query, replacement, options)
        if (count > 0) editor.replaceAll(target, newText)
        studio.notify(if (count == 0) "No matches to replace" else "Replaced $count match(es)")
    }

    fun save(target: EditorDocument) {
        when {
            target.readOnly -> studio.notify("This document is read-only; save the listing with Export source", isError = true)
            target.source is DocumentSource.ProjectFile -> if (editor.save(target)) studio.notify("Saved ${target.title}")
            else -> dialog = EditorDialog.SaveToProject
        }
    }

    fun compile(target: EditorDocument) {
        if (target.readOnly || target.isText) {
            studio.notify(if (target.isText) "FXT text tables are not compiled; CLEO loads them as they are" else "Listings are read-only and cannot be compiled", isError = true)
            return
        }
        if (target.source is DocumentSource.ProjectFile && target.isDirty) editor.save(target)
        studio.compileDocument(target) { result ->
            dialog = EditorDialog.Compiled(result)
            if (!result.success) problemsOpen = true
        }
    }

    fun format(target: EditorDocument) {
        if (target.readOnly || target.isText) return
        editor.replaceAll(target, BlockStructure.format(target.text))
    }

    Column(Modifier.fillMaxSize()) {
        EditorTopBar(
            studio = studio,
            doc = doc,
            onUndo = { doc?.let(editor::undo) },
            onRedo = { doc?.let(editor::redo) },
            onSave = { doc?.let(::save) },
            onCompile = { doc?.let(::compile) },
            onSearch = { searchOpen = !searchOpen },
            onFormat = { doc?.let(::format) },
            onDialog = { dialog = it },
            onToggleProblems = { problemsOpen = !problemsOpen },
            onClose = { d -> if (d.isDirty) closing = d else editor.close(d) },
        )
        if (editor.documents.isNotEmpty()) {
            TabStrip(studio, onClose = { d -> if (d.isDirty) closing = d else editor.close(d) })
        }
        if (doc == null) {
            NoDocument(studio)
        } else {
            if (searchOpen) {
                SearchBar(
                    query = query,
                    onQuery = { query = it; currentMatch = -1 },
                    replacement = replacement,
                    onReplacement = { replacement = it },
                    options = options,
                    onOptions = { options = it; currentMatch = -1 },
                    result = search,
                    current = currentMatch,
                    readOnly = doc.readOnly,
                    onNext = { findNext(doc, true) },
                    onPrevious = { findNext(doc, false) },
                    onReplace = { replaceCurrent(doc) },
                    onReplaceAll = { replaceEverything(doc) },
                    onClose = { searchOpen = false },
                )
            }
            CodeEditor(
                studio = studio,
                doc = doc,
                searchMatches = search.matches,
                currentMatch = if (currentMatch in search.matches.indices) currentMatch else -1,
                revealRequest = reveal,
                actions = EditorActions(
                    onSave = { save(doc) },
                    onCompile = { compile(doc) },
                    onFind = { searchOpen = true },
                    onFormat = { format(doc) },
                ),
                modifier = Modifier.weight(1f).fillMaxWidth(),
            )
            if (problemsOpen) {
                ProblemsPanel(doc, onJump = { d -> jumpTo(doc, d.line, d.column) }, onClose = { problemsOpen = false })
            }
            CompletionStrip(studio, doc)
            StatusBar(studio, doc, onProblems = { problemsOpen = !problemsOpen })
            if (settings.codingBar && !doc.readOnly) CodingBar(studio, doc, onFind = { searchOpen = !searchOpen })
        }
    }

    if (doc != null) {
        when (val d = dialog) {
            EditorDialog.GoToLine -> GoToLineDialog(doc, onDismiss = { dialog = null }) { line -> jumpTo(doc, line); dialog = null }
            EditorDialog.Outline -> OutlineDialog(doc, onDismiss = { dialog = null }) { line -> jumpTo(doc, line + 1); dialog = null }
            EditorDialog.Snippets -> SnippetDialog(onDismiss = { dialog = null }) { body -> insertSnippet(studio, doc, body); dialog = null }
            EditorDialog.SaveToProject -> SaveToProjectDialog(studio, doc, onDismiss = { dialog = null })
            EditorDialog.Diff -> DiffDialog(doc, onDismiss = { dialog = null })
            is EditorDialog.Compiled -> CompileResultDialog(
                studio, doc, d.result,
                onJump = { diag -> jumpTo(doc, diag.line, diag.column); dialog = null },
                onDismiss = { dialog = null },
            )
            null -> Unit
        }
    }
    closing?.let { target ->
        CloseDocumentDialog(
            doc = target,
            onSave = {
                if (target.source is DocumentSource.ProjectFile && editor.save(target)) editor.close(target)
                closing = null
            },
            onDiscard = { editor.close(target); closing = null },
            onDismiss = { closing = null },
        )
    }
}

// ---------------------------------------------------------------------------------------- top bar and tabs

@Composable
private fun EditorTopBar(
    studio: Studio,
    doc: EditorDocument?,
    onUndo: () -> Unit,
    onRedo: () -> Unit,
    onSave: () -> Unit,
    onCompile: () -> Unit,
    onSearch: () -> Unit,
    onFormat: () -> Unit,
    onDialog: (EditorDialog) -> Unit,
    onToggleProblems: () -> Unit,
    onClose: (EditorDocument) -> Unit,
) {
    val wide = LocalWideLayout.current
    val openDrawer = LocalOpenDrawer.current
    var menu by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().height(56.dp).background(MaterialTheme.colorScheme.background).padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (!wide) IconButton(onClick = openDrawer) { Icon(Icons.Outlined.Menu, "Menu") }
        Column(Modifier.weight(1f).padding(start = if (wide) 12.dp else 0.dp)) {
            Text(doc?.title ?: "Editor", style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (doc != null) {
                val where = (doc.source as? DocumentSource.ProjectFile)?.projectName ?: "Scratch"
                val flags = buildList {
                    if (doc.readOnly) add("read-only")
                    if (doc.isDirty) add("unsaved")
                }
                Text(
                    (listOf(where) + flags).joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                )
            }
        }
        if (doc != null) {
            val compact = Modifier.size(40.dp)
            val editable = !doc.readOnly
            // Reading isDirty subscribes this bar to every edit, so the undo/redo state stays current.
            val dirty = doc.isDirty
            IconButton(onClick = onUndo, enabled = editable && doc.canUndo, modifier = compact) { Icon(Icons.AutoMirrored.Outlined.Undo, "Undo") }
            IconButton(onClick = onRedo, enabled = editable && doc.canRedo, modifier = compact) { Icon(Icons.AutoMirrored.Outlined.Redo, "Redo") }
            if (wide) IconButton(onClick = onSearch, modifier = compact) { Icon(Icons.Outlined.Search, "Find and replace") }
            IconButton(onClick = onSave, enabled = editable && (dirty || doc.source !is DocumentSource.ProjectFile), modifier = compact) {
                Icon(Icons.Outlined.Save, "Save")
            }
            if (!doc.isText && editable) {
                Box(
                    Modifier
                        .padding(horizontal = 4.dp)
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(Brush.linearGradient(listOf(Palette.Sunset, Palette.Pink)))
                        .clickable(enabled = studio.busy == null, onClick = onCompile),
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Outlined.PlayArrow, "Compile", tint = Color.White) }
            }
            Box {
                IconButton(onClick = { menu = true }, modifier = compact) { Icon(Icons.Outlined.MoreVert, "More editor actions") }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    MenuEntry("Find and replace", Icons.Outlined.FindReplace) { menu = false; onSearch() }
                    MenuEntry("Go to line…", Icons.Outlined.FormatListNumbered) { menu = false; onDialog(EditorDialog.GoToLine) }
                    MenuEntry("Outline…", Icons.Outlined.AccountTree) { menu = false; onDialog(EditorDialog.Outline) }
                    MenuEntry("Problems", Icons.Outlined.ReportProblem) { menu = false; onToggleProblems() }
                    if (editable && !doc.isText) {
                        MenuEntry("Format document", Icons.Outlined.AutoFixHigh) { menu = false; onFormat() }
                        MenuEntry("Insert snippet…", Icons.Outlined.Code) { menu = false; onDialog(EditorDialog.Snippets) }
                    }
                    if (doc.source is DocumentSource.ProjectFile) {
                        MenuEntry("Compare with saved", Icons.Outlined.Difference, enabled = dirty) { menu = false; onDialog(EditorDialog.Diff) }
                    } else if (editable) {
                        MenuEntry("Save to project…", Icons.Outlined.FolderOpen) { menu = false; onDialog(EditorDialog.SaveToProject) }
                    }
                    MenuEntry("Export source…", Icons.Outlined.FileUpload) {
                        menu = false
                        studio.platform.saveDocument(doc.fileName.substringBeforeLast('.') + ".txt", "text/plain", doc.text.toByteArray()) { ok, _ ->
                            if (ok) studio.notify("Exported ${doc.title}")
                        }
                    }
                    if (!doc.isText && editable) {
                        HorizontalDivider()
                        Text(
                            "Target without a {\$CLEO} directive",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                        )
                        listOf(ScriptFormat.CLEO_ANDROID_AUTO, ScriptFormat.CLEO_ANDROID_INVOKED, ScriptFormat.CLEO_PC).forEach { f ->
                            DropdownMenuItem(
                                text = { Text(f.title) },
                                leadingIcon = { RadioButton(selected = doc.format == f, onClick = null) },
                                onClick = { doc.format = f; menu = false },
                            )
                        }
                    }
                    HorizontalDivider()
                    MenuEntry("Close tab", Icons.Outlined.Close) { menu = false; onClose(doc) }
                }
            }
        }
    }
}

@Composable
private fun MenuEntry(label: String, icon: ImageVector, enabled: Boolean = true, onClick: () -> Unit) {
    DropdownMenuItem(text = { Text(label) }, leadingIcon = { Icon(icon, null) }, enabled = enabled, onClick = onClick)
}

@Composable
private fun TabStrip(studio: Studio, onClose: (EditorDocument) -> Unit) {
    val editor = studio.editor
    Row(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.background)
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        editor.documents.forEach { d ->
            val active = d.id == editor.activeId
            val shape = RoundedCornerShape(10.dp)
            Row(
                Modifier
                    .clip(shape)
                    .background(if (active) MaterialTheme.colorScheme.surfaceContainerHigh else MaterialTheme.colorScheme.surfaceContainerLow)
                    .then(
                        if (active) Modifier.border(1.dp, Brush.linearGradient(listOf(Palette.Sunset.copy(alpha = 0.8f), Palette.Pink.copy(alpha = 0.5f))), shape) else Modifier,
                    )
                    .clickable { editor.activate(d) }
                    .padding(start = 12.dp, end = 2.dp, top = 2.dp, bottom = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (d.isDirty) {
                    Box(Modifier.size(7.dp).clip(CircleShape).background(Palette.Gold))
                    Spacer(Modifier.width(6.dp))
                }
                val errors = d.diagnostics.count { it.isError }
                Text(
                    d.title,
                    style = MaterialTheme.typography.labelLarge,
                    color = when {
                        errors > 0 -> MaterialTheme.colorScheme.error
                        active -> MaterialTheme.colorScheme.onSurface
                        else -> MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    maxLines = 1,
                )
                IconButton(onClick = { onClose(d) }, modifier = Modifier.size(30.dp)) {
                    Icon(Icons.Outlined.Close, "Close ${d.title}", modifier = Modifier.size(16.dp))
                }
            }
        }
    }
}

@Composable
private fun NoDocument(studio: Studio) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        EmptyState(
            Icons.Outlined.Description,
            "No open files",
            "Open a file from a project, decompile a script, or start a scratch file.",
        ) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                FilledTonalButton(onClick = { studio.navigate(Screen.PROJECTS) }) { Text("Projects") }
                OutlinedButton(onClick = {
                    studio.editor.openText("scratch.txt", Templates.EMPTY.source("Scratch"), format = ScriptFormat.CLEO_ANDROID_AUTO)
                }) { Text("Scratch file") }
                OutlinedButton(onClick = { studio.navigate(Screen.BUILD) }) { Text("Decompile a script") }
            }
        }
    }
}

// ---------------------------------------------------------------------------------------- search

@Composable
private fun SearchBar(
    query: String,
    onQuery: (String) -> Unit,
    replacement: String,
    onReplacement: (String) -> Unit,
    options: SearchOptions,
    onOptions: (SearchOptions) -> Unit,
    result: SearchResult,
    current: Int,
    readOnly: Boolean,
    onNext: () -> Unit,
    onPrevious: () -> Unit,
    onReplace: () -> Unit,
    onReplaceAll: () -> Unit,
    onClose: () -> Unit,
) {
    var showReplace by remember { mutableStateOf(false) }
    Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CompactField(query, onQuery, "Find", Modifier.weight(1f), isError = result.error != null, onEnter = onNext)
                val count = result.matches.size
                Text(
                    when {
                        result.error != null -> "!"
                        query.isEmpty() -> ""
                        count == 0 -> "0"
                        current in 0 until count -> "${current + 1}/$count"
                        else -> "$count"
                    },
                    style = MaterialTheme.typography.labelMedium,
                    color = if (count == 0 && query.isNotEmpty()) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 6.dp),
                )
                IconButton(onClick = onPrevious, modifier = Modifier.size(36.dp)) { Icon(Icons.Outlined.KeyboardArrowUp, "Previous match") }
                IconButton(onClick = onNext, modifier = Modifier.size(36.dp)) { Icon(Icons.Outlined.KeyboardArrowDown, "Next match") }
                if (!readOnly) {
                    IconButton(onClick = { showReplace = !showReplace }, modifier = Modifier.size(36.dp)) { Icon(Icons.Outlined.FindReplace, "Toggle replace") }
                }
                IconButton(onClick = onClose, modifier = Modifier.size(36.dp)) { Icon(Icons.Outlined.Close, "Close search") }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                ToggleChip("Aa", "Match case", options.caseSensitive) { onOptions(options.copy(caseSensitive = it)) }
                ToggleChip("W", "Whole word", options.wholeWord) { onOptions(options.copy(wholeWord = it)) }
                ToggleChip(".*", "Regular expression", options.regex) { onOptions(options.copy(regex = it)) }
                val error = result.error
                if (error != null) {
                    Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                } else if (result.matches.size >= SearchEngine.MAX_MATCHES) {
                    Text("Showing the first ${SearchEngine.MAX_MATCHES} matches", style = MaterialTheme.typography.labelSmall, color = Palette.Gold)
                }
            }
            if (showReplace && !readOnly) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    CompactField(replacement, onReplacement, if (options.regex) "Replace (\$1 = group 1)" else "Replace", Modifier.weight(1f), onEnter = onReplace)
                    TextButton(onClick = onReplace, enabled = result.matches.isNotEmpty()) { Text("Replace") }
                    TextButton(onClick = onReplaceAll, enabled = result.matches.isNotEmpty()) { Text("All") }
                }
            }
        }
    }
}

@Composable
private fun CompactField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier, isError: Boolean = false, onEnter: () -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        modifier = modifier.heightIn(min = 48.dp),
        singleLine = true,
        isError = isError,
        placeholder = { Text(placeholder, style = MaterialTheme.typography.bodyMedium) },
        textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = CodeFont),
        keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(onSearch = { onEnter() }, onDone = { onEnter() }),
        shape = MaterialTheme.shapes.small,
    )
}

@Composable
private fun ToggleChip(label: String, description: String, selected: Boolean, onToggle: (Boolean) -> Unit) {
    val color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
    Text(
        label,
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(if (selected) color.copy(alpha = 0.16f) else Color.Transparent)
            .border(1.dp, color.copy(alpha = 0.5f), RoundedCornerShape(8.dp))
            .selectable(selected = selected, onClick = { onToggle(!selected) })
            .semantics { contentDescription = description }
            .padding(horizontal = 10.dp, vertical = 4.dp),
        color = color,
        fontFamily = CodeFont,
        fontWeight = FontWeight.Bold,
        fontSize = 13.sp,
    )
}

// ---------------------------------------------------------------------------------------- bottom panels

@Composable
private fun ProblemsPanel(doc: EditorDocument, onJump: (Diagnostic) -> Unit, onClose: () -> Unit) {
    val items = remember(doc.diagnostics) { doc.diagnostics.sortedWith(compareBy({ it.severity.ordinal }, { it.line }, { it.column })) }
    Surface(color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.fillMaxWidth().heightIn(max = 220.dp)) {
            Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Problems", style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                Text(
                    "${items.count { it.isError }} errors · ${items.count { it.severity == Severity.WARNING }} warnings",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                IconButton(onClick = onClose, modifier = Modifier.size(36.dp)) { Icon(Icons.Outlined.Close, "Close problems") }
            }
            if (items.isEmpty()) {
                Text(
                    "No problems found.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(14.dp),
                )
            } else {
                LazyColumn(Modifier.padding(horizontal = 8.dp)) {
                    items(items) { d -> DiagnosticRow(d, onClick = if (d.line > 0) ({ onJump(d) }) else null) }
                }
            }
        }
    }
}

@Composable
private fun CompletionStrip(studio: Studio, doc: EditorDocument) {
    val settings = studio.settings
    val engine = remember(studio.database) { CompletionEngine(studio.database) }
    val value = doc.value
    val result = remember(value.text, value.selection, engine, settings.autocomplete, doc.readOnly) {
        if (!settings.autocomplete || doc.readOnly || doc.isText || !value.selection.collapsed) {
            null
        } else {
            engine.complete(value.text, value.selection.start, limit = 30)
                .takeIf { it.prefix.isNotEmpty() }
                ?.let { r -> r.copy(items = r.items.filter { it.insertText.trim() != r.prefix }) }
                ?.takeIf { it.items.isNotEmpty() }
        }
    }
    if (result == null) return
    Row(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 6.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        result.items.forEach { item ->
            CompletionChip(item) {
                // Apply only if the text is still the one the suggestions were computed for.
                if (doc.text == value.text) studio.editor.replaceRange(doc, result.replaceStart, result.replaceEnd, item.insertText)
            }
        }
    }
}

@Composable
private fun CompletionChip(item: Completion, onClick: () -> Unit) {
    val color = when (item.kind) {
        CompletionKind.COMMAND -> Palette.Sunset
        CompletionKind.KEYWORD -> Palette.Pink
        CompletionKind.LABEL -> Palette.Teal
        CompletionKind.VARIABLE -> Palette.Sky
        CompletionKind.CONSTANT -> Palette.Gold
        CompletionKind.ENUM_MEMBER -> Palette.Violet
        CompletionKind.MODEL -> Palette.Green
    }
    Column(
        Modifier
            .clip(RoundedCornerShape(10.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 4.dp),
    ) {
        Text(item.label, fontFamily = CodeFont, fontSize = 13.sp, color = color, maxLines = 1)
        Text(
            item.detail,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.widthIn(max = 220.dp),
        )
    }
}

@Composable
private fun StatusBar(studio: Studio, doc: EditorDocument, onProblems: () -> Unit) {
    val value = doc.value
    val caret = value.selection.start
    val lineIndex = remember(value.text) { LineIndex(value.text) }
    val line = lineIndex.lineOf(caret)
    val column = caret - lineIndex.lineStart(line)
    val help = remember(value.text, caret, studio.database, doc.isText) {
        if (doc.isText) null else CommandHelpProvider.at(value.text, caret, studio.database)
    }
    val errors = doc.diagnostics.count { it.isError }
    val warnings = doc.diagnostics.count { it.severity == Severity.WARNING }
    Row(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerLow)
            .padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            "${line + 1}:${column + 1}" + if (!value.selection.collapsed) " (${value.selection.length})" else "",
            fontFamily = CodeFont,
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Column(Modifier.weight(1f)) {
            if (help != null) {
                Text(help.statusText, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, fontFamily = CodeFont)
                help.currentParamText?.let {
                    Text("param ${help.paramIndex + 1}: $it", fontSize = 11.sp, color = Palette.Teal, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            } else {
                Text(
                    if (doc.isText) "FXT text table" else (doc.lastResult?.format ?: doc.format).title,
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        Row(
            Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onProblems).padding(horizontal = 6.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (errors == 0 && warnings == 0) {
                Icon(Icons.Outlined.CheckCircle, "No problems", tint = Palette.Green, modifier = Modifier.size(16.dp))
            } else {
                if (errors > 0) CountBadge(errors, MaterialTheme.colorScheme.error, Icons.Outlined.ErrorOutline)
                if (warnings > 0) CountBadge(warnings, Palette.Gold, Icons.Outlined.ReportProblem)
            }
        }
    }
}

@Composable
private fun CountBadge(count: Int, color: Color, icon: ImageVector) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = color, modifier = Modifier.size(15.dp))
        Spacer(Modifier.width(3.dp))
        Text("$count", color = color, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
    }
}

private class CodingKey(val label: String, val description: String, val action: (Studio, EditorDocument) -> Unit)

private fun insertText(studio: Studio, doc: EditorDocument, text: String) {
    val sel = doc.value.selection
    studio.editor.replaceRange(doc, sel.min, sel.max, text)
}

private fun moveCaret(studio: Studio, doc: EditorDocument, delta: Int) {
    val sel = doc.value.selection
    studio.editor.select(doc, (if (delta < 0) sel.min else sel.max) + delta)
}

private val CODING_KEYS: List<CodingKey> = buildList {
    add(CodingKey("⇥", "Indent") { s, d -> insertText(s, d, BlockStructure.INDENT) })
    add(CodingKey("⇤", "Outdent") { s, d -> outdentLine(s, d) })
    add(CodingKey("◀", "Caret left") { s, d -> moveCaret(s, d, -1) })
    add(CodingKey("▶", "Caret right") { s, d -> moveCaret(s, d, 1) })
    listOf("@", "$", ":", "=", "(", ")", "'", "\"", "#", "{", "}", ".", ",", "+", "-", "*", "/", "<", ">", "_", "[", "]", "//").forEach { sym ->
        add(CodingKey(sym, "Insert $sym") { s, d -> insertText(s, d, sym) })
    }
}

@Composable
private fun CodingBar(studio: Studio, doc: EditorDocument, onFind: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 4.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Box(
            Modifier.size(width = 42.dp, height = 36.dp).clip(RoundedCornerShape(8.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh).clickable(onClick = onFind),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.AutoMirrored.Outlined.ManageSearch, "Find", modifier = Modifier.size(18.dp)) }
        CODING_KEYS.forEach { key ->
            Box(
                Modifier
                    .size(width = 42.dp, height = 36.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                    .clickable { key.action(studio, doc) },
                contentAlignment = Alignment.Center,
            ) {
                Text(key.label, fontFamily = CodeFont, fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurface)
            }
        }
    }
}

// ---------------------------------------------------------------------------------------- dialogs

@Composable
private fun GoToLineDialog(doc: EditorDocument, onDismiss: () -> Unit, onGo: (Int) -> Unit) {
    val lines = remember(doc.text) { LineIndex(doc.text).lineCount }
    var value by remember { mutableStateOf("") }
    val target = value.toIntOrNull()?.takeIf { it in 1..lines }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Go to line") },
        text = {
            OutlinedTextField(
                value = value,
                onValueChange = { v -> value = v.filter(Char::isDigit).take(7) },
                singleLine = true,
                label = { Text("Line (1–$lines)") },
                isError = value.isNotEmpty() && target == null,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = { target?.let(onGo) }),
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = { TextButton(enabled = target != null, onClick = { target?.let(onGo) }) { Text("Go") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun OutlineDialog(doc: EditorDocument, onDismiss: () -> Unit, onJump: (Int) -> Unit) {
    val items = remember(doc.text) { runCatching { Outline.of(doc.text) }.getOrDefault(emptyList()) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Outline") },
        text = {
            if (items.isEmpty()) {
                Text("No labels, constants, variables or directives in this file.")
            } else {
                LazyColumn(Modifier.heightIn(max = 420.dp)) {
                    items(items) { item ->
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).clickable { onJump(item.line) }.padding(vertical = 8.dp, horizontal = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            val (label, color) = when (item.kind) {
                                OutlineKind.LABEL -> "label" to Palette.Teal
                                OutlineKind.CONSTANT -> "const" to Palette.Gold
                                OutlineKind.VARIABLE -> "var" to Palette.Sky
                                OutlineKind.DIRECTIVE -> "directive" to Palette.Violet
                            }
                            Tag(label, color)
                            Spacer(Modifier.width(10.dp))
                            Text(item.name, fontFamily = CodeFont, fontSize = 13.sp, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text("${item.line + 1}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Close") } },
    )
}

@Composable
private fun SnippetDialog(onDismiss: () -> Unit, onInsert: (String) -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Insert snippet") },
        text = {
            LazyColumn(Modifier.heightIn(max = 460.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(Templates.SNIPPETS) { s ->
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                            .clickable { onInsert(s.body) }
                            .padding(10.dp),
                    ) {
                        Text(s.title, style = MaterialTheme.typography.titleSmall)
                        Text(s.description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(s.body.lines().first(), fontFamily = CodeFont, fontSize = 12.sp, color = Palette.Teal, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Close") } },
    )
}

/** Inserts [body] at the caret, indenting continuation lines like the caret's line and placing the caret on the first blank line. */
private fun insertSnippet(studio: Studio, doc: EditorDocument, body: String) {
    val v = doc.value
    val idx = LineIndex(v.text)
    val lineStart = idx.lineStart(idx.lineOf(v.selection.min))
    val before = v.text.substring(lineStart, v.selection.min)
    val indent = if (before.isBlank()) before else before.takeWhile { it == ' ' }
    val lines = body.lines()
    val text = lines.mapIndexed { i, l -> if (i == 0) l else indent + l }.joinToString("\n")
    studio.editor.replaceRange(doc, v.selection.min, v.selection.max, text)
    val blank = lines.indexOfFirst { it.isNotEmpty() && it.isBlank() }
    if (blank > 0) {
        val offsetInText = text.lines().take(blank + 1).sumOf { it.length + 1 } - 1
        studio.editor.select(doc, v.selection.min + offsetInText)
    }
}

@Composable
private fun SaveToProjectDialog(studio: Studio, doc: EditorDocument, onDismiss: () -> Unit) {
    var project by remember { mutableStateOf<Project?>(studio.projectList.firstOrNull()) }
    val suggested = remember(doc.title) {
        val base = doc.title.removeSuffix(" (recovered)")
        if (runCatching { ProjectManager.validateFileName(base) }.isSuccess) base else base.substringBeforeLast('.').filter { it.isLetterOrDigit() || it in " _.-" }.ifBlank { "script" } + ".txt"
    }
    var name by remember { mutableStateOf(suggested) }
    val nameError = remember(name) { runCatching { ProjectManager.validateFileName(name) }.exceptionOrNull()?.message }
    val exists = remember(name, project) { project?.directory?.child(name.trim()) != null }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Save to project") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (studio.projectList.isEmpty()) {
                    Text("There are no projects yet. Create one first; the scratch file stays open.")
                    FilledTonalButton(onClick = { onDismiss(); studio.navigate(Screen.PROJECTS) }) { Text("Go to Projects") }
                } else {
                    Text("Project", style = MaterialTheme.typography.titleSmall)
                    studio.projectList.forEach { p ->
                        Row(
                            Modifier.fillMaxWidth().selectable(selected = p == project, onClick = { project = p }).padding(vertical = 2.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = p == project, onClick = { project = p })
                            Text(p.name, modifier = Modifier.weight(1f))
                            Tag(".${p.format.extension}", MaterialTheme.colorScheme.tertiary)
                        }
                    }
                    OutlinedTextField(
                        value = name,
                        onValueChange = { name = it },
                        singleLine = true,
                        label = { Text("File name") },
                        isError = nameError != null || exists,
                        supportingText = {
                            when {
                                nameError != null -> Text(nameError)
                                exists -> Text("A file with this name already exists; choose another name")
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = project != null && nameError == null && !exists,
                onClick = {
                    project?.let { studio.saveScratchToProject(doc, it, name.trim()) }
                    onDismiss()
                },
            ) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun DiffDialog(doc: EditorDocument, onDismiss: () -> Unit) {
    val diff = remember(doc.savedText, doc.text) { TextDiff.unified(doc.savedText, doc.text, "saved", "editor") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Changes since last save") },
        text = {
            if (diff.isEmpty()) {
                Text("No changes.")
            } else {
                val lines = remember(diff) { diff.lines() }
                Surface(color = MaterialTheme.colorScheme.surfaceContainerLowest, shape = MaterialTheme.shapes.small) {
                    LazyColumn(Modifier.heightIn(max = 460.dp).horizontalScroll(rememberScrollState()).padding(8.dp)) {
                        itemsIndexed(lines) { _, l ->
                            val color = when {
                                l.startsWith("+++") || l.startsWith("---") -> MaterialTheme.colorScheme.onSurfaceVariant
                                l.startsWith("@@") -> Palette.Violet
                                l.startsWith("+") -> Palette.Green
                                l.startsWith("-") -> Palette.Red
                                else -> MaterialTheme.colorScheme.onSurface
                            }
                            Text(l, fontFamily = CodeFont, fontSize = 12.sp, color = color, softWrap = false)
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Close") } },
    )
}

@Composable
private fun CompileResultDialog(studio: Studio, doc: EditorDocument, result: CompileResult, onJump: (Diagnostic) -> Unit, onDismiss: () -> Unit) {
    val bytes = result.bytes
    val outName = doc.fileName.substringBeforeLast('.') + "." + result.format.extension
    val inProject = doc.source is DocumentSource.ProjectFile
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            if (bytes != null) Icon(Icons.Outlined.CheckCircle, null, tint = Palette.Green) else Icon(Icons.Outlined.ErrorOutline, null, tint = MaterialTheme.colorScheme.error)
        },
        title = { Text(if (bytes != null) "Compiled $outName" else "Compilation failed") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (bytes != null) {
                    KeyValue("Format", result.format.title)
                    KeyValue("Size", "${bytes.size} bytes")
                    KeyValue("Instructions", "${result.instructionCount}")
                    KeyValue("Labels", "${result.labels.size}")
                    KeyValue("SHA-256", bytes.sha256().take(16) + "…", mono = true)
                    Text(
                        "Validated: every instruction was decoded back and matched what was emitted, and every jump lands on an instruction.",
                        style = MaterialTheme.typography.bodySmall,
                        color = Palette.Green,
                    )
                    Text(
                        "Rodwave cannot run scripts, so in-game behaviour is untested. Keep a backup when you install it." +
                            if (inProject) " The binary was saved next to the source in the project." else "",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (result.warnings.isNotEmpty()) {
                        Text("${result.warnings.size} warning(s)", style = MaterialTheme.typography.titleSmall, color = Palette.Gold)
                        result.warnings.take(20).forEach { d -> DiagnosticRow(d, onClick = if (d.line > 0) ({ onJump(d) }) else null) }
                    }
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilledTonalButton(onClick = { studio.exportBytes(outName, bytes) }) { Text("Save as…") }
                        OutlinedButton(onClick = { studio.exportToFolder(outName, bytes) }) { Text("Copy to export folder") }
                        OutlinedButton(onClick = {
                            studio.importCompiled(outName, bytes) { r -> if (r.mod != null) studio.navigate(Screen.MODS) }
                            onDismiss()
                        }) { Text("Add to Mod Manager") }
                        OutlinedButton(onClick = {
                            studio.inspectFile(PickedFile(outName, bytes))
                            studio.navigate(Screen.BUILD)
                            onDismiss()
                        }) { Text("Inspect output") }
                    }
                } else {
                    Text(
                        "${result.errors.size} error(s), ${result.warnings.size} warning(s). No output was written.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    result.diagnostics.filter { it.severity != Severity.INFO }.sortedBy { it.severity.ordinal }.take(40).forEach { d ->
                        DiagnosticRow(d, onClick = if (d.line > 0) ({ onJump(d) }) else null)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Close") } },
    )
}

@Composable
private fun CloseDocumentDialog(doc: EditorDocument, onSave: () -> Unit, onDiscard: () -> Unit, onDismiss: () -> Unit) {
    val canSave = doc.source is DocumentSource.ProjectFile && !doc.readOnly
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Close ${doc.title}?") },
        text = {
            Text(
                if (canSave) "This file has unsaved changes." else "This scratch file has not been saved to a project. Closing it discards its contents.",
            )
        },
        confirmButton = {
            Row {
                TextButton(onClick = onDiscard) { Text("Discard", color = MaterialTheme.colorScheme.error) }
                if (canSave) TextButton(onClick = onSave) { Text("Save and close") }
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
