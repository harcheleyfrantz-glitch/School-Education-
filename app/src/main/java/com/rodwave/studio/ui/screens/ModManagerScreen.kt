@file:OptIn(ExperimentalLayoutApi::class)

package com.rodwave.studio.ui.screens

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Extension
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.unit.dp
import com.rodwave.engine.mods.ActionType
import com.rodwave.engine.mods.DestinationKind
import com.rodwave.engine.mods.ImportResult
import com.rodwave.engine.mods.InstallPlan
import com.rodwave.engine.mods.ManagedMod
import com.rodwave.engine.mods.ModKind
import com.rodwave.engine.mods.OperationRecord
import com.rodwave.engine.mods.OperationStatus
import com.rodwave.engine.mods.OperationType
import com.rodwave.studio.core.Studio
import com.rodwave.studio.ui.ScreenFrame
import com.rodwave.studio.ui.components.BulletList
import com.rodwave.studio.ui.components.ConfirmDialog
import com.rodwave.studio.ui.components.EmptyState
import com.rodwave.studio.ui.components.FilterPill
import com.rodwave.studio.ui.components.InfoBanner
import com.rodwave.studio.ui.components.KeyValue
import com.rodwave.studio.ui.components.SearchField
import com.rodwave.studio.ui.components.SectionCard
import com.rodwave.studio.ui.components.SegmentedTabs
import com.rodwave.studio.ui.components.Tag
import com.rodwave.studio.ui.components.formatBytes
import com.rodwave.studio.ui.theme.CodeFont
import com.rodwave.studio.ui.theme.Palette

/** A dry run being shown to the user, or the mod whose plan is being computed. */
private sealed interface PlanState {
    data class Loading(val mod: ManagedMod, val install: Boolean) : PlanState
    data class Ready(val plan: InstallPlan) : PlanState
}

@Composable
fun ModManagerScreen(studio: Studio) {
    var tab by remember { mutableIntStateOf(0) }
    var query by remember { mutableStateOf("") }
    var kind by remember { mutableStateOf<ModKind?>(null) }
    var imported by remember { mutableStateOf<ImportResult?>(null) }
    var plan by remember { mutableStateOf<PlanState?>(null) }
    var removing by remember { mutableStateOf<ManagedMod?>(null) }
    var restoring by remember { mutableStateOf<OperationRecord?>(null) }
    var categoryFor by remember { mutableStateOf<ManagedMod?>(null) }

    // Plans are computed off the main thread; the dialog opens when one is ready.
    (plan as? PlanState.Loading)?.let { loading ->
        LaunchedEffect(loading) {
            val result = runCatching { if (loading.install) studio.planInstall(loading.mod) else studio.planUninstall(loading.mod) }
            plan = result.getOrNull()?.let { PlanState.Ready(it) }
            result.exceptionOrNull()?.let { studio.notify("Could not plan the change: ${it.message}", isError = true) }
        }
    }

    val enabledCount = studio.mods.count { it.enabled }
    ScreenFrame(studio, "Mod Manager", "${studio.mods.size} in library · $enabledCount installed") {
        SegmentedTabs(listOf("Library", "History (${studio.operations.size})"), tab, { tab = it }, Modifier.padding(horizontal = 16.dp, vertical = 4.dp).fillMaxWidth())
        Box(Modifier.weight(1f)) {
            if (tab == 0) {
                LibraryPane(
                    studio, query, { query = it }, kind, { kind = it },
                    onInstall = { plan = PlanState.Loading(it, install = true) },
                    onUninstall = { plan = PlanState.Loading(it, install = false) },
                    onRemove = { removing = it },
                    onCategory = { categoryFor = it },
                )
                ExtendedFloatingActionButton(
                    onClick = {
                        studio.platform.pickFile(listOf("application/zip", "application/octet-stream", "*/*")) { f ->
                            f?.let { studio.importMod(it) { r -> imported = r } }
                        }
                    },
                    icon = { Icon(Icons.Outlined.Add, null) },
                    text = { Text("Import") },
                    modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp),
                )
            } else {
                HistoryPane(studio, onRestore = { restoring = it })
            }
        }
    }

    imported?.let { r -> ImportResultDialog(r) { imported = null } }
    (plan as? PlanState.Ready)?.let { ready ->
        PlanDialog(
            studio, ready.plan,
            onApply = { confirmed -> studio.applyPlan(ready.plan, confirmed); plan = null },
            onDismiss = { plan = null },
        )
    }
    removing?.let { mod ->
        ConfirmDialog(
            title = "Remove '${mod.name}' from the library?",
            message = "Rodwave deletes its stored copy of this mod. Nothing is installed, so no game folder is touched.",
            confirmLabel = "Remove",
            destructive = true,
            onConfirm = { studio.removeMod(mod); removing = null },
            onDismiss = { removing = null },
        )
    }
    restoring?.let { op ->
        ConfirmDialog(
            title = "Restore backups?",
            message = "Rodwave writes back the ${op.backups.size} original file(s) saved by this ${op.type.name.lowercase()} of '${op.modName ?: "unknown"}'. " +
                "Each file is checked against its recorded SHA-256 before it is written.",
            confirmLabel = "Restore",
            requireCheck = "Overwrite the current files at those paths",
            onConfirm = { studio.restoreOperation(op.id); restoring = null },
            onDismiss = { restoring = null },
        )
    }
    categoryFor?.let { mod ->
        TextInputDialog("Category for ${mod.name}", mod.category, "Save", onDismiss = { categoryFor = null }) { value ->
            studio.updateMod(mod.copy(category = value.take(40)))
            categoryFor = null
        }
    }
}

