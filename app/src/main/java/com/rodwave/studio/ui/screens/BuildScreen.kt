@file:OptIn(ExperimentalLayoutApi::class)

package com.rodwave.studio.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Build
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.FileOpen
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.automirrored.outlined.ManageSearch
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rodwave.engine.analysis.HexDump
import com.rodwave.engine.analysis.ScriptVerdict
import com.rodwave.engine.decompiler.RoundTripStatus
import com.rodwave.engine.diagnostics.Severity
import com.rodwave.engine.project.Project
import com.rodwave.engine.scm.ScriptFormat
import com.rodwave.studio.core.BatchEntry
import com.rodwave.studio.core.DocumentSource
import com.rodwave.studio.core.InspectedFile
import com.rodwave.studio.core.Screen
import com.rodwave.studio.core.Studio
import com.rodwave.studio.ui.ScreenFrame
import com.rodwave.studio.ui.components.CodeBlock
import com.rodwave.studio.ui.components.DiagnosticRow
import com.rodwave.studio.ui.components.EmptyState
import com.rodwave.studio.ui.components.InfoBanner
import com.rodwave.studio.ui.components.KeyValue
import com.rodwave.studio.ui.components.SectionCard
import com.rodwave.studio.ui.components.SegmentedTabs
import com.rodwave.studio.ui.components.Tag
import com.rodwave.studio.ui.components.formatBytes
import com.rodwave.studio.ui.theme.CodeFont
import com.rodwave.studio.ui.theme.Palette

/** Largest prefix of a file shown in the hex view; the rest is summarised. */
private const val HEX_VIEW_LIMIT = 64 * 1024

@Composable
fun BuildScreen(studio: Studio) {
    ScreenFrame(studio, "Compiler & Decompiler", "${studio.database.info.name} ${studio.database.info.version} · ${studio.database.size} commands") {
        SegmentedTabs(
            listOf("Compile", "Decompile & inspect"),
            studio.buildTab,
            { studio.buildTab = it },
            Modifier.padding(horizontal = 16.dp, vertical = 4.dp).fillMaxWidth(),
        )
        if (studio.buildTab == 0) CompilePane(studio) else DecompilePane(studio)
    }
}

// ---------------------------------------------------------------------------------------- compile

@Composable
private fun CompilePane(studio: Studio) {
    var project by remember { mutableStateOf(studio.projectList.firstOrNull()) }
    var batch by remember { mutableStateOf<Pair<Boolean, List<BatchEntry>>?>(null) }
    val active = studio.editor.active?.takeIf { !it.readOnly && !it.isText }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            SectionCard(
                "Active document",
                icon = Icons.Outlined.Code,
                subtitle = active?.let { "${it.title} · ${(it.lastResult?.format ?: it.format).title}" } ?: "Open a script in the editor to compile it here",
            ) {
                val last = active?.lastResult
                if (last != null) {
                    val bytes = last.bytes
                    if (bytes != null) {
                        Text("Last build: ${bytes.size} bytes, ${last.instructionCount} instructions, ${last.warnings.size} warning(s); output validated.", style = MaterialTheme.typography.bodySmall, color = Palette.Green)
                    } else {
                        Text("Last build failed with ${last.errors.size} error(s).", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                    }
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilledTonalButton(enabled = active != null && studio.busy == null, onClick = {
                        active?.let { doc ->
                            if (doc.source is DocumentSource.ProjectFile && doc.isDirty) studio.editor.save(doc)
                            studio.compileDocument(doc) { r -> studio.notify(if (r.success) "Compiled ${doc.title}: ${r.bytes?.size} bytes" else "${r.errors.size} error(s) in ${doc.title}", isError = !r.success) }
                        }
                    }) { Text("Compile") }
                    OutlinedButton(onClick = { studio.navigate(Screen.EDITOR) }) { Text("Open editor") }
                }
            }
        }
        item {
            SectionCard(
                "Batch compile a project",
                icon = Icons.Outlined.Layers,
                subtitle = "Compiles the main file and every file with a {\$CLEO} directive. Other files count as includes.",
            ) {
                if (studio.projectList.isEmpty()) {
                    Text("No projects yet.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    studio.projectList.forEach { p ->
                        Row(
                            Modifier.fillMaxWidth().selectable(selected = p == project, onClick = { project = p; batch = null }).padding(vertical = 2.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = p == project, onClick = { project = p; batch = null })
                            Text(p.name, modifier = Modifier.weight(1f))
                            Tag(".${p.format.extension}", MaterialTheme.colorScheme.tertiary)
                        }
                    }
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilledTonalButton(enabled = project != null && studio.busy == null, onClick = {
                            project?.let { p -> studio.batchCompile(p, write = true) { batch = true to it } }
                        }) { Text("Compile all") }
                        OutlinedButton(enabled = project != null && studio.busy == null, onClick = {
                            project?.let { p -> studio.batchCompile(p, write = false) { batch = false to it } }
                        }) { Text("Validate only") }
                    }
                }
            }
        }
        batch?.let { (written, entries) ->
            item { BatchSummary(written, entries, project) }
            items(entries, key = { it.file }) { BatchEntryCard(it) }
        }
        item { TargetProfiles(studio) }
    }
}

