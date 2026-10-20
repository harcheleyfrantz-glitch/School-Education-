@file:OptIn(ExperimentalLayoutApi::class)

package com.rodwave.studio.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
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
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rodwave.engine.compat.ComponentState
import com.rodwave.engine.compat.Confidence
import com.rodwave.engine.diagnostics.Diagnostic
import com.rodwave.engine.diagnostics.Severity
import com.rodwave.studio.ui.theme.CodeFont
import com.rodwave.studio.ui.theme.Palette
import com.rodwave.studio.ui.theme.stateColor

/** Card with an optional icon, title and trailing content. */
@Composable
fun SectionCard(
    title: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    subtitle: String? = null,
    accent: Color = MaterialTheme.colorScheme.primary,
    trailing: @Composable RowScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit = {},
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
        shape = MaterialTheme.shapes.large,
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (icon != null) {
                    Box(
                        Modifier.size(36.dp).clip(RoundedCornerShape(11.dp)).background(accent.copy(alpha = 0.16f)),
                        contentAlignment = Alignment.Center,
                    ) { Icon(icon, contentDescription = null, tint = accent, modifier = Modifier.size(20.dp)) }
                    Spacer(Modifier.width(12.dp))
                }
                Column(Modifier.weight(1f)) {
                    Text(title, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    if (subtitle != null) {
                        Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                trailing()
            }
            content()
        }
    }
}

/** Colored pill showing one of the six compatibility states. */
@Composable
fun StateChip(state: ComponentState, modifier: Modifier = Modifier) {
    val color = stateColor(state)
    Row(
        modifier
            .clip(CircleShape)
            .background(color.copy(alpha = 0.14f))
            .border(1.dp, color.copy(alpha = 0.45f), CircleShape)
            .padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(7.dp).clip(CircleShape).background(color))
        Spacer(Modifier.width(6.dp))
        Text(state.label, color = color, style = MaterialTheme.typography.labelMedium, maxLines = 1)
    }
}

@Composable
fun Tag(text: String, color: Color = MaterialTheme.colorScheme.onSurfaceVariant, modifier: Modifier = Modifier) {
    Text(
        text,
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(color.copy(alpha = 0.12f))
            .padding(horizontal = 7.dp, vertical = 2.dp),
        color = color,
        style = MaterialTheme.typography.labelSmall,
        maxLines = 1,
    )
}

@Composable
fun ConfidenceTag(confidence: Confidence) {
    val color = when (confidence) {
        Confidence.HIGH -> Palette.Green
        Confidence.MEDIUM -> Palette.Gold
        Confidence.LOW -> Palette.Slate
    }
    Tag(confidence.label, color)
}

@Composable
fun EmptyState(icon: ImageVector, title: String, message: String, modifier: Modifier = Modifier, action: @Composable () -> Unit = {}) {
    Column(
        modifier.fillMaxWidth().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            Modifier.size(64.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHigh),
            contentAlignment = Alignment.Center,
        ) { Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(30.dp)) }
        Text(title, style = MaterialTheme.typography.titleMedium)
        Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        action()
    }
}

/** Confirmation dialog; when [requireCheck] is set the user must tick a box first. */
@Composable
fun ConfirmDialog(
    title: String,
    message: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    destructive: Boolean = false,
    requireCheck: String? = null,
    extra: @Composable ColumnScope.() -> Unit = {},
) {
    var checked by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(message)
                extra()
                if (requireCheck != null) {
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clickable { checked = !checked }) {
                        Checkbox(checked = checked, onCheckedChange = { checked = it })
                        Text(requireCheck, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = onConfirm,
                enabled = requireCheck == null || checked,
            ) { Text(confirmLabel, color = if (destructive) MaterialTheme.colorScheme.error else Color.Unspecified) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
fun SearchField(value: String, onValueChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth(),
        singleLine = true,
        placeholder = { Text(placeholder) },
        leadingIcon = { Icon(Icons.Outlined.Search, null) },
        trailingIcon = {
            if (value.isNotEmpty()) IconButton(onClick = { onValueChange("") }) { Icon(Icons.Outlined.Close, "Clear") }
        },
        shape = MaterialTheme.shapes.medium,
    )
}

@Composable
fun KeyValue(key: String, value: String, mono: Boolean = false) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
        Text(key, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.width(140.dp))
        Text(value, style = if (mono) MaterialTheme.typography.bodySmall.copy(fontFamily = CodeFont) else MaterialTheme.typography.bodySmall)
    }
}

