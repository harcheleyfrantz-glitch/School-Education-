package com.rodwave.studio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Extension
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.automirrored.outlined.ManageSearch
import androidx.compose.material.icons.outlined.Menu
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.rodwave.engine.opcode.DatabaseOrigin
import com.rodwave.studio.core.Screen
import com.rodwave.studio.core.Studio
import com.rodwave.studio.ui.LocalOpenDrawer
import com.rodwave.studio.ui.LocalWideLayout
import com.rodwave.studio.ui.components.ChipRow
import com.rodwave.studio.ui.components.SectionCard
import com.rodwave.studio.ui.components.StateChip
import com.rodwave.studio.ui.components.Tag
import com.rodwave.studio.ui.icon.RodwaveLogo
import com.rodwave.studio.ui.theme.Palette

@Composable
fun HomeScreen(studio: Studio) {
    var showNew by remember { mutableStateOf(false) }
    val wide = LocalWideLayout.current
    val openDrawer = LocalOpenDrawer.current
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            if (!wide) {
                IconButton(onClick = openDrawer) { Icon(Icons.Outlined.Menu, "Menu") }
            }
            Hero(studio)
        }
        item {
            QuickActions(
                listOf(
                    QuickAction("New project", "Start from a template", Icons.Outlined.Add, Palette.Sunset) { showNew = true },
                    QuickAction("Open project", "${studio.projectList.size} in storage", Icons.Outlined.FolderOpen, Palette.Pink) { studio.navigate(Screen.PROJECTS) },
                    QuickAction("Inspect script", "Decompile .csa/.csi/.scm", Icons.AutoMirrored.Outlined.ManageSearch, Palette.Violet) { studio.navigate(Screen.BUILD) },
                    QuickAction("Compatibility", "Game, CLEO and AML", Icons.Outlined.VerifiedUser, Palette.Teal) { studio.navigate(Screen.COMPAT) },
                    QuickAction("Mod Manager", "${studio.mods.size} managed mod(s)", Icons.Outlined.Extension, Palette.Gold) { studio.navigate(Screen.MODS) },
                    QuickAction("Opcodes", "${studio.database.size} commands", Icons.Outlined.Search, Palette.Sky) { studio.navigate(Screen.OPCODES) },
                ),
            )
        }
        val open = studio.editor.documents
        if (open.isNotEmpty()) {
            item {
                SectionCard("Continue editing", icon = Icons.Outlined.Code, subtitle = "${open.size} open tab(s)") {
                    open.take(4).forEach { doc ->
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable {
                                studio.editor.activate(doc)
                                studio.navigate(Screen.EDITOR)
                            }.padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(doc.title, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (doc.isDirty) Tag("unsaved", Palette.Gold)
                        }
                    }
                }
            }
        }
        item {
            Text("Recent projects", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 4.dp))
        }
        if (studio.projectList.isEmpty()) {
            item {
                SectionCard("No projects yet", icon = Icons.Outlined.AutoAwesome, subtitle = "Templates include a touch toggle, a menu script and a vehicle spawner.") {
                    FilledTonalButton(onClick = { showNew = true }) { Text("Create your first project") }
                }
            }
        } else {
            items(studio.projectList.take(5), key = { it.name }) { p ->
                SectionCard(
                    p.name,
                    icon = Icons.Outlined.Code,
                    subtitle = "Modified ${formatTime(studio.projects.lastModified(p))}",
                    modifier = Modifier.clickable { studio.openProject(p) },
                    trailing = { Tag(".${p.format.extension}", MaterialTheme.colorScheme.tertiary) },
                )
            }
        }
        item { LibraryCard(studio) }
        if (studio.settings.folders.isEmpty()) {
            item {
                SectionCard(
                    "Set up your game folders",
                    icon = Icons.Outlined.Info,
                    accent = Palette.Sky,
                    subtitle = "Android only lets apps open folders you pick. On Android 11+ the game's Android/data folder cannot be picked; Rodwave explains the alternatives.",
                ) {
                    FilledTonalButton(onClick = { studio.navigate(Screen.GAME_DIR) }) { Text("Open Game Directory") }
                }
            }
        }
        item {
            SectionCard("Documentation", icon = Icons.AutoMirrored.Outlined.MenuBook, subtitle = "Syntax reference, CLEO Android basics, storage access, porting PC scripts") {
                FilledTonalButton(onClick = { studio.navigate(Screen.DOCS) }) { Text("Read the docs") }
            }
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
    if (showNew) NewProjectDialog(studio) { showNew = false }
}

@Composable
private fun Hero(studio: Studio) {
    val shape = RoundedCornerShape(28.dp)
    Box(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Brush.linearGradient(listOf(Color(0xFF2B0A3D), Color(0xFF1A0B2E), Color(0xFF0E1226))))
            .border(1.dp, Brush.linearGradient(listOf(Palette.Sunset.copy(alpha = 0.7f), Palette.Pink.copy(alpha = 0.5f), Palette.Violet.copy(alpha = 0.3f))), shape)
            .padding(20.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                RodwaveLogo(size = 68.dp)
                Spacer(Modifier.width(16.dp))
                Column {
                    Text("Rodwave", style = MaterialTheme.typography.displaySmall, color = Color.White)
                    Text(
                        "Sanny Builder for mobile · GTA SA Android",
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.White.copy(alpha = 0.75f),
                    )
                }
            }
            val game = studio.installedGame
            Text(
                if (game != null) "GTA SA ${game.versionName ?: ""} · ${game.runningAbi?.androidName ?: game.abis.joinToString { it.androidName }.ifEmpty { "ABI unknown" }}" else "Game package not detected on this device",
                style = MaterialTheme.typography.labelLarge,
                color = Color.White,
                fontWeight = FontWeight.SemiBold,
            )
            ChipRow {
                listOf("gtasa-android" to "Game", "cleo-aml" to "CLEO (AML)", "aml" to "AML").forEach { (id, label) ->
                    studio.status(id)?.let { s ->
                        Column {
                            Text(label, style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.6f))
                            StateChip(s.state)
                        }
                    }
                }
            }
        }
    }
}

private data class QuickAction(val title: String, val subtitle: String, val icon: ImageVector, val color: Color, val onClick: () -> Unit)

@Composable
private fun QuickActions(actions: List<QuickAction>) {
    val wide = LocalWideLayout.current
    val perRow = if (wide) 3 else 2
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        actions.chunked(perRow).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { a ->
                    Column(
                        Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(20.dp))
                            .background(MaterialTheme.colorScheme.surfaceContainer)
                            .clickable(onClick = a.onClick)
                            .padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Box(Modifier.size(38.dp).clip(RoundedCornerShape(12.dp)).background(a.color.copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
                            Icon(a.icon, null, tint = a.color)
                        }
                        Text(a.title, style = MaterialTheme.typography.titleSmall, maxLines = 1)
                        Text(a.subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                repeat(perRow - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun LibraryCard(studio: Studio) {
    val state = studio.libraryState
    val full = state.database.info.origin != DatabaseOrigin.BUILT_IN
    SectionCard(
        "Opcode library",
        icon = Icons.Outlined.Search,
        accent = if (full) Palette.Green else Palette.Gold,
        subtitle = state.message,
    ) {
        if (!full) {
            Text(
                "The built-in core set covers control flow, math, common commands, mobile widgets and CLEO Android. Import the Sanny Builder Library for all 2,700+ commands.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            FilledTonalButton(onClick = { studio.navigate(Screen.OPCODES) }) { Text("Get the full library") }
        }
    }
}
