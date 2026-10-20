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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Backup
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.automirrored.outlined.LibraryBooks
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.PrivacyTip
import androidx.compose.material.icons.outlined.Troubleshoot
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rodwave.engine.RodwaveEngine
import com.rodwave.studio.core.Screen
import com.rodwave.studio.core.Studio
import com.rodwave.studio.core.StudioSettings
import com.rodwave.studio.core.ThemeVariant
import com.rodwave.studio.ui.ScreenFrame
import com.rodwave.studio.ui.components.BulletList
import com.rodwave.studio.ui.components.FilterPill
import com.rodwave.studio.ui.components.KeyValue
import com.rodwave.studio.ui.components.SectionCard
import com.rodwave.studio.ui.icon.RodwaveLogo
import com.rodwave.studio.ui.theme.CodeFont
import com.rodwave.studio.ui.theme.Palette
import kotlin.math.roundToInt

private val AUTOSAVE_CHOICES = listOf(0 to "Off", 15 to "15 s", 30 to "30 s", 60 to "1 min")

@Composable
fun SettingsScreen(studio: Studio) {
    val s = studio.settings
    fun update(transform: (StudioSettings) -> StudioSettings) = studio.updateSettings(transform)
    ScreenFrame(studio, "Settings", "Editor, appearance, storage and diagnostics") {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                SectionCard("Editor", icon = Icons.Outlined.Code) {
                    // Saved when the drag ends, not on every step.
                    var font by remember(s.fontSize) { mutableFloatStateOf(s.fontSize.toFloat()) }
                    Text("Font size: ${font.roundToInt()} sp", style = MaterialTheme.typography.bodyMedium)
                    Slider(
                        value = font,
                        onValueChange = { font = it },
                        onValueChangeFinished = { update { it.copy(fontSize = font.roundToInt().coerceIn(10, 24)) } },
                        valueRange = 10f..24f,
                        steps = 13,
                    )
                    Text("while true\n    wait 0\nend", fontFamily = CodeFont, fontSize = font.roundToInt().sp, color = Palette.Teal)
                    SettingSwitch("Autocomplete", "Suggest commands, labels, variables and enums from the opcode library", s.autocomplete) { v -> update { it.copy(autocomplete = v) } }
                    SettingSwitch("Auto-indent", "Indent after if/while/repeat and dedent end/else/until", s.autoIndent) { v -> update { it.copy(autoIndent = v) } }
                    SettingSwitch("Coding bar", "Symbol keys above the on-screen keyboard", s.codingBar) { v -> update { it.copy(codingBar = v) } }
                    SettingSwitch("Live diagnostics", "Recompile in the background while you type", s.liveDiagnostics) { v -> update { it.copy(liveDiagnostics = v) } }
                    Text("Autosave project files", style = MaterialTheme.typography.bodyMedium)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        AUTOSAVE_CHOICES.forEach { (seconds, label) ->
                            FilterPill(label, s.autosaveSeconds == seconds) { update { it.copy(autosaveSeconds = seconds) } }
                        }
                    }
                    Text(
                        "Unsaved changes are also written to a recovery snapshot every few seconds, so they survive a crash even with autosave off.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            item {
                SectionCard("Appearance", icon = Icons.Outlined.Palette) {
                    ThemeVariant.entries.forEach { t ->
                        Row(
                            Modifier.fillMaxWidth().selectable(selected = s.theme == t, onClick = { update { it.copy(theme = t) } }),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = s.theme == t, onClick = { update { it.copy(theme = t) } })
                            Text(t.title)
                        }
                    }
                }
            }
            item {
                SectionCard("Opcode library", icon = Icons.AutoMirrored.Outlined.LibraryBooks, subtitle = studio.libraryState.message) {
                    FilledTonalButton(onClick = { studio.navigate(Screen.OPCODES) }) { Text("Manage library") }
                }
            }
            item {
                SectionCard("Storage and backups", icon = Icons.Outlined.Backup) {
                    KeyValue("App storage", studio.storage.path.ifEmpty { "private app folder" }, mono = true)
                    KeyValue("Projects", "${studio.projectList.size}")
                    KeyValue("Managed mods", "${studio.mods.size}")
                    KeyValue("Mod operations", "${studio.operations.size}")
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilledTonalButton(enabled = studio.busy == null, onClick = { studio.exportWorkspace() }) { Text("Back up projects…") }
                        OutlinedButton(onClick = { studio.navigate(Screen.TOOLS) }) { Text("Restore…") }
                        OutlinedButton(onClick = { studio.navigate(Screen.GAME_DIR) }) { Text("Folders") }
                    }
                }
            }
            item {
                SectionCard("Privacy", icon = Icons.Outlined.PrivacyTip, accent = Palette.Green) {
                    BulletList(
                        listOf(
                            "Rodwave works offline. Projects, mods, logs and settings stay in its private storage on this device.",
                            "The network is used only when you download the opcode library. Links open in your browser after you confirm.",
                            "Nothing is uploaded, and there is no analytics or crash reporting.",
                            "Rodwave never requests root, \"all files\" access or other apps' data.",
                        ),
                    )
                }
            }
            item {
                SectionCard("Diagnostics", icon = Icons.Outlined.Troubleshoot) {
                    KeyValue("Platform", studio.platform.platformName)
                    studio.platform.sdkInt?.let { KeyValue("Android API", "$it") }
                    studio.platform.deviceInfo.forEach { (k, v) -> KeyValue(k, v) }
                    KeyValue("Engine", "${RodwaveEngine.NAME} ${RodwaveEngine.VERSION}")
                    KeyValue("Opcodes", "${studio.database.info.name} ${studio.database.info.version} (${studio.database.size})")
                    OutlinedButton(onClick = {
                        val text = buildString {
                            appendLine("Platform: ${studio.platform.platformName} ${studio.platform.sdkInt ?: ""}")
                            studio.platform.deviceInfo.forEach { (k, v) -> appendLine("$k: $v") }
                            appendLine("Engine: ${RodwaveEngine.VERSION}")
                            appendLine("Opcodes: ${studio.database.info.name} ${studio.database.info.version} (${studio.database.size})")
                        }
                        studio.platform.copyToClipboard("Rodwave diagnostics", text)
                        studio.notify("Diagnostics copied")
                    }) { Text("Copy diagnostics") }
                }
            }
            item {
                SectionCard("About", icon = Icons.Outlined.Info) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        RodwaveLogo(size = 56.dp)
                        Spacer(Modifier.width(14.dp))
                        Column {
                            Text("Rodwave", style = MaterialTheme.typography.titleLarge)
                            Text("A Sanny Builder for mobile · ${RodwaveEngine.VERSION}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    Text(
                        "Open-source under the MIT licence. Not affiliated with Rockstar Games, Take-Two, Sanny Builder, CLEO or AML. " +
                            "Rodwave ships no game files.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    Text("Third-party software", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 4.dp))
                    BulletList(
                        listOf(
                            "Kotlin, kotlinx.coroutines and kotlinx.serialization — Apache License 2.0",
                            "AndroidX, Jetpack Compose and Material 3 — Apache License 2.0",
                            "Opcode data verified against the Sanny Builder Library (sannybuilder/library); the library itself is not bundled",
                            "AML behaviour documented from AndroidModLoader by RusJJ (MIT); no AML code is included",
                        ),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun SettingSwitch(title: String, description: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(title, style = MaterialTheme.typography.bodyMedium)
            Text(description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Switch(checked = checked, onCheckedChange = onChange)
    }
}