@Composable
private fun LibraryPane(
    studio: Studio,
    query: String,
    onQuery: (String) -> Unit,
    kind: ModKind?,
    onKind: (ModKind?) -> Unit,
    onInstall: (ManagedMod) -> Unit,
    onUninstall: (ManagedMod) -> Unit,
    onRemove: (ManagedMod) -> Unit,
    onCategory: (ManagedMod) -> Unit,
) {
    val mods = studio.mods
    val visible = remember(mods, query, kind) {
        val q = query.trim().lowercase()
        mods.filter { m ->
            (kind == null || m.kind == kind) &&
                (q.isEmpty() || listOfNotNull(m.name, m.category, m.author, m.description, m.sourceName).any { it.lowercase().contains(q) })
        }.sortedWith(compareBy({ !it.enabled }, { it.category.lowercase() }, { it.name.lowercase() }))
    }
    val destinations = remember(studio.settings.folders) { studio.destinations().keys }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 96.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { MissingPieces(studio, destinations) }
        if (mods.isEmpty()) {
            item {
                EmptyState(
                    Icons.Outlined.Inventory2,
                    "No mods yet",
                    "Import .csa, .csi, .fxt, .so, .ini files or a .zip. Importing only stores a copy; installing is a separate step with a dry run.",
                )
            }
            return@LazyColumn
        }
        item { SearchField(query, onQuery, "Search mods") }
        item {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterPill("All", kind == null, count = mods.size) { onKind(null) }
                ModKind.entries.forEach { k ->
                    val n = mods.count { it.kind == k }
                    if (n > 0) FilterPill(k.label, kind == k, count = n) { onKind(if (kind == k) null else k) }
                }
            }
        }
        items(visible, key = { it.id }) { mod ->
            ModCard(studio, mod, destinations, onInstall, onUninstall, onRemove, onCategory)
        }
    }
}

@Composable
private fun MissingPieces(studio: Studio, destinations: Set<DestinationKind>) {
    val notes = buildList {
        if (DestinationKind.CLEO_SCRIPTS !in destinations) add("No CLEO scripts folder: scripts can be exported but not installed.")
        if (DestinationKind.AML_MODS !in destinations) add("No AML mods folder: native mods can be exported but not installed.")
        val aml = studio.status("aml")?.state
        if (studio.mods.any { it.kind == ModKind.AML_MOD } && aml != null && aml.name in setOf("NOT_DETECTED", "UNKNOWN")) {
            add("AML was not detected; native mods need AML to load.")
        }
    }
    if (notes.isNotEmpty()) {
        InfoBanner(notes.joinToString(" "), color = Palette.Gold, icon = Icons.Outlined.WarningAmber, title = "Before installing")
    }
}