@Composable
private fun BatchSummary(written: Boolean, entries: List<BatchEntry>, project: Project?) {
    val failed = entries.count { !it.result.success }
    when {
        entries.isEmpty() -> InfoBanner("No scripts found: the project has no main file or {\$CLEO} files.", color = Palette.Gold)
        failed == 0 -> InfoBanner(
            if (written) "All ${entries.size} script(s) compiled and validated; binaries were saved in ${project?.name ?: "the project"}." else "All ${entries.size} script(s) compile cleanly. Nothing was written.",
            color = Palette.Green,
            icon = Icons.Outlined.CheckCircle,
        )
        else -> InfoBanner("$failed of ${entries.size} script(s) failed. Failed scripts produce no output.", color = Palette.Red, icon = Icons.Outlined.ErrorOutline)
    }
}

@Composable
private fun BatchEntryCard(entry: BatchEntry) {
    val r = entry.result
    val bytes = r.bytes
    SectionCard(
        entry.file,
        icon = if (bytes != null) Icons.Outlined.CheckCircle else Icons.Outlined.ErrorOutline,
        accent = if (bytes != null) Palette.Green else MaterialTheme.colorScheme.error,
        subtitle = if (bytes != null) {
            "${bytes.size} bytes · ${r.instructionCount} instructions · ${r.format.title}" + (entry.output?.let { " → $it" } ?: "")
        } else {
            "${r.errors.size} error(s), ${r.warnings.size} warning(s)"
        },
    ) {
        entry.report?.let { report ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Tag(report.verdict.label, verdictColor(report.verdict))
            }
            report.findings.filter { it.severity != Severity.INFO }.take(4).forEach { f ->
                Text("• ${f.title}: ${f.detail}", style = MaterialTheme.typography.bodySmall, color = if (f.severity == Severity.ERROR) MaterialTheme.colorScheme.error else Palette.Gold)
            }
        }
        (r.errors + r.warnings).take(8).forEach { DiagnosticRow(it) }
    }
}

