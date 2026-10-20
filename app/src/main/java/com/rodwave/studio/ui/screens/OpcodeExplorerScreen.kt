@file:OptIn(ExperimentalLayoutApi::class)

package com.rodwave.studio.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.automirrored.outlined.LibraryBooks
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rodwave.engine.opcode.CoreOpcodes
import com.rodwave.engine.opcode.DatabaseOrigin
import com.rodwave.engine.opcode.EnumDefinition
import com.rodwave.engine.opcode.OpcodeDefinition
import com.rodwave.engine.opcode.ParamSource
import com.rodwave.engine.opcode.SannyLibraryImporter
import com.rodwave.studio.core.Screen
import com.rodwave.studio.core.Studio
import com.rodwave.studio.ui.ScreenFrame
import com.rodwave.studio.ui.components.BulletList
import com.rodwave.studio.ui.components.ConfirmDialog
import com.rodwave.studio.ui.components.FilterPill
import com.rodwave.studio.ui.components.InfoBanner
import com.rodwave.studio.ui.components.KeyValue
import com.rodwave.studio.ui.components.SearchField
import com.rodwave.studio.ui.components.SectionCard
import com.rodwave.studio.ui.components.SegmentedTabs
import com.rodwave.studio.ui.components.Tag
import com.rodwave.studio.ui.theme.CodeFont
import com.rodwave.studio.ui.theme.Palette

private const val MAX_RESULTS = 400

@Composable
fun OpcodeExplorerScreen(studio: Studio) {
    var tab by remember { mutableIntStateOf(0) }
    var query by remember { mutableStateOf("") }
    var extension by remember { mutableStateOf<String?>(null) }
    var conditionsOnly by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<OpcodeDefinition?>(null) }
    var confirmDownload by remember { mutableStateOf(false) }
    var confirmRemove by remember { mutableStateOf(false) }
    val db = studio.database
    val results = remember(db, query, extension, conditionsOnly) {
        db.search(query, limit = MAX_RESULTS, extension = extension, conditionsOnly = conditionsOnly)
    }
    val enums = remember(db, query) {
        val q = query.trim().lowercase()
        db.enums.filter { e -> q.isEmpty() || e.name.lowercase().contains(q) || e.members.keys.any { it.lowercase().contains(q) } }
    }
    ScreenFrame(studio, "Opcode Explorer", "${db.size} commands · ${db.enums.size} enums · ${db.info.origin.label}") {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item { LibraryManager(studio, onDownload = { confirmDownload = true }, onRemove = { confirmRemove = true }) }
            item { SearchField(query, { query = it }, "Hex id, name, Class.member or description") }
            item { SegmentedTabs(listOf("Commands", "Enums"), tab, { tab = it }, Modifier.fillMaxWidth()) }
            if (tab == 0) {
                item {
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilterPill("All", extension == null) { extension = null }
                        db.extensions.forEach { ext -> FilterPill(ext, extension == ext) { extension = if (extension == ext) null else ext } }
                        FilterPill("Conditions", conditionsOnly, Palette.Teal) { conditionsOnly = !conditionsOnly }
                    }
                }
                item {
                    Text(
                        if (results.size >= MAX_RESULTS) "First $MAX_RESULTS matches" else "${results.size} match(es)",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                items(results, key = { it.id }) { def -> OpcodeRow(def) { selected = def } }
            } else {
                items(enums, key = { it.name }) { e -> EnumCard(e, query) }
            }
        }
    }
    selected?.let { def -> OpcodeDetail(studio, def, onDismiss = { selected = null }) }
    if (confirmDownload) {
        ConfirmDialog(
            title = "Download the Sanny Builder Library?",
            message = "Rodwave will fetch sa_mobile.json and enums.json over HTTPS from the official repository:\n${SannyLibraryImporter.SA_MOBILE_JSON_URL}\n\n" +
                "The files are checked (they must describe sa_mobile) and stored only on this device. The library's repository states no licence, so Rodwave does not ship it; the download is for your own use.",
            confirmLabel = "Download",
            onConfirm = { studio.downloadLibrary(); confirmDownload = false },
            onDismiss = { confirmDownload = false },
        )
    }
    if (confirmRemove) {
        ConfirmDialog(
            title = "Remove the imported library?",
            message = "Rodwave goes back to the built-in core set. Scripts that use other commands will no longer compile until you import the library again.",
            confirmLabel = "Remove",
            destructive = true,
            onConfirm = { studio.removeLibrary(); confirmRemove = false },
            onDismiss = { confirmRemove = false },
        )
    }
}

@Composable
private fun LibraryManager(studio: Studio, onDownload: () -> Unit, onRemove: () -> Unit) {
    val state = studio.libraryState
    val info = state.database.info
    SectionCard(
        "Opcode library",
        icon = Icons.AutoMirrored.Outlined.LibraryBooks,
        accent = if (info.origin == DatabaseOrigin.BUILT_IN) Palette.Gold else Palette.Green,
        subtitle = state.message,
    ) {
        KeyValue("Active", "${info.name} ${info.version}")
        KeyValue("Game", info.game)
        state.imported?.let { KeyValue("Imported file", "${it.info.name} ${it.info.version} · ${it.size} commands") }
        if (info.importWarnings.isNotEmpty()) {
            Text("${info.importWarnings.size} import warning(s)", style = MaterialTheme.typography.bodySmall, color = Palette.Gold)
            BulletList(info.importWarnings.take(5), color = Palette.Gold)
        }
        if (state.imported != null) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Use the imported library", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                Switch(checked = studio.settings.useImportedLibrary, onCheckedChange = { studio.setUseImportedLibrary(it) })
            }
        } else {
            InfoBanner(
                "The built-in core set (${CoreOpcodes.database.size} commands) is checked against the Sanny Builder Library by Rodwave's test suite. Import the full " +
                    "library for every SA Mobile command and enum: get sa_mobile.json and enums.json from github.com/sannybuilder/library, or let Rodwave download them.",
            )
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            FilledTonalButton(enabled = studio.busy == null, onClick = onDownload) { Text("Download…") }
            OutlinedButton(onClick = { studio.platform.pickFile(listOf("application/json", "*/*")) { f -> f?.let(studio::importLibraryFile) } }) { Text("Import sa_mobile.json") }
            if (state.imported != null) {
                OutlinedButton(onClick = { studio.platform.pickFile(listOf("application/json", "*/*")) { f -> f?.let(studio::importEnumsFile) } }) { Text("Import enums.json") }
                TextButton(onClick = onRemove) { Text("Remove", color = MaterialTheme.colorScheme.error) }
            }
        }
    }
}