@Composable
private fun ModCard(
    studio: Studio,
    mod: ManagedMod,
    destinations: Set<DestinationKind>,
    onInstall: (ManagedMod) -> Unit,
    onUninstall: (ManagedMod) -> Unit,
    onRemove: (ManagedMod) -> Unit,
    onCategory: (ManagedMod) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    SectionCard(
        mod.name,
        modifier = Modifier.animateContentSize().clickable { expanded = !expanded },
        icon = Icons.Outlined.Extension,
        accent = if (mod.enabled) Palette.Green else Palette.Violet,
        subtitle = listOfNotNull(mod.kind.label, mod.version?.let { "v$it" }, mod.author?.let { "by $it" }).joinToString(" · "),
        trailing = { Tag(if (mod.enabled) "installed" else "not installed", if (mod.enabled) Palette.Green else MaterialTheme.colorScheme.onSurfaceVariant) },
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Tag(mod.category, Palette.Sky, Modifier.clickable { onCategory(mod) })
            Tag("${mod.files.size} file(s) · ${formatBytes(mod.files.sumOf { it.size })}")
        }
        if (mod.description.isNotBlank()) Text(mod.description, style = MaterialTheme.typography.bodySmall)
        val missing = mod.files.map { it.destination }.distinct().filter { it != DestinationKind.EXPORT && it !in destinations }
        if (missing.isNotEmpty()) {
            Text("Needs: ${missing.joinToString { it.label }}", style = MaterialTheme.typography.bodySmall, color = Palette.Gold)
        }
        if (mod.findings.isNotEmpty()) {
            BulletList(if (expanded) mod.findings else mod.findings.take(2), color = Palette.Gold)
        }
        if (expanded) {
            Text("Files", style = MaterialTheme.typography.titleSmall)
            mod.files.forEach { f ->
                Column {
                    Text("${f.destination.label} / ${f.targetPath}", fontFamily = CodeFont, style = MaterialTheme.typography.labelSmall)
                    Text("${f.kind.label} · ${formatBytes(f.size)} · sha256 ${f.sha256.take(12)}…", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (mod.requires.isNotEmpty()) KeyValue("Requires", mod.requires.joinToString())
            KeyValue("Imported from", mod.sourceName, mono = true)
            KeyValue("Imported", formatTime(mod.importedAt))
            mod.instructions?.let {
                Text("Instructions from the archive", style = MaterialTheme.typography.titleSmall)
                Text(it.take(4000), style = MaterialTheme.typography.bodySmall, fontFamily = CodeFont)
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (mod.enabled) {
                FilledTonalButton(enabled = studio.busy == null, onClick = { onUninstall(mod) }) { Text("Uninstall…") }
            } else {
                FilledTonalButton(enabled = studio.busy == null, onClick = { onInstall(mod) }) { Text("Install…") }
            }
            OutlinedButton(onClick = { studio.exportMod(mod) }) { Text("Export") }
            if (!mod.enabled) TextButton(onClick = { onRemove(mod) }) { Text("Remove", color = MaterialTheme.colorScheme.error) }
        }
    }
}

@Composable
private fun PlanDialog(studio: Studio, plan: InstallPlan, onApply: (Boolean) -> Unit, onDismiss: () -> Unit) {
    var accepted by remember(plan) { mutableStateOf(false) }
    val verb = if (plan.type == OperationType.INSTALL) "Install" else "Uninstall"
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("$verb '${plan.mod.name}'") },
        text = {
            Column(Modifier.heightIn(max = 520.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Dry run — nothing has changed yet.", style = MaterialTheme.typography.labelLarge, color = Palette.Teal)
                plan.actions.forEach { a ->
                    val color = when (a.type) {
                        ActionType.CREATE -> Palette.Green
                        ActionType.REPLACE -> Palette.Gold
                        ActionType.SKIP_IDENTICAL -> MaterialTheme.colorScheme.onSurfaceVariant
                        ActionType.DELETE -> Palette.Red
                        ActionType.RESTORE -> Palette.Sky
                    }
                    Column {
                        Text(a.type.label, style = MaterialTheme.typography.labelMedium, color = color)
                        Text("${a.destination.label} / ${a.targetPath}", fontFamily = CodeFont, style = MaterialTheme.typography.labelSmall)
                        if (a.note.isNotEmpty()) Text(a.note, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                if (plan.blockers.isNotEmpty()) {
                    InfoBanner(plan.blockers.joinToString("\n"), color = Palette.Red, title = "Cannot apply")
                }
                plan.warnings.forEach { InfoBanner(it, color = Palette.Gold, icon = Icons.Outlined.WarningAmber) }
                if (plan.confirmations.isNotEmpty()) {
                    Text("Needs your confirmation", style = MaterialTheme.typography.titleSmall, color = Palette.Gold)
                    plan.confirmations.forEach { c ->
                        Text("${c.destination.label} / ${c.targetPath}: ${c.reason}", style = MaterialTheme.typography.bodySmall)
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clickable { accepted = !accepted }) {
                        Checkbox(checked = accepted, onCheckedChange = { accepted = it })
                        Text("Replace these files (Rodwave backs up the originals first)", style = MaterialTheme.typography.bodySmall)
                    }
                }
                if (!plan.changesFiles && plan.blockers.isEmpty()) {
                    Text("Every file is already in place; applying only records ownership.", style = MaterialTheme.typography.bodySmall)
                }
                Text(
                    "After writing, Rodwave reads every file back and compares its SHA-256. If anything fails, all changes of this operation are rolled back.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        confirmButton = {
            TextButton(enabled = plan.canApply(accepted) && studio.busy == null, onClick = { onApply(accepted) }) { Text(verb) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun ImportResultDialog(result: ImportResult, onDismiss: () -> Unit) {
    val mod = result.mod
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(if (mod != null) Icons.Outlined.CheckCircle else Icons.Outlined.WarningAmber, null, tint = if (mod != null) Palette.Green else Palette.Red) },
        title = { Text(if (mod != null) "Imported ${mod.name}" else "Import failed") },
        text = {
            Column(Modifier.heightIn(max = 460.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (mod != null) {
                    Text("Stored in Rodwave's library. Nothing was installed yet.", style = MaterialTheme.typography.bodySmall, color = Palette.Teal)
                    KeyValue("Kind", mod.kind.label)
                    KeyValue("Files", "${mod.files.size}")
                }
                if (result.messages.isNotEmpty()) BulletList(result.messages)
                if (result.rejectedEntries.isNotEmpty()) {
                    Text("Rejected archive entries", style = MaterialTheme.typography.titleSmall, color = Palette.Red)
                    BulletList(result.rejectedEntries, color = Palette.Red)
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } },
    )
}

@Composable
private fun HistoryPane(studio: Studio, onRestore: (OperationRecord) -> Unit) {
    val ops = remember(studio.operations) { studio.operations.sortedByDescending { it.startedAt } }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (ops.isEmpty()) {
            item { EmptyState(Icons.Outlined.History, "No operations yet", "Installs, uninstalls and restores are logged here with their backups.") }
        }
        items(ops, key = { it.id }) { op -> OperationCard(op, onRestore) }
        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
private fun OperationCard(op: OperationRecord, onRestore: (OperationRecord) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val color = when (op.status) {
        OperationStatus.SUCCEEDED -> Palette.Green
        OperationStatus.ROLLED_BACK -> Palette.Gold
        OperationStatus.FAILED -> Palette.Red
    }
    SectionCard(
        "${op.type.name.lowercase().replaceFirstChar { it.uppercase() }} · ${op.modName ?: "—"}",
        modifier = Modifier.animateContentSize().clickable { expanded = !expanded },
        icon = Icons.Outlined.History,
        accent = color,
        subtitle = formatTime(op.startedAt) + " · ${op.backups.size} backup(s)",
        trailing = { Tag(op.status.name.lowercase().replace('_', ' '), color) },
    ) {
        op.error?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = Palette.Red) }
        if (expanded) {
            op.steps.forEach { Text(it, fontFamily = CodeFont, style = MaterialTheme.typography.labelSmall) }
            op.backups.forEach { b ->
                Text("backup: ${b.destination.label} / ${b.targetPath} (${formatBytes(b.size)})", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (op.backups.isNotEmpty() && op.status == OperationStatus.SUCCEEDED) {
            OutlinedButton(onClick = { onRestore(op) }) { Text("Restore originals…") }
        }
    }
}
