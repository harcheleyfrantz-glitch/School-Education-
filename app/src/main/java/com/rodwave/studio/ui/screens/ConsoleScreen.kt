package com.rodwave.studio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.DeleteSweep
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rodwave.studio.core.LogEntry
import com.rodwave.studio.core.LogLevel
import com.rodwave.studio.core.Studio
import com.rodwave.studio.ui.ScreenFrame
import com.rodwave.studio.ui.components.ConfirmDialog
import com.rodwave.studio.ui.components.EmptyState
import com.rodwave.studio.ui.components.FilterPill
import com.rodwave.studio.ui.components.SearchField
import com.rodwave.studio.ui.theme.CodeFont
import com.rodwave.studio.ui.theme.Palette
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private fun levelColor(level: LogLevel): Color = when (level) {
    LogLevel.INFO -> Palette.Sky
    LogLevel.SUCCESS -> Palette.Green
    LogLevel.WARNING -> Palette.Gold
    LogLevel.ERROR -> Palette.Red
}

@Composable
fun ConsoleScreen(studio: Studio) {
    val console = studio.console
    var query by remember { mutableStateOf("") }
    var levels by remember { mutableStateOf(LogLevel.entries.toSet()) }
    var confirmClear by remember { mutableStateOf(false) }
    val entries = console.entries
    val visible = remember(entries.size, entries.lastOrNull(), query, levels) {
        val q = query.trim().lowercase()
        entries.filter { it.level in levels && (q.isEmpty() || it.message.lowercase().contains(q) || it.source.lowercase().contains(q)) }
    }
    val listState = rememberLazyListState()
    LaunchedEffect(visible.size) {
        if (visible.isNotEmpty()) listState.scrollToItem(visible.lastIndex)
    }
    ScreenFrame(
        studio,
        "Console",
        "${entries.size} entries · ${entries.count { it.level == LogLevel.ERROR }} errors",
        actions = {
            IconButton(onClick = { studio.platform.copyToClipboard("Rodwave console", console.export()); studio.notify("Console copied") }) {
                Icon(Icons.Outlined.ContentCopy, "Copy log")
            }
            IconButton(onClick = {
                studio.platform.saveDocument("rodwave-console.log", "text/plain", console.export().toByteArray()) { ok, _ -> if (ok) studio.notify("Log saved") }
            }) { Icon(Icons.Outlined.FileUpload, "Export log") }
            IconButton(onClick = { confirmClear = true }) { Icon(Icons.Outlined.DeleteSweep, "Clear log") }
        },
    ) {
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SearchField(query, { query = it }, "Filter messages")
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                LogLevel.entries.forEach { level ->
                    FilterPill(level.name.lowercase().replaceFirstChar { it.uppercase() }, level in levels, levelColor(level), entries.count { it.level == level }) {
                        levels = if (level in levels) levels - level else levels + level
                    }
                }
            }
        }
        Box(Modifier.weight(1f).fillMaxWidth().padding(16.dp).clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.surfaceContainerLowest)) {
            if (visible.isEmpty()) {
                EmptyState(Icons.Outlined.Terminal, "Nothing logged", "Compiles, scans, installs and errors appear here as they happen.")
            } else {
                LazyColumn(state = listState, contentPadding = PaddingValues(10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    items(visible) { entry -> LogRow(entry) }
                }
            }
        }
    }
    if (confirmClear) {
        ConfirmDialog(
            title = "Clear the console?",
            message = "All log entries, including the saved history, are removed. Mod operation records are not affected.",
            confirmLabel = "Clear",
            destructive = true,
            onConfirm = { console.clear(); confirmClear = false },
            onDismiss = { confirmClear = false },
        )
    }
}

private val TIME = ThreadLocal.withInitial { SimpleDateFormat("HH:mm:ss", Locale.US) }

@Composable
private fun LogRow(entry: LogEntry) {
    Row(verticalAlignment = Alignment.Top) {
        Box(Modifier.padding(top = 5.dp).size(6.dp).clip(CircleShape).background(levelColor(entry.level)))
        Column(Modifier.padding(start = 8.dp)) {
            if (entry.time == 0L) {
                Text(entry.message, fontFamily = CodeFont, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                Row {
                    Text(TIME.get()!!.format(Date(entry.time)), fontFamily = CodeFont, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(" [${entry.source}]", fontFamily = CodeFont, fontSize = 11.sp, color = levelColor(entry.level), modifier = Modifier.width(110.dp))
                }
                Text(entry.message, fontFamily = CodeFont, fontSize = 12.sp)
            }
        }
    }
}