@Composable
private fun TargetProfiles(studio: Studio) {
    SectionCard("Target profiles", icon = Icons.Outlined.Tune, subtitle = "What each output format means and what the compiler checks") {
        listOf(ScriptFormat.CLEO_ANDROID_AUTO, ScriptFormat.CLEO_ANDROID_INVOKED, ScriptFormat.CLEO_PC, ScriptFormat.MAIN_SCM).forEach { f ->
            Column(Modifier.padding(vertical = 4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(f.title, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                    Tag(
                        when (f) {
                            ScriptFormat.MAIN_SCM -> "decompile only"
                            ScriptFormat.CLEO_PC -> "PC, not loaded on Android"
                            else -> "compile + decompile"
                        },
                        if (f.isCleoAndroid) Palette.Green else Palette.Gold,
                    )
                }
                Text(f.description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        InfoBanner(
            "Every GTA SA Android version shares the SA Mobile opcode table, so one compiler profile covers 1.00–2.x. " +
                "Memory addresses used with CLEO's 0DD8/0DD9 commands differ per version and ABI; the inspector flags them, but no tool can make them portable.",
        )
        KeyValue("Opcode table", "${studio.database.info.name} ${studio.database.info.version}")
        KeyValue("Commands", "${studio.database.size}")
        KeyValue("Origin", studio.database.info.origin.label)
    }
}

// ---------------------------------------------------------------------------------------- decompile

@Composable
private fun DecompilePane(studio: Studio) {
    val file = studio.inspected
    var view by remember(file) { mutableIntStateOf(0) }
    val pick = {
        studio.platform.pickFile(listOf("application/octet-stream", "*/*")) { picked -> picked?.let(studio::inspectFile) }
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            SectionCard(
                "Open a compiled script",
                icon = Icons.Outlined.FileOpen,
                subtitle = ".csa, .csi, .cs or main.scm. The file is analysed locally and never modified.",
            ) {
                FilledTonalButton(enabled = studio.busy == null, onClick = pick) { Text("Choose file…") }
            }
        }
        if (file == null) {
            item {
                EmptyState(
                    Icons.AutoMirrored.Outlined.ManageSearch,
                    "Nothing inspected yet",
                    "Rodwave decompiles the script, recompiles the listing and compares the bytes, so you can see whether the source reproduces the file exactly.",
                )
            }
            return@LazyColumn
        }
        item { InspectHeader(studio, file) }
        item {
            SegmentedTabs(listOf("Summary", "Source", "Hex", "Opcodes"), view, { view = it }, Modifier.fillMaxWidth())
        }
        when (view) {
            0 -> summaryItems(file)
            1 -> sourceItems(studio, file)
            2 -> hexItems(file)
            else -> opcodeItems(studio, file)
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
private fun InspectHeader(studio: Studio, file: InspectedFile) {
    val report = file.report
    SectionCard(
        file.name,
        icon = Icons.Outlined.Build,
        accent = verdictColor(report.verdict),
        subtitle = "${formatBytes(file.size.toLong())} · ${report.format?.title ?: "format from content"}",
        trailing = { Tag(report.verdict.label, verdictColor(report.verdict)) },
    ) {
        val decompiled = file.decompiled
        if (decompiled != null) RoundTripBanner(decompiled.roundTrip, decompiled.firstDifference)
        if (file.mainScm != null) {
            InfoBanner("main.scm listings are read-only: Rodwave does not compile main.scm, so the listing cannot be verified by recompiling.", color = Palette.Violet)
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (decompiled != null || file.mainScm != null) {
                FilledTonalButton(onClick = { studio.openDecompiledInEditor(file) }) { Text(if (file.mainScm != null) "Open listing" else "Open in editor") }
                OutlinedButton(onClick = {
                    val text = decompiled?.text ?: file.mainScm?.text.orEmpty()
                    studio.platform.saveDocument(file.name.substringBeforeLast('.') + ".txt", "text/plain", text.toByteArray()) { ok, _ ->
                        if (ok) studio.notify("Listing saved")
                    }
                }) { Text("Save listing") }
            }
            OutlinedButton(onClick = { studio.inspected = null }) { Text("Clear") }
        }
    }
}

@Composable
private fun RoundTripBanner(status: RoundTripStatus, firstDifference: Int?) {
    when (status) {
        RoundTripStatus.IDENTICAL -> InfoBanner(
            "Byte-exact round trip: recompiling the listing reproduces the file exactly.",
            color = Palette.Green,
            icon = Icons.Outlined.CheckCircle,
        )
        RoundTripStatus.DIFFERENT -> InfoBanner(
            "The listing recompiles, but the bytes differ" + (firstDifference?.let { " from offset 0x${it.toString(16).uppercase()}" } ?: "") +
                ". Treat the listing as a reading aid, not as the original source.",
            color = Palette.Gold,
        )
        RoundTripStatus.NOT_RECOMPILABLE -> InfoBanner(
            "The listing does not recompile; see the diagnostics. Unknown commands are kept as hex so nothing is lost.",
            color = Palette.Red,
            icon = Icons.Outlined.ErrorOutline,
        )
        RoundTripStatus.NOT_CHECKED -> InfoBanner("Round trip not checked.")
    }
}

private fun LazyListScope.summaryItems(file: InspectedFile) {
    val report = file.report
    item {
        SectionCard("Facts", icon = Icons.AutoMirrored.Outlined.ManageSearch) {
            report.scriptName?.let { KeyValue("Script name", it, mono = true) }
            KeyValue("Instructions", "${report.instructionCount}")
            KeyValue("Code coverage", "%.1f%%".format(report.coverage * 100))
            KeyValue("Data bytes", "${report.dataBytes}")
            KeyValue("Local variables", report.localVariables.sorted().take(24).joinToString(" ") { "$it@" }.ifEmpty { "none" }, mono = true)
            KeyValue("Global variables", "${report.globalVariables.size}")
            KeyValue("Touch input", if (report.usesTouch) "yes" else "no")
            KeyValue("CLEO menu", if (report.usesCleoMenu) "yes" else "no")
            KeyValue("Native memory", if (report.usesNativeMemory) "yes — version specific" else "no")
            if (report.cleoAndroidCommands.isNotEmpty()) {
                KeyValue("CLEO Android", report.cleoAndroidCommands.sorted().joinToString(" ") { it.toString(16).uppercase().padStart(4, '0') }, mono = true)
            }
            if (report.unknownOpcodes.isNotEmpty()) {
                KeyValue("Unknown opcodes", report.unknownOpcodes.sorted().joinToString(" ") { it.toString(16).uppercase().padStart(4, '0') }, mono = true)
            }
        }
    }
    file.mainScm?.header?.let { h ->
        item {
            SectionCard("main.scm header", icon = Icons.Outlined.Layers) {
                KeyValue("Segments", "${h.segments.size}")
                KeyValue("Target game", "'${h.targetGameChar}'" + if (h.isSanAndreasLayout) " (San Andreas layout)" else "")
                KeyValue("Global variable space", "${h.globalVariableSpace.last - h.globalVariableSpace.first + 1} bytes")
                KeyValue("Models", "${h.models.size}")
                h.mainScriptSize?.let { KeyValue("Main script size", "$it bytes") }
                KeyValue("Missions", "${h.missionCount}")
                h.exclusiveMissionCount?.let { KeyValue("Exclusive missions", "$it") }
                KeyValue("Streamed scripts", "${h.streamedScripts.size}")
                KeyValue("Code starts at", "0x${h.mainCodeStart.toString(16).uppercase()}", mono = true)
            }
        }
    }
    if (report.pcCommands.isNotEmpty()) {
        item {
            SectionCard("PC CLEO commands", icon = Icons.Outlined.ErrorOutline, accent = Palette.Red, subtitle = "These ids mean something else in the mobile game") {
                report.pcCommands.forEach { use ->
                    Text(
                        "${use.opcode.toString(16).uppercase().padStart(4, '0')} ${use.pcName}" + (use.mobileName?.let { " → mobile: $it" } ?: " → not defined on mobile"),
                        fontFamily = CodeFont,
                        fontSize = 12.sp,
                    )
                }
            }
        }
    }
    if (report.findings.isNotEmpty()) {
        item {
            SectionCard("Findings", icon = Icons.AutoMirrored.Outlined.ManageSearch) {
                report.findings.forEach { f ->
                    val color = when (f.severity) {
                        Severity.ERROR -> Palette.Red
                        Severity.WARNING -> Palette.Gold
                        Severity.INFO -> Palette.Sky
                    }
                    Column {
                        Text(f.title, style = MaterialTheme.typography.titleSmall, color = color)
                        Text(f.detail, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }
    val diagnostics = file.decompiled?.diagnostics ?: file.mainScm?.diagnostics.orEmpty()
    if (diagnostics.isNotEmpty()) {
        item {
            SectionCard("Decompiler messages", icon = Icons.Outlined.ErrorOutline) {
                diagnostics.take(60).forEach { DiagnosticRow(it) }
                if (diagnostics.size > 60) Text("…and ${diagnostics.size - 60} more", style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

private fun LazyListScope.sourceItems(studio: Studio, file: InspectedFile) {
    val text = file.decompiled?.text ?: file.mainScm?.text
    item {
        if (text == null) {
            InfoBanner("No listing: ${file.report.verdict.label}.", color = Palette.Gold)
        } else {
            val lines = text.lines()
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                CodeBlock(lines.take(400).joinToString("\n"))
                if (lines.size > 400) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Showing 400 of ${lines.size} lines.", style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                        OutlinedButton(onClick = { studio.openDecompiledInEditor(file) }) { Text("Open all") }
                    }
                }
            }
        }
    }
}

private fun LazyListScope.hexItems(file: InspectedFile) {
    val shown = minOf(file.size, HEX_VIEW_LIMIT)
    val rows = HexDump.rows(file.bytes, 0, shown)
    item {
        Text(
            "Offset    00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F",
            fontFamily = CodeFont,
            fontSize = 11.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
    items(rows) { row ->
        Text(row, fontFamily = CodeFont, fontSize = 11.sp, softWrap = false, maxLines = 1, overflow = TextOverflow.Clip)
    }
    if (file.size > shown) {
        item { Text("Showing the first ${formatBytes(shown.toLong())} of ${formatBytes(file.size.toLong())}.", style = MaterialTheme.typography.bodySmall) }
    }
}

private fun LazyListScope.opcodeItems(studio: Studio, file: InspectedFile) {
    val counts = file.report.opcodeCounts.entries.sortedByDescending { it.value }
    if (counts.isEmpty()) {
        item { InfoBanner("No instructions were decoded.") }
        return
    }
    item {
        Text("${counts.size} distinct commands, ${counts.sumOf { it.value }} uses", style = MaterialTheme.typography.titleSmall)
    }
    items(counts.take(300), key = { it.key }) { (id, n) ->
        val def = studio.database[id]
        Row(
            Modifier.fillMaxWidth().clickable { studio.navigate(Screen.OPCODES) }.padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(id.toString(16).uppercase().padStart(4, '0'), fontFamily = CodeFont, fontSize = 12.sp, color = Palette.Sunset)
            Spacer(Modifier.width(10.dp))
            Text(def?.keyword ?: "unknown", fontFamily = CodeFont, fontSize = 12.sp, modifier = Modifier.weight(1f), color = if (def == null) Palette.Red else Color.Unspecified)
            Tag("×$n", MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

fun verdictColor(verdict: ScriptVerdict): Color = when (verdict) {
    ScriptVerdict.READY -> Palette.Green
    ScriptVerdict.NEEDS_REVIEW -> Palette.Gold
    ScriptVerdict.PC_SCRIPT -> Palette.Red
    ScriptVerdict.MAIN_SCM -> Palette.Violet
    ScriptVerdict.NOT_A_SCRIPT -> Palette.Slate
}
