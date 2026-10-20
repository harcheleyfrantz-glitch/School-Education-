@file:OptIn(ExperimentalLayoutApi::class)

package com.rodwave.studio.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Extension
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.FolderOff
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Output
import androidx.compose.material.icons.outlined.SportsEsports
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material3.FilledTonalButton
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.rodwave.engine.compat.ScanResult
import com.rodwave.studio.core.FolderPurpose
import com.rodwave.studio.core.Studio
import com.rodwave.studio.ui.ScreenFrame
import com.rodwave.studio.ui.components.ConfidenceTag
import com.rodwave.studio.ui.components.ConfirmDialog
import com.rodwave.studio.ui.components.InfoBanner
import com.rodwave.studio.ui.components.KeyValue
import com.rodwave.studio.ui.components.SectionCard
import com.rodwave.studio.ui.components.Tag
import com.rodwave.studio.ui.components.formatBytes
import com.rodwave.studio.ui.theme.CodeFont
import com.rodwave.studio.ui.theme.Palette

private const val GAME_PACKAGE = "com.rockstargames.gtasa"

private fun FolderPurpose.icon(): ImageVector = when (this) {
    FolderPurpose.GAME_DATA -> Icons.Outlined.SportsEsports
    FolderPurpose.CLEO_SCRIPTS -> Icons.Outlined.Terminal
    FolderPurpose.AML_MODS -> Icons.Outlined.Extension
    FolderPurpose.EXPORT -> Icons.Outlined.Output
}

