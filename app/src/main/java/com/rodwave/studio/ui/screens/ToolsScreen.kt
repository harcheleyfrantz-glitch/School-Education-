@file:OptIn(ExperimentalLayoutApi::class)

package com.rodwave.studio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.AccountTree
import androidx.compose.material.icons.outlined.Archive
import androidx.compose.material.icons.outlined.Build
import androidx.compose.material.icons.outlined.Difference
import androidx.compose.material.icons.automirrored.outlined.ManageSearch
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material.icons.automirrored.outlined.ViewQuilt
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rodwave.engine.analysis.BinaryInfo
import com.rodwave.engine.analysis.BinaryInspector
import com.rodwave.engine.analysis.BinaryKind
import com.rodwave.engine.analysis.HexDump
import com.rodwave.engine.editor.DiffOp
import com.rodwave.engine.editor.TextDiff
import com.rodwave.engine.project.Project
import com.rodwave.engine.project.ProjectTemplate
import com.rodwave.engine.project.RestorePlan
import com.rodwave.engine.project.Templates
import com.rodwave.studio.core.BatchEntry
import com.rodwave.studio.core.PickedFile
import com.rodwave.studio.core.Screen
import com.rodwave.studio.core.Studio
import com.rodwave.studio.ui.LocalWideLayout
import com.rodwave.studio.ui.ScreenFrame
import com.rodwave.studio.ui.components.BulletList
import com.rodwave.studio.ui.components.CodeBlock
import com.rodwave.studio.ui.components.ConfirmDialog
import com.rodwave.studio.ui.components.InfoBanner
import com.rodwave.studio.ui.components.KeyValue
import com.rodwave.studio.ui.components.SectionCard
import com.rodwave.studio.ui.components.Tag
import com.rodwave.studio.ui.components.formatBytes
import com.rodwave.studio.ui.theme.CodeFont
import com.rodwave.studio.ui.theme.Palette
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private enum class Tool(val title: String, val subtitle: String, val icon: ImageVector, val color: Color) {
    BINARY("Binary viewer", "Identify a file by content: ELF, ZIP, script", Icons.Outlined.Memory, Palette.Violet),
    DIFF("Diff", "Compare two documents or files", Icons.Outlined.Difference, Palette.Sky),
    DEPENDENCIES("Dependency analysis", "Includes, loaders and risky commands per script", Icons.Outlined.AccountTree, Palette.Teal),
    TEMPLATES("Templates & snippets", "Start points and reusable blocks", Icons.AutoMirrored.Outlined.ViewQuilt, Palette.Pink),
    BACKUP("Workspace backup", "Export or restore all projects as a ZIP", Icons.Outlined.Archive, Palette.Gold),
}

private data class Shortcut(val title: String, val subtitle: String, val icon: ImageVector, val color: Color, val action: (Studio) -> Unit)

private val SHORTCUTS = listOf(
    Shortcut("Script inspector", "Decompile and analyse", Icons.AutoMirrored.Outlined.ManageSearch, Palette.Sunset) { it.buildTab = 1; it.navigate(Screen.BUILD) },
    Shortcut("Batch compile", "Compile a whole project", Icons.Outlined.Build, Palette.Sunset) { it.buildTab = 0; it.navigate(Screen.BUILD) },
    Shortcut("Opcode browser", "Search every command", Icons.Outlined.Search, Palette.Sky) { it.navigate(Screen.OPCODES) },
    Shortcut("Compatibility report", "Export for troubleshooting", Icons.Outlined.VerifiedUser, Palette.Green) { it.navigate(Screen.COMPAT) },
    Shortcut("Console", "Every operation, logged", Icons.Outlined.Terminal, Palette.Slate) { it.navigate(Screen.CONSOLE) },
    Shortcut("Docs library", "Guides and references", Icons.AutoMirrored.Outlined.MenuBook, Palette.Lavender) { it.navigate(Screen.DOCS) },
)

