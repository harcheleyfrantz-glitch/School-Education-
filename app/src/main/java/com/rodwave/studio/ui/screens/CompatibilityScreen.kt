@file:OptIn(ExperimentalLayoutApi::class)

package com.rodwave.studio.ui.screens

import androidx.compose.animation.animateContentSize
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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.rodwave.engine.compat.ComponentCategory
import com.rodwave.engine.compat.ComponentState
import com.rodwave.engine.compat.ComponentStatus
import com.rodwave.engine.compat.ExternalLink
import com.rodwave.engine.compat.GtaSaVersions
import com.rodwave.studio.core.Screen
import com.rodwave.studio.core.Studio
import com.rodwave.studio.ui.ScreenFrame
import com.rodwave.studio.ui.components.BulletList
import com.rodwave.studio.ui.components.ConfidenceTag
import com.rodwave.studio.ui.components.FilterPill
import com.rodwave.studio.ui.components.InfoBanner
import com.rodwave.studio.ui.components.KeyValue
import com.rodwave.studio.ui.components.OpenLinkDialog
import com.rodwave.studio.ui.components.SearchField
import com.rodwave.studio.ui.components.SectionCard
import com.rodwave.studio.ui.components.StateChip
import com.rodwave.studio.ui.components.Tag
import com.rodwave.studio.ui.theme.CodeFont
import com.rodwave.studio.ui.theme.Palette
import com.rodwave.studio.ui.theme.stateColor