@Composable
fun GameDirectoryScreen(studio: Studio) {
    var forgetting by remember { mutableStateOf<FolderPurpose?>(null) }
    val sdk = studio.platform.sdkInt
    val scopedStorage = sdk != null && sdk >= 30
    ScreenFrame(studio, "Game Directory", "${studio.settings.folders.size} of ${FolderPurpose.entries.size} folders set") {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { AccessExplainer(sdk, scopedStorage) }
            item { ExpectedLocations(studio, scopedStorage) }
            items(FolderPurpose.entries, key = { it.name }) { purpose ->
                FolderCard(studio, purpose, scopedStorage, onForget = { forgetting = purpose })
            }
            item {
                SectionCard("Rescan", icon = Icons.Outlined.Folder, subtitle = "Scans every folder again (read-only) and re-evaluates the Compatibility Center") {
                    FilledTonalButton(enabled = studio.busy == null && studio.settings.folders.isNotEmpty(), onClick = { studio.scanFolders() }) { Text("Scan all folders") }
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
    forgetting?.let { purpose ->
        ConfirmDialog(
            title = "Forget ${purpose.title.lowercase()}?",
            message = "Rodwave releases its access permission and stops using this folder. No files are deleted.",
            confirmLabel = "Forget",
            onConfirm = { studio.forgetFolder(purpose); forgetting = null },
            onDismiss = { forgetting = null },
        )
    }
}

@Composable
private fun AccessExplainer(sdk: Int?, scopedStorage: Boolean) {
    InfoBanner(
        title = "What Android lets Rodwave see",
        icon = Icons.Outlined.Lock,
        color = if (scopedStorage) Palette.Gold else Palette.Sky,
        text = buildString {
            append("Rodwave only reads folders you pick in the system picker, and keeps that permission until you forget the folder. ")
            append("It never asks for root or \"all files\" access. ")
            if (scopedStorage) {
                append("On this device (Android API $sdk) the picker cannot open Android/data or Android/obb, so the game's own data folder is out of reach — picking another folder does not change that. ")
                append("AML's internal folder AMLMods/$GAME_PACKAGE lives in shared storage and can be picked. When a destination is not reachable, export files and copy them with a file manager that has access.")
            } else if (sdk != null) {
                append("On Android 10 and older the picker can open Android/data/$GAME_PACKAGE directly.")
            } else {
                append("Desktop preview: folders open directly from disk.")
            }
        },
    )
}

@Composable
private fun ExpectedLocations(studio: Studio, scopedStorage: Boolean) {
    val game = studio.installedGame
    SectionCard(
        "Where things usually live",
        icon = Icons.Outlined.Folder,
        subtitle = if (game != null) "${game.packageName} ${game.versionName ?: ""} is installed" else "The game package was not detected",
    ) {
        LocationRow("Android/data/$GAME_PACKAGE", "Game data, saves, AML internal mods and configs", reachable = !scopedStorage)
        LocationRow("AMLMods/$GAME_PACKAGE", "AML's shared-storage mods folder (loaded after the internal one)", reachable = true)
        LocationRow("Android/obb/$GAME_PACKAGE", "Game archives; Rodwave never needs to touch these", reachable = !scopedStorage)
        Text(
            "The folder a CLEO loader reads scripts from depends on that loader build. Rodwave finds it from scripts already on your device, or you choose it.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun LocationRow(path: String, description: String, reachable: Boolean) {
    Row(verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f)) {
            Text(path, fontFamily = CodeFont, style = MaterialTheme.typography.bodySmall)
            Text(description, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Tag(if (reachable) "pickable" else "blocked by Android", if (reachable) Palette.Green else Palette.Gold)
    }
}

@Composable
private fun FolderCard(studio: Studio, purpose: FolderPurpose, scopedStorage: Boolean, onForget: () -> Unit) {
    val ref = studio.settings.folder(purpose)
    val folder = remember(ref) { ref?.let { studio.folder(purpose) } }
    val scan = studio.scans[purpose]
    SectionCard(
        purpose.title,
        icon = purpose.icon(),
        accent = when {
            ref == null -> Palette.Slate
            folder == null -> Palette.Red
            else -> Palette.Teal
        },
        subtitle = purpose.description,
    ) {
        when {
            ref == null -> Text("Not set", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            folder == null -> InfoBanner("Access to “${ref.displayName}” was lost (the folder was moved, deleted or the permission revoked). Choose it again.", color = Palette.Red, icon = Icons.Outlined.FolderOff)
            else -> {
                KeyValue("Folder", ref.displayName, mono = true)
                KeyValue("Writable", if (folder.canWrite) "yes" else "no — read-only")
            }
        }
        if (scan != null) ScanSummary(scan)
        if (purpose == FolderPurpose.GAME_DATA && scopedStorage) {
            Text(
                "If the picker hides Android/data, leave this unset; the AML mods and export folders cover installation.",
                style = MaterialTheme.typography.bodySmall,
                color = Palette.Gold,
            )
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            FilledTonalButton(onClick = { studio.chooseFolder(purpose) }) { Text(if (ref == null) "Choose folder" else "Change") }
            if (ref != null) {
                OutlinedButton(onClick = onForget) { Text("Forget") }
            }
        }
    }
}

@Composable
private fun ScanSummary(scan: ScanResult) {
    var showAll by remember(scan) { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(scan.location.label, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
            ConfidenceTag(scan.locationConfidence)
        }
        scan.locationEvidence.take(4).forEach { e ->
            Text("• ${e.text}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        KeyValue("Files scanned", "${scan.filesScanned}" + if (scan.truncated) " (limit reached; scan a smaller folder)" else "")
        KeyValue("CLEO scripts", "${scan.scripts.size}" + if (scan.scriptFolders.isNotEmpty()) " in ${scan.scriptFolders.joinToString { it.ifEmpty { "/" } }}" else "")
        KeyValue("Native libraries", "${scan.nativeMods.size} (${scan.nativeMods.count { it.info.isAmlMod }} AML mods)")
        if (scan.configFiles.isNotEmpty()) KeyValue("AML configs", "${scan.configFiles.size}")
        scan.amlCore?.let { core -> KeyValue("AML core config", "version ${core.version ?: "?"}" + (core.lastLaunchEpochSeconds?.let { " · last launch ${formatTime(it * 1000)}" } ?: "")) }
        if (scan.saveFiles.isNotEmpty()) KeyValue("Save files", "${scan.saveFiles.size}")
        if (scan.pcScripts.isNotEmpty()) KeyValue("PC scripts (.cs)", "${scan.pcScripts.size} — not loaded by CLEO Android")
        if (scan.mainScmFiles.isNotEmpty()) KeyValue("main.scm", scan.mainScmFiles.joinToString(), mono = true)
        if (scan.errors.isNotEmpty()) {
            Text("${scan.errors.size} file(s) could not be read", style = MaterialTheme.typography.bodySmall, color = Palette.Red)
        }
        if (showAll) {
            scan.scripts.take(100).forEach { s ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(s.path, fontFamily = CodeFont, style = MaterialTheme.typography.labelSmall, modifier = Modifier.weight(1f))
                    Text(formatBytes(s.size), style = MaterialTheme.typography.labelSmall)
                    s.report?.let { Tag(it.verdict.label.substringBefore(" —"), verdictColor(it.verdict), Modifier.padding(start = 6.dp)) }
                }
            }
            scan.nativeMods.take(100).forEach { m ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(m.path, fontFamily = CodeFont, style = MaterialTheme.typography.labelSmall, modifier = Modifier.weight(1f))
                    Tag(m.info.abi?.androidName ?: "not ELF", if (m.info.isLoaderCompatibleAbi) Palette.Green else Palette.Red)
                    if (m.info.isAmlMod) Tag("AML", Palette.Violet, Modifier.padding(start = 4.dp))
                }
            }
            scan.errors.take(20).forEach { Text(it, style = MaterialTheme.typography.labelSmall, color = Palette.Red) }
        }
        if (scan.scripts.isNotEmpty() || scan.nativeMods.isNotEmpty() || scan.errors.isNotEmpty()) {
            TextButton(onClick = { showAll = !showAll }) { Text(if (showAll) "Hide files" else "Show files") }
        }
    }
}