@Composable
fun ToolsScreen(studio: Studio) {
    var tool by remember { mutableStateOf<Tool?>(null) }
    val current = tool
    ScreenFrame(
        studio,
        current?.title ?: "Tools",
        current?.subtitle ?: "Utilities for scripts, mods and your workspace",
        actions = {
            if (current != null) IconButton(onClick = { tool = null }) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "All tools") }
        },
    ) {
        when (current) {
            null -> ToolGrid(studio) { tool = it }
            Tool.BINARY -> BinaryViewer(studio)
            Tool.DIFF -> DiffTool(studio)
            Tool.DEPENDENCIES -> DependencyTool(studio)
            Tool.TEMPLATES -> TemplatesTool(studio)
            Tool.BACKUP -> BackupTool(studio)
        }
    }
}

@Composable
private fun ToolGrid(studio: Studio, onOpen: (Tool) -> Unit) {
    val perRow = if (LocalWideLayout.current) 3 else 2
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item { Text("Utilities", style = MaterialTheme.typography.titleMedium) }
        items(Tool.entries.chunked(perRow)) { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { t -> Tile(t.title, t.subtitle, t.icon, t.color, Modifier.weight(1f)) { onOpen(t) } }
                repeat(perRow - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        item { Text("Elsewhere in Rodwave", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp)) }
        items(SHORTCUTS.chunked(perRow)) { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { s -> Tile(s.title, s.subtitle, s.icon, s.color, Modifier.weight(1f)) { s.action(studio) } }
                repeat(perRow - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun Tile(title: String, subtitle: String, icon: ImageVector, color: Color, modifier: Modifier, onClick: () -> Unit) {
    Column(
        modifier
            .clip(RoundedCornerShape(20.dp))
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .clickable(onClick = onClick)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(Modifier.size(38.dp).clip(RoundedCornerShape(12.dp)).background(color.copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = color)
        }
        Text(title, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

// ---------------------------------------------------------------------------------------- binary viewer

@Composable
private fun BinaryViewer(studio: Studio) {
    var file by remember { mutableStateOf<PickedFile?>(null) }
    var info by remember { mutableStateOf<BinaryInfo?>(null) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            SectionCard("Choose a file", icon = Icons.Outlined.Memory, subtitle = "Read locally; nothing is executed, loaded or changed") {
                FilledTonalButton(enabled = studio.busy == null, onClick = {
                    studio.platform.pickFile(listOf("*/*")) { picked ->
                        picked ?: return@pickFile
                        studio.runTask("Inspecting ${picked.name}", "tools") {
                            val result = withContext(Dispatchers.Default) { BinaryInspector.inspect(picked.name, picked.bytes, studio.database) }
                            file = picked
                            info = result
                            studio.console.info("tools", "${picked.name}: ${result.kind.label}, ${result.size} bytes, sha256 ${result.sha256}")
                        }
                    }
                }) { Text("Choose file…") }
            }
        }
        val i = info
        val f = file
        if (i != null && f != null) {
            item {
                SectionCard(i.name, icon = Icons.Outlined.Memory, accent = Palette.Violet, subtitle = "${i.kind.label} · ${formatBytes(i.size.toLong())}") {
                    KeyValue("SHA-256", i.sha256, mono = true)
                    TextButton(onClick = { studio.platform.copyToClipboard("SHA-256", i.sha256); studio.notify("Hash copied") }) { Text("Copy hash") }
                    InfoBanner("Identified from the file's content. The file name and extension were not used.")
                }
            }
            binaryDetails(studio, f, i)
            item {
                SectionCard("First bytes", icon = Icons.Outlined.Memory) {
                    HexDump.rows(f.bytes, 0, 256).forEach { Text(it, fontFamily = CodeFont, fontSize = 10.sp, softWrap = false, maxLines = 1) }
                }
            }
        }
    }
}

private fun LazyListScope.binaryDetails(studio: Studio, file: PickedFile, info: BinaryInfo) {
    when (info.kind) {
        BinaryKind.ELF -> info.native?.let { n ->
            item {
                SectionCard("Native library", icon = Icons.Outlined.Memory, accent = if (n.isAmlMod) Palette.Green else Palette.Gold) {
                    KeyValue("ABI", n.abi?.androidName ?: "unknown machine")
                    KeyValue("Loadable by AML", if (n.isLoaderCompatibleAbi) "ABI yes (ARM)" else "no — AML runs only on ARM builds of the game")
                    KeyValue("Shared object", if (n.isSharedObject) "yes" else "no")
                    KeyValue("AML mod", if (n.isAmlMod) "yes — exports __GetModInfo" else "no — does not export __GetModInfo")
                    if (n.amlCallbacks.isNotEmpty()) KeyValue("AML callbacks", n.amlCallbacks.joinToString())
                    KeyValue("Dependency list", if (n.declaresDependencies) "exports __GetDepsList (read by AML at run time)" else "none declared")
                    KeyValue("Game restriction", if (n.restrictsGame) "exports __INeedASpecificGame" else "none")
                    if (n.neededLibraries.isNotEmpty()) KeyValue("Links against", n.neededLibraries.joinToString(), mono = true)
                    if (n.guidCandidates.isNotEmpty()) {
                        KeyValue("GUID-like strings", n.guidCandidates.take(10).joinToString(), mono = true)
                        Text("Heuristic: these may be the mod's own GUID or ones it depends on.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    n.error?.let { Text(it, color = Palette.Red, style = MaterialTheme.typography.bodySmall) }
                }
            }
        }
        BinaryKind.ZIP -> item {
            val archive = info.archive
            SectionCard("Archive", icon = Icons.Outlined.Archive, accent = if (archive != null) Palette.Gold else Palette.Red, subtitle = archive?.let { "${it.files.size} files, ${it.rejected.size} rejected" }) {
                info.archiveError?.let { InfoBanner(it, color = Palette.Red) }
                archive?.files?.take(200)?.forEach { e ->
                    Row {
                        Text(e.path, fontFamily = CodeFont, fontSize = 12.sp, modifier = Modifier.weight(1f))
                        Text(formatBytes(e.data.size.toLong()), style = MaterialTheme.typography.labelSmall)
                    }
                }
                if (!archive?.rejected.isNullOrEmpty()) {
                    Text("Rejected entries (never extracted)", style = MaterialTheme.typography.titleSmall, color = Palette.Red)
                    archive!!.rejected.forEach { r -> Text("${r.path} — ${r.reason}", fontFamily = CodeFont, fontSize = 12.sp, color = Palette.Red) }
                }
                if (archive != null) {
                    OutlinedButton(onClick = { studio.importMod(file); studio.navigate(Screen.MODS) }) { Text("Import into Mod Manager") }
                }
            }
        }
        BinaryKind.SCRIPT, BinaryKind.MAIN_SCM -> info.script?.let { r ->
            item {
                SectionCard(if (info.kind == BinaryKind.MAIN_SCM) "main.scm" else "Compiled script", icon = Icons.AutoMirrored.Outlined.ManageSearch, accent = verdictColor(r.verdict)) {
                    Tag(r.verdict.label, verdictColor(r.verdict))
                    KeyValue("Instructions", "${r.instructionCount}")
                    KeyValue("Coverage", "%.1f%%".format(r.coverage * 100))
                    FilledTonalButton(onClick = { studio.inspectFile(file); studio.navigate(Screen.BUILD) }) { Text("Open in script inspector") }
                }
            }
        }
        BinaryKind.TEXT -> item {
            SectionCard("Text", icon = Icons.AutoMirrored.Outlined.ManageSearch) {
                KeyValue("Lines", "${info.textLines}")
                OutlinedButton(onClick = {
                    studio.editor.openText(file.name, file.bytes.toString(Charsets.UTF_8))
                    studio.navigate(Screen.EDITOR)
                }) { Text("Open in editor") }
            }
        }
        BinaryKind.UNKNOWN -> item {
            InfoBanner("Rodwave does not recognise this data: it is not an ELF library, ZIP archive, main.scm, text, or a script made of known commands.", color = Palette.Gold)
        }
    }
}

// ---------------------------------------------------------------------------------------- diff

private sealed interface DiffSource {
    val label: String
    val text: String

    class Document(override val label: String, override val text: String) : DiffSource
    class File(override val label: String, override val text: String) : DiffSource
}

@Composable
private fun DiffTool(studio: Studio) {
    var left by remember { mutableStateOf<DiffSource?>(null) }
    var right by remember { mutableStateOf<DiffSource?>(null) }
    val l = left
    val r = right
    val diff = remember(l, r) { if (l == null || r == null) null else TextDiff.diff(l.text, r.text) }
    val unified = remember(l, r) { if (l == null || r == null) emptyList() else TextDiff.unified(l.text, r.text, l.label, r.label).lines().take(3000) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            SectionCard("Compare", icon = Icons.Outlined.Difference, subtitle = "Line-by-line difference of two texts") {
                DiffSourcePicker(studio, "Original", left) { left = it }
                DiffSourcePicker(studio, "Changed", right) { right = it }
            }
        }
        if (diff != null) {
            val added = diff.count { it.op == DiffOp.INSERT }
            val removed = diff.count { it.op == DiffOp.DELETE }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Tag("+$added", Palette.Green)
                    Tag("−$removed", Palette.Red)
                    Text(if (added == 0 && removed == 0) "The texts are identical" else "${diff.size} lines", style = MaterialTheme.typography.bodySmall)
                }
            }
            items(unified) { line ->
                val color = when {
                    line.startsWith("+++") || line.startsWith("---") -> MaterialTheme.colorScheme.onSurfaceVariant
                    line.startsWith("@@") -> Palette.Violet
                    line.startsWith("+") -> Palette.Green
                    line.startsWith("-") -> Palette.Red
                    else -> MaterialTheme.colorScheme.onSurface
                }
                Text(line, fontFamily = CodeFont, fontSize = 12.sp, color = color, softWrap = false, maxLines = 1)
            }
        }
    }
}

@Composable
private fun DiffSourcePicker(studio: Studio, label: String, current: DiffSource?, onPick: (DiffSource) -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(current?.label ?: "Not chosen", style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Box {
            OutlinedButton(onClick = { menu = true }) { Text("Choose") }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                studio.editor.documents.forEach { d ->
                    DropdownMenuItem(text = { Text("${d.title} (editor)") }, onClick = { menu = false; onPick(DiffSource.Document(d.title, d.text)) })
                    if (d.isDirty) {
                        DropdownMenuItem(text = { Text("${d.title} (last saved)") }, onClick = { menu = false; onPick(DiffSource.Document("${d.title} (saved)", d.savedText)) })
                    }
                }
                DropdownMenuItem(text = { Text("Pick a file…") }, onClick = {
                    menu = false
                    studio.platform.pickFile(listOf("text/plain", "*/*")) { f ->
                        if (f != null) {
                            if (BinaryInspector.inspect(f.name, f.bytes, studio.database).kind != BinaryKind.TEXT) {
                                studio.notify("${f.name} is not a text file; decompile scripts first", isError = true)
                            } else {
                                onPick(DiffSource.File(f.name, f.bytes.toString(Charsets.UTF_8)))
                            }
                        }
                    }
                })
            }
        }
    }
}

// ---------------------------------------------------------------------------------------- dependencies

@Composable
private fun DependencyTool(studio: Studio) {
    var project by remember { mutableStateOf<Project?>(studio.projectList.firstOrNull()) }
    var entries by remember { mutableStateOf<List<BatchEntry>?>(null) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            SectionCard("Project", icon = Icons.Outlined.AccountTree, subtitle = "Compiles every script without writing files, then analyses the output") {
                if (studio.projectList.isEmpty()) Text("No projects yet.", style = MaterialTheme.typography.bodySmall)
                studio.projectList.forEach { p ->
                    Row(
                        Modifier.fillMaxWidth().selectable(selected = p == project, onClick = { project = p; entries = null }),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(selected = p == project, onClick = { project = p; entries = null })
                        Text(p.name)
                    }
                }
                FilledTonalButton(enabled = project != null && studio.busy == null, onClick = {
                    project?.let { p -> studio.batchCompile(p, write = false) { entries = it } }
                }) { Text("Analyse") }
            }
        }
        entries?.let { list ->
            item { DependencySummary(list) }
            items(list, key = { it.file }) { e -> DependencyCard(e) }
        }
    }
}

@Composable
private fun DependencySummary(entries: List<BatchEntry>) {
    val reports = entries.mapNotNull { it.report }
    val needs = buildList {
        if (entries.isNotEmpty()) add("A CLEO Android loader (CLEO standalone or the CLEO library for AML) — every script needs one.")
        reports.count { it.cleoAndroidCommands.isNotEmpty() }.takeIf { it > 0 }?.let { add("$it script(s) use CLEO Android extension commands (0DD0–0DF3).") }
        reports.count { it.usesTouch }.takeIf { it > 0 }?.let { add("$it script(s) read touch input.") }
        reports.count { it.usesCleoMenu }.takeIf { it > 0 }?.let { add("$it script(s) use the CLEO menu.") }
    }
    val risks = buildList {
        reports.count { it.usesNativeMemory }.takeIf { it > 0 }?.let { add("$it script(s) access game memory directly; addresses differ per game version and ABI.") }
        reports.count { it.pcCommands.isNotEmpty() }.takeIf { it > 0 }?.let { add("$it script(s) use PC CLEO opcode ids that mean other commands on mobile.") }
        reports.count { it.unknownOpcodes.isNotEmpty() }.takeIf { it > 0 }?.let { add("$it script(s) use commands the opcode library does not define.") }
        entries.count { !it.result.success }.takeIf { it > 0 }?.let { add("$it script(s) do not compile.") }
        entries.flatMap { it.includes }.filter { !it.second }.map { it.first }.distinct().takeIf { it.isNotEmpty() }?.let { add("Missing includes: ${it.joinToString()}") }
    }
    SectionCard("Summary", icon = Icons.Outlined.AccountTree, subtitle = "${entries.size} script(s) analysed") {
        if (needs.isNotEmpty()) {
            Text("Requires", style = MaterialTheme.typography.titleSmall)
            BulletList(needs)
        }
        if (risks.isNotEmpty()) {
            Text("Risks", style = MaterialTheme.typography.titleSmall, color = Palette.Gold)
            BulletList(risks, color = Palette.Gold)
        } else if (entries.isNotEmpty()) {
            Text("No risky commands found.", style = MaterialTheme.typography.bodySmall, color = Palette.Green)
        }
        Text(
            "This is static analysis of compiled bytes; it cannot tell whether a script works in the game.",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun DependencyCard(entry: BatchEntry) {
    val r = entry.report
    SectionCard(
        entry.file,
        icon = Icons.Outlined.Build,
        accent = if (entry.result.success) Palette.Green else Palette.Red,
        subtitle = if (entry.result.success) "${entry.result.instructionCount} instructions" else "${entry.result.errors.size} error(s)",
        trailing = { r?.let { Tag(it.verdict.label.substringBefore(" —"), verdictColor(it.verdict)) } },
    ) {
        if (entry.includes.isNotEmpty()) {
            Text("Includes", style = MaterialTheme.typography.titleSmall)
            entry.includes.forEach { (path, found) ->
                Row {
                    Text(path, fontFamily = CodeFont, fontSize = 12.sp, modifier = Modifier.weight(1f))
                    Tag(if (found) "found" else "missing", if (found) Palette.Green else Palette.Red)
                }
            }
        }
        if (r != null) {
            val features = listOfNotNull(
                if (r.cleoAndroidCommands.isNotEmpty()) "CLEO Android commands: " + r.cleoAndroidCommands.sorted().joinToString(" ") { it.toString(16).uppercase().padStart(4, '0') } else null,
                if (r.usesTouch) "Touch input" else null,
                if (r.usesCleoMenu) "CLEO menu" else null,
                if (r.usesNativeMemory) "Direct memory access (version specific)" else null,
                if (r.pcCommands.isNotEmpty()) "PC CLEO ids: " + r.pcCommands.joinToString { it.pcName } else null,
                if (r.unknownOpcodes.isNotEmpty()) "Unknown: " + r.unknownOpcodes.sorted().joinToString(" ") { it.toString(16).uppercase().padStart(4, '0') } else null,
            )
            if (features.isNotEmpty()) BulletList(features)
        }
        entry.result.errors.take(3).forEach { Text(it.render(), style = MaterialTheme.typography.bodySmall, color = Palette.Red) }
    }
}

// ---------------------------------------------------------------------------------------- templates

@Composable
private fun TemplatesTool(studio: Studio) {
    var creating by remember { mutableStateOf<ProjectTemplate?>(null) }
    val active = studio.editor.active?.takeIf { !it.readOnly && !it.isText }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { Text("Project templates", style = MaterialTheme.typography.titleMedium) }
        items(Templates.ALL, key = { it.id }) { t ->
            SectionCard(t.title, icon = Icons.AutoMirrored.Outlined.ViewQuilt, accent = Palette.Pink, subtitle = t.description, trailing = { Tag(".${t.format.extension}", MaterialTheme.colorScheme.tertiary) }) {
                CodeBlock(t.source("Example").lines().take(8).joinToString("\n"))
                FilledTonalButton(onClick = { creating = t }) { Text("Create project") }
            }
        }
        item { Text("Snippets", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp)) }
        items(Templates.SNIPPETS, key = { it.id }) { s ->
            SectionCard(s.title, subtitle = s.description) {
                CodeBlock(s.body)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { studio.platform.copyToClipboard(s.title, s.body); studio.notify("Snippet copied") }) { Text("Copy") }
                    OutlinedButton(enabled = active != null, onClick = {
                        active?.let { doc ->
                            val sel = doc.value.selection
                            studio.editor.replaceRange(doc, sel.min, sel.max, s.body)
                            studio.navigate(Screen.EDITOR)
                        }
                    }) { Text("Insert into ${active?.title ?: "editor"}") }
                }
            }
        }
        item {
            Text(
                "Templates and snippets are original to Rodwave and compile with the built-in opcode set. They have not been tested in the game.",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    creating?.let { t -> NewProjectDialog(studio, initialTemplate = t) { creating = null } }
}

// ---------------------------------------------------------------------------------------- backup

@Composable
private fun BackupTool(studio: Studio) {
    var plan by remember { mutableStateOf<RestorePlan?>(null) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            SectionCard("Export", icon = Icons.Outlined.Archive, accent = Palette.Gold, subtitle = "${studio.projectList.size} project(s) in one ZIP, saved where you choose") {
                FilledTonalButton(enabled = studio.busy == null && studio.projectList.isNotEmpty(), onClick = { studio.exportWorkspace() }) { Text("Create backup…") }
            }
        }
        item {
            SectionCard("Restore", icon = Icons.Outlined.Archive, subtitle = "Shows what would change before writing anything") {
                OutlinedButton(enabled = studio.busy == null, onClick = {
                    studio.platform.pickFile(listOf("application/zip", "*/*")) { f -> f?.let { studio.planWorkspaceRestore(it) { p -> plan = p } } }
                }) { Text("Choose backup…") }
            }
        }
        item {
            InfoBanner(
                "Backups contain your projects only. Managed mods, backups of replaced game files and settings stay in Rodwave's private storage. " +
                    "Entries with unsafe paths (\"..\", absolute paths) are rejected and never written.",
            )
        }
    }
    plan?.let { p -> RestoreDialog(studio, p) { plan = null } }
}

@Composable
private fun RestoreDialog(studio: Studio, plan: RestorePlan, onDismiss: () -> Unit) {
    var overwrite by remember { mutableStateOf(false) }
    ConfirmDialog(
        title = "Restore ${plan.files.size} file(s)?",
        message = "${plan.newFiles.size} new file(s), ${plan.conflicts.size} already exist, ${plan.rejected.size} rejected.",
        confirmLabel = if (overwrite) "Restore and replace" else "Restore",
        destructive = overwrite,
        onConfirm = { studio.restoreWorkspace(plan, overwrite); onDismiss() },
        onDismiss = onDismiss,
    ) {
        if (plan.conflicts.isNotEmpty()) {
            Text("Existing files", style = MaterialTheme.typography.titleSmall)
            plan.conflicts.take(12).forEach { Text(it, fontFamily = CodeFont, fontSize = 12.sp) }
            if (plan.conflicts.size > 12) Text("…and ${plan.conflicts.size - 12} more", style = MaterialTheme.typography.labelSmall)
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clickable { overwrite = !overwrite }) {
                Checkbox(checked = overwrite, onCheckedChange = { overwrite = it })
                Text("Replace existing files with the backup's version", style = MaterialTheme.typography.bodySmall)
            }
            if (!overwrite) Text("Existing files are kept; only new files are written.", style = MaterialTheme.typography.labelSmall, color = Palette.Teal)
        }
        if (plan.rejected.isNotEmpty()) {
            Text("Rejected", style = MaterialTheme.typography.titleSmall, color = Palette.Red)
            plan.rejected.take(8).forEach { Text(it, fontFamily = CodeFont, fontSize = 12.sp, color = Palette.Red) }
        }
    }
}