@Composable
fun CompatibilityScreen(studio: Studio) {
    var query by remember { mutableStateOf("") }
    var filter by remember { mutableStateOf<ComponentState?>(null) }
    var link by remember { mutableStateOf<ExternalLink?>(null) }
    val statuses = studio.statuses
    val visible = remember(statuses, query, filter) {
        val q = query.trim().lowercase()
        statuses.filter { s ->
            (filter == null || s.state == filter) &&
                (q.isEmpty() || listOf(s.profile.name, s.profile.summary, s.summary, s.profile.category.label).any { it.lowercase().contains(q) } ||
                    s.evidence.any { it.text.lowercase().contains(q) })
        }
    }
    ScreenFrame(
        studio,
        "Compatibility Center",
        studio.lastScanTime?.let { "Last scan ${formatTime(it)}" } ?: "No folder scanned yet",
        actions = {
            IconButton(onClick = { studio.detectGame(); if (studio.settings.folders.isNotEmpty()) studio.scanFolders() }, enabled = studio.busy == null) {
                Icon(Icons.Outlined.Refresh, "Rescan")
            }
        },
    ) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { DeviceCard(studio) }
            item {
                InfoBanner(
                    title = "How states are decided",
                    text = "\"Compatible\" needs evidence beyond file names, such as AML's own config written at launch or a library that exports AML's entry point. " +
                        "A file that is only present by name is at most \"Installed but unverified\". CLEO and AML are different systems: CLEO runs bytecode " +
                        "scripts (.csa/.csi), AML loads native .so mods — CLEO can itself be installed as an AML mod.",
                )
            }
            item { ReportActions(studio) }
            item { SearchField(query, { query = it }, "Search components, evidence…") }
            item {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterPill("All", filter == null, count = statuses.size) { filter = null }
                    ComponentState.entries.forEach { st ->
                        val n = statuses.count { it.state == st }
                        if (n > 0) FilterPill(st.label, filter == st, stateColor(st), n) { filter = if (filter == st) null else st }
                    }
                }
            }
            ComponentCategory.entries.forEach { category ->
                val group = visible.filter { it.profile.category == category }
                if (group.isNotEmpty()) {
                    item(key = "header-${category.name}") {
                        Text(category.label, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp))
                    }
                    items(group, key = { it.profile.id }) { status -> StatusCard(status) { link = it } }
                }
            }
            if (visible.isEmpty()) {
                item { Text("No component matches.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
    link?.let { l -> OpenLinkDialog(l.title, l.url, onOpen = { studio.platform.openUrl(l.url) }, onDismiss = { link = null }) }
}

@Composable
private fun DeviceCard(studio: Studio) {
    val game = studio.installedGame
    SectionCard(
        if (game != null) "GTA SA ${game.versionName ?: "(unknown version)"}" else "Game not detected",
        icon = Icons.Outlined.PhoneAndroid,
        accent = if (game != null) Palette.Green else Palette.Slate,
        subtitle = studio.platform.platformName + (studio.platform.sdkInt?.let { " · API $it" } ?: ""),
    ) {
        if (game == null) {
            Text(
                "Android's package manager does not report com.rockstargames.gtasa. Rodwave can still compile scripts and manage mods; " +
                    "choose folders in Game Directory to scan existing files.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            KeyValue("Package", game.packageName, mono = true)
            KeyValue("Version", "${game.versionName ?: "?"} (code ${game.versionCode ?: "?"})" + (GtaSaVersions.classify(game.versionName)?.let { " → profile $it" } ?: " → not a known version"))
            KeyValue("ABIs", game.abis.joinToString { it.androidName }.ifEmpty { "unknown" })
            KeyValue("APK readable", if (game.apkReadable) "yes — native libraries listed from the APK" else "no")
            if (game.hasAml) KeyValue("Bundled loader", "libAML.so is inside the APK (patched game)")
            game.targetSdk?.let { KeyValue("Target SDK", "$it") }
        }
        val scan = studio.mergedScan()
        if (scan != null) {
            KeyValue("Scanned", "${scan.filesScanned} files in ${studio.scans.size} folder(s)" + if (scan.truncated) " (limit reached)" else "")
            KeyValue("Found", "${scan.scripts.size} scripts · ${scan.nativeMods.size} libraries · ${scan.configFiles.size} configs")
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            FilledTonalButton(onClick = { studio.navigate(Screen.GAME_DIR) }) { Text("Game Directory") }
            OutlinedButton(enabled = studio.busy == null, onClick = {
                studio.detectGame()
                if (studio.settings.folders.isNotEmpty()) studio.scanFolders()
            }) { Text("Rescan") }
        }
    }
}

@Composable
private fun ReportActions(studio: Studio) {
    SectionCard("Compatibility report", icon = Icons.Outlined.VerifiedUser, subtitle = "Markdown summary of the game, folders, evidence and states for troubleshooting") {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            TextButton(onClick = {
                studio.platform.saveDocument("rodwave-compatibility-report.md", "text/markdown", studio.reportText().toByteArray()) { ok, _ ->
                    if (ok) studio.notify("Report saved")
                }
            }) {
                Icon(Icons.Outlined.FileUpload, null)
                Text(" Export")
            }
            TextButton(onClick = { studio.platform.share("Rodwave compatibility report", studio.reportText()) }) {
                Icon(Icons.Outlined.Share, null)
                Text(" Share")
            }
            TextButton(onClick = {
                studio.platform.copyToClipboard("Rodwave report", studio.reportText())
                studio.notify("Report copied")
            }) {
                Icon(Icons.Outlined.ContentCopy, null)
                Text(" Copy")
            }
        }
        Text(
            "The report stays on your device unless you export or share it.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun StatusCard(status: ComponentStatus, onLink: (ExternalLink) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val p = status.profile
    SectionCard(
        p.name,
        modifier = Modifier.animateContentSize().clickable { expanded = !expanded },
        subtitle = status.summary,
        accent = stateColor(status.state),
        trailing = {
            Icon(if (expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, if (expanded) "Collapse" else "Expand")
        },
    ) {
        StateChip(status.state)
        if (status.evidence.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                status.evidence.take(if (expanded) 50 else 3).forEach { e ->
                    Row(verticalAlignment = Alignment.Top) {
                        ConfidenceTag(e.confidence)
                        Column(Modifier.padding(start = 8.dp).weight(1f)) {
                            Text(e.text, style = MaterialTheme.typography.bodySmall)
                            e.path?.let { Text(it, fontFamily = CodeFont, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        }
                    }
                }
                if (!expanded && status.evidence.size > 3) {
                    Text("+${status.evidence.size - 3} more", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                }
            }
        }
        if (expanded) {
            Text(p.summary, style = MaterialTheme.typography.bodyMedium)
            KeyValue("Versions", p.supportedVersions)
            KeyValue("ABIs", p.supportedAbis)
            if (p.requirements.isNotEmpty()) {
                Text("Requirements", style = MaterialTheme.typography.titleSmall)
                BulletList(p.requirements)
            }
            if (p.installSteps.isNotEmpty()) {
                Text("Install", style = MaterialTheme.typography.titleSmall)
                BulletList(p.installSteps, numbered = true)
            }
            if (p.limitations.isNotEmpty()) {
                Text("Limitations", style = MaterialTheme.typography.titleSmall)
                BulletList(p.limitations, color = Palette.Gold)
            }
            Text("Sources", style = MaterialTheme.typography.titleSmall)
            BulletList(p.sources, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (p.links.isNotEmpty()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    p.links.forEach { l ->
                        TextButton(onClick = { onLink(l) }) {
                            Text(l.title)
                            Icon(Icons.AutoMirrored.Outlined.OpenInNew, null, Modifier.padding(start = 4.dp))
                        }
                    }
                }
            }
            Tag(p.category.label)
        }
    }
}