@Composable
private fun OpcodeRow(def: OpcodeDefinition, onClick: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 4.dp, vertical = 6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(def.hexId, fontFamily = CodeFont, fontSize = 13.sp, color = Palette.Sunset)
            Spacer(Modifier.width(10.dp))
            Text(def.keyword, fontFamily = CodeFont, fontSize = 13.sp, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (def.isCondition) Tag("condition", Palette.Teal)
            if (def.extension != OpcodeDefinition.EXTENSION_DEFAULT) Tag(def.extension, Palette.Violet, Modifier.padding(start = 4.dp))
            if (def.isUnsupported) Tag("unsupported", Palette.Red, Modifier.padding(start = 4.dp))
        }
        if (def.description.isNotBlank()) {
            Text(def.description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun OpcodeDetail(studio: Studio, def: OpcodeDefinition, onDismiss: () -> Unit) {
    val active = studio.editor.active?.takeIf { !it.readOnly && !it.isText }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("${def.hexId}: ${def.keyword}", fontFamily = CodeFont) },
        text = {
            Column(Modifier.heightIn(max = 520.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (def.description.isNotBlank()) Text(def.description, style = MaterialTheme.typography.bodyMedium)
                Text(def.signature, fontFamily = CodeFont, fontSize = 12.sp, color = Palette.Teal)
                if (def.params.isEmpty()) {
                    Text("No parameters.", style = MaterialTheme.typography.bodySmall)
                } else {
                    Text("Parameters (in bytecode order)", style = MaterialTheme.typography.titleSmall)
                    def.params.forEachIndexed { i, p ->
                        Row(verticalAlignment = Alignment.Top) {
                            Text("${i + 1}", fontFamily = CodeFont, fontSize = 12.sp, modifier = Modifier.width(22.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Column(Modifier.weight(1f)) {
                                Text(p.displayName, fontFamily = CodeFont, fontSize = 13.sp)
                                Text(
                                    listOfNotNull(
                                        p.typeName,
                                        if (p.isOutput) "output" else "input",
                                        when (p.source) {
                                            ParamSource.ANY -> null
                                            ParamSource.VAR_ANY -> "variable"
                                            ParamSource.VAR_GLOBAL -> "global variable"
                                            ParamSource.VAR_LOCAL -> "local variable"
                                            ParamSource.LITERAL -> "literal only"
                                        },
                                    ).joinToString(" · "),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
                val facts = listOfNotNull(
                    def.className?.let { "Class: $it${def.member?.let { m -> ".$m" } ?: ""}" },
                    def.operator?.let { "Operator: $it" },
                    "Extension: ${def.extension}",
                    if (def.isCondition) "Can be used as a condition" else null,
                    if (def.isBranch) "Changes control flow" else null,
                    if (def.isVariadic) "Takes a variable argument list" else null,
                    if (def.isConstructor) "Creates an entity" else null,
                    if (def.isDestructor) "Releases an entity" else null,
                    if (def.isUnsupported) "Marked unsupported in this game" else null,
                    if (def.platforms.isNotEmpty()) "Platforms: ${def.platforms.joinToString()}" else null,
                )
                BulletList(facts, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        confirmButton = {
            Row {
                TextButton(onClick = {
                    studio.platform.copyToClipboard(def.hexId, "${def.hexId}: ${def.keyword}")
                    studio.notify("Copied ${def.hexId}")
                }) { Text("Copy") }
                TextButton(enabled = active != null, onClick = {
                    active?.let { doc ->
                        val sel = doc.value.selection
                        studio.editor.replaceRange(doc, sel.min, sel.max, "${def.hexId}: ${def.keyword} ")
                        studio.navigate(Screen.EDITOR)
                    }
                    onDismiss()
                }) { Text("Insert") }
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Close") } },
    )
}

@Composable
private fun EnumCard(e: EnumDefinition, query: String) {
    var expanded by remember { mutableStateOf(false) }
    val q = query.trim().lowercase()
    val members = e.members.entries.toList()
    val shown = if (expanded) members else members.filter { q.isNotEmpty() && it.key.lowercase().contains(q) }.ifEmpty { members.take(6) }
    SectionCard(e.name, modifier = Modifier.clickable { expanded = !expanded }, subtitle = "${members.size} members") {
        shown.forEach { (k, v) ->
            Row {
                Text("${e.name}.$k", fontFamily = CodeFont, fontSize = 12.sp, modifier = Modifier.weight(1f))
                Text("$v", fontFamily = CodeFont, fontSize = 12.sp, color = Palette.Gold)
            }
        }
        if (!expanded && members.size > shown.size) Text("Tap to show all", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
    }
}
