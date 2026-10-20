package com.rodwave.studio.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.DriveFileRenameOutline
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.automirrored.outlined.InsertDriveFile
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.automirrored.outlined.NoteAdd
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.unit.dp
import com.rodwave.engine.project.Project
import com.rodwave.engine.project.ProjectManager
import com.rodwave.engine.project.ProjectTemplate
import com.rodwave.engine.project.Templates
import com.rodwave.studio.core.Screen
import com.rodwave.studio.core.Studio
import com.rodwave.studio.ui.ScreenFrame
import com.rodwave.studio.ui.components.ConfirmDialog
import com.rodwave.studio.ui.components.EmptyState
import com.rodwave.studio.ui.components.SectionCard
import com.rodwave.studio.ui.components.Tag
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

fun formatTime(millis: Long): String =
    if (millis <= 0) "—" else SimpleDateFormat("MMM d, HH:mm", Locale.getDefault()).format(Date(millis))

@Composable
fun ProjectsScreen(studio: Studio) {
    var showNew by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<Project?>(null) }
    var deleting by remember { mutableStateOf<Project?>(null) }
    var newFileIn by remember { mutableStateOf<Project?>(null) }

    ScreenFrame(studio, "Projects", "${studio.projectList.size} project(s) in private storage") {
        androidx.compose.foundation.layout.Box(Modifier.weight(1f)) {
            if (studio.projectList.isEmpty()) {
                EmptyState(Icons.Outlined.FolderOpen, "No projects yet", "Create one from a template to start writing CLEO scripts.") {
                    TextButton(onClick = { showNew = true }) { Text("New project") }
                }
            } else {
                LazyColumn(contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(studio.projectList, key = { it.name }) { project ->
                        ProjectCard(
                            studio, project,
                            onRename = { renaming = project },
                            onDelete = { deleting = project },
                            onNewFile = { newFileIn = project },
                        )
                    }
                    item { Spacer(Modifier.padding(36.dp)) }
                }
            }
            ExtendedFloatingActionButton(
                onClick = { showNew = true },
                icon = { Icon(Icons.Outlined.Add, null) },
                text = { Text("New project") },
                modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp),
            )
        }
    }

    if (showNew) NewProjectDialog(studio) { showNew = false }
    renaming?.let { p ->
        TextInputDialog("Rename project", p.name, "Rename", onDismiss = { renaming = null }) { name ->
            studio.renameProject(p, name)
            renaming = null
        }
    }
    deleting?.let { p ->
        ConfirmDialog(
            title = "Delete '${p.name}'?",
            message = "The project folder and all its files will be removed from Rodwave's storage. Export a workspace backup first if you want to keep a copy.",
            confirmLabel = "Delete",
            destructive = true,
            requireCheck = "I understand this cannot be undone",
            onConfirm = {
                studio.deleteProject(p)
                deleting = null
            },
            onDismiss = { deleting = null },
        )
    }
    newFileIn?.let { p ->
        TextInputDialog("New file in ${p.name}", "helpers.txt", "Create", onDismiss = { newFileIn = null }) { name ->
            try {
                studio.projects.createFile(p, name, if (name.endsWith(".fxt", true)) "# KEY text\n" else "// ${name}\n")
                studio.refreshProjects()
                studio.editor.openProjectFile(studio.projectList.first { it.name == p.name }, name)
                studio.navigate(Screen.EDITOR)
            } catch (e: Exception) {
                studio.notify(e.message ?: "Could not create the file", isError = true)
            }
            newFileIn = null
        }
    }
}

@Composable
private fun ProjectCard(studio: Studio, project: Project, onRename: () -> Unit, onDelete: () -> Unit, onNewFile: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val files = remember(project, studio.projectList) { runCatching { project.sourceFiles() }.getOrDefault(emptyList()) }
    SectionCard(
        title = project.name,
        subtitle = "Modified ${formatTime(studio.projects.lastModified(project))}",
        icon = Icons.Outlined.FolderOpen,
        trailing = {
            Tag(".${project.format.extension}", MaterialTheme.colorScheme.tertiary)
            IconButton(onClick = { menu = true }) { Icon(Icons.Outlined.MoreVert, "Project actions") }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("New file") }, leadingIcon = { Icon(Icons.AutoMirrored.Outlined.NoteAdd, null) }, onClick = { menu = false; onNewFile() })
                DropdownMenuItem(text = { Text("Rename") }, leadingIcon = { Icon(Icons.Outlined.DriveFileRenameOutline, null) }, onClick = { menu = false; onRename() })
                DropdownMenuItem(text = { Text("Delete") }, leadingIcon = { Icon(Icons.Outlined.Delete, null) }, onClick = { menu = false; onDelete() })
            }
        },
    ) {
        if (project.manifest.description.isNotBlank()) {
            Text(project.manifest.description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        files.forEach { f ->
            Row(
                Modifier.fillMaxWidth().clickable {
                    studio.editor.openProjectFile(project, f.name)
                    studio.navigate(Screen.EDITOR)
                }.padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.AutoMirrored.Outlined.InsertDriveFile, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.width(10.dp))
                Text(f.name, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                Text("${f.length} B", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
fun NewProjectDialog(studio: Studio, initialTemplate: ProjectTemplate = Templates.EMPTY, onDismiss: () -> Unit) {
    var name by remember { mutableStateOf("MyScript") }
    var template by remember { mutableStateOf(initialTemplate) }
    val nameError = remember(name) { runCatching { ProjectManager.validateName(name) }.exceptionOrNull()?.message }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("New project") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name") },
                    singleLine = true,
                    isError = nameError != null,
                    supportingText = { if (nameError != null) Text(nameError) },
                    modifier = Modifier.fillMaxWidth(),
                )
                Text("Template", style = MaterialTheme.typography.titleSmall)
                Templates.ALL.forEach { t ->
                    Row(
                        Modifier.fillMaxWidth().selectable(selected = t == template, onClick = { template = t }).padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(selected = t == template, onClick = { template = t })
                        Column(Modifier.weight(1f)) {
                            Text(t.title, style = MaterialTheme.typography.bodyMedium)
                            Text(t.description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Tag(".${t.format.extension}", MaterialTheme.colorScheme.tertiary)
                    }
                }
            }
        },
        confirmButton = {
            TextButton(enabled = nameError == null, onClick = {
                if (studio.createProject(name, template) != null) onDismiss()
            }) { Text("Create") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
fun TextInputDialog(title: String, initial: String, confirm: String, onDismiss: () -> Unit, onConfirm: (String) -> Unit) {
    var value by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { OutlinedTextField(value, { value = it }, singleLine = true, modifier = Modifier.fillMaxWidth()) },
        confirmButton = { TextButton(enabled = value.isNotBlank(), onClick = { onConfirm(value.trim()) }) { Text(confirm) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