@Composable
fun DiagnosticRow(d: Diagnostic, onClick: (() -> Unit)? = null) {
    val color = when (d.severity) {
        Severity.ERROR -> MaterialTheme.colorScheme.error
        Severity.WARNING -> Palette.Gold
        Severity.INFO -> Palette.Sky
    }
    Row(
        Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(vertical = 6.dp, horizontal = 4.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(Modifier.padding(top = 5.dp).size(8.dp).clip(CircleShape).background(color))
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(color = color, fontWeight = FontWeight.Bold)) { append(d.code) }
                    if (d.line > 0) append("  line ${d.line}${if (d.column > 0) ":${d.column}" else ""}")
                    if (d.offset != null) append("  @0x${d.offset!!.toString(16).uppercase()}")
                },
                style = MaterialTheme.typography.labelMedium,
            )
            Text(d.message, style = MaterialTheme.typography.bodySmall)
            if (d.hint != null) Text("Hint: ${d.hint}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Monospace block for code, logs and listings. */
@Composable
fun CodeBlock(text: String, modifier: Modifier = Modifier, maxLines: Int = Int.MAX_VALUE) {
    Surface(color = MaterialTheme.colorScheme.surfaceContainerLowest, shape = MaterialTheme.shapes.small, modifier = modifier.fillMaxWidth()) {
        Box(Modifier.horizontalScroll(rememberScrollState()).padding(12.dp)) {
            Text(text, fontFamily = CodeFont, fontSize = 12.sp, lineHeight = 17.sp, maxLines = maxLines, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
fun ChipRow(content: @Composable () -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { content() }
}

/** Minimal Markdown renderer for the documentation library. */
@Composable
fun MarkdownText(markdown: String, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val lines = markdown.lines()
        var i = 0
        while (i < lines.size) {
            val line = lines[i]
            when {
                line.startsWith("```") -> {
                    val block = StringBuilder()
                    i++
                    while (i < lines.size && !lines[i].startsWith("```")) {
                        block.appendLine(lines[i])
                        i++
                    }
                    CodeBlock(block.toString().trimEnd())
                }
                line.startsWith("## ") -> Text(line.removePrefix("## "), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 6.dp))
                line.startsWith("# ") -> Text(line.removePrefix("# "), style = MaterialTheme.typography.headlineSmall)
                line.startsWith("- ") -> Row {
                    Text("•", color = MaterialTheme.colorScheme.primary, modifier = Modifier.width(18.dp))
                    Text(line.removePrefix("- "), style = MaterialTheme.typography.bodyMedium)
                }
                line.isBlank() -> Spacer(Modifier.height(2.dp))
                else -> Text(line, style = MaterialTheme.typography.bodyMedium)
            }
            i++
        }
    }
}

/** Compact segmented control for switching between views of one screen. */
@Composable
fun SegmentedTabs(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerLow)
            .padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        options.forEachIndexed { i, label ->
            val active = i == selected
            Box(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(11.dp))
                    .background(if (active) MaterialTheme.colorScheme.surfaceContainerHighest else Color.Transparent)
                    .clickable { onSelect(i) }
                    .padding(vertical = 8.dp, horizontal = 6.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    label,
                    style = MaterialTheme.typography.labelLarge,
                    color = if (active) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/** Tinted explanation box for limits and caveats the user should read. */
@Composable
fun InfoBanner(text: String, modifier: Modifier = Modifier, color: Color = Palette.Sky, icon: ImageVector = Icons.Outlined.Info, title: String? = null) {
    Row(
        modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.medium)
            .background(color.copy(alpha = 0.10f))
            .border(1.dp, color.copy(alpha = 0.30f), MaterialTheme.shapes.medium)
            .padding(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(icon, null, tint = color, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(10.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (title != null) Text(title, style = MaterialTheme.typography.titleSmall, color = color)
            Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface)
        }
    }
}

/** Asks before leaving the app for a web page, showing the full address. */
@Composable
fun OpenLinkDialog(title: String, url: String, onOpen: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Open in browser?") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(title, style = MaterialTheme.typography.titleSmall)
                Text(url, fontFamily = CodeFont, fontSize = 12.sp, color = MaterialTheme.colorScheme.primary)
                Text(
                    "Rodwave does not download or install anything from this page. Check the publisher before installing software.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        confirmButton = { TextButton(onClick = { onOpen(); onDismiss() }) { Text("Open") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/** Human-readable byte count. */
fun formatBytes(bytes: Long): String = when {
    bytes < 1024 -> "$bytes B"
    bytes < 1024 * 1024 -> "%.1f KB".format(bytes / 1024.0)
    else -> "%.1f MB".format(bytes / (1024.0 * 1024.0))
}

/** Selectable pill used for filters. */
@Composable
fun FilterPill(label: String, selected: Boolean, color: Color = MaterialTheme.colorScheme.primary, count: Int? = null, onClick: () -> Unit) {
    Row(
        Modifier
            .clip(CircleShape)
            .background(if (selected) color.copy(alpha = 0.18f) else MaterialTheme.colorScheme.surfaceContainer)
            .border(1.dp, if (selected) color.copy(alpha = 0.6f) else MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f), CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.labelLarge, color = if (selected) color else MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        if (count != null) {
            Spacer(Modifier.width(6.dp))
            Text("$count", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Bulleted list of short statements. */
@Composable
fun BulletList(items: List<String>, numbered: Boolean = false, color: Color = MaterialTheme.colorScheme.primary) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        items.forEachIndexed { i, text ->
            Row {
                Text(if (numbered) "${i + 1}." else "•", color = color, style = MaterialTheme.typography.bodySmall, modifier = Modifier.width(20.dp))
                Text(text, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}
