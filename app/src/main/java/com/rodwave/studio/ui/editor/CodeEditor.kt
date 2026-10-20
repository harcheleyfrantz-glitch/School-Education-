package com.rodwave.studio.ui.editor

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isMetaPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rodwave.engine.diagnostics.Severity
import com.rodwave.engine.editor.AutoIndent
import com.rodwave.engine.editor.BlockStructure
import com.rodwave.engine.editor.BracketMatcher
import com.rodwave.engine.editor.LineIndex
import com.rodwave.engine.editor.StyledSpan
import com.rodwave.engine.editor.SyntaxHighlighter
import com.rodwave.engine.editor.SyntaxStyle
import com.rodwave.studio.core.EditorDocument
import com.rodwave.studio.core.Studio
import com.rodwave.studio.ui.theme.CodeFont
import com.rodwave.studio.ui.theme.LocalSyntaxColors
import com.rodwave.studio.ui.theme.Palette
import com.rodwave.studio.ui.theme.SyntaxColors

/** Keyboard actions the editor forwards to its screen. */
class EditorActions(
    val onSave: () -> Unit = {},
    val onCompile: () -> Unit = {},
    val onFind: () -> Unit = {},
    val onFormat: () -> Unit = {},
)

private class SyntaxTransformation(
    private val spans: List<StyledSpan>,
    private val marks: List<Pair<IntRange, SpanStyle>>,
    private val colors: SyntaxColors,
) : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        val length = text.length
        val styled = buildAnnotatedString {
            append(text.text)
            for (s in spans) {
                if (s.start >= length) continue
                val end = s.end.coerceAtMost(length)
                addStyle(
                    SpanStyle(
                        color = colors.of(s.style),
                        fontStyle = if (s.style == SyntaxStyle.COMMENT) FontStyle.Italic else null,
                        fontWeight = if (s.style == SyntaxStyle.KEYWORD || s.style == SyntaxStyle.OPCODE || s.style == SyntaxStyle.LABEL) FontWeight.SemiBold else null,
                    ),
                    s.start, end,
                )
            }
            for ((range, style) in marks) {
                val start = range.first.coerceIn(0, length)
                val end = (range.last + 1).coerceIn(start, length)
                if (end > start) addStyle(style, start, end)
            }
        }
        return TransformedText(styled, OffsetMapping.Identity)
    }
}

@Composable
fun CodeEditor(
    studio: Studio,
    doc: EditorDocument,
    searchMatches: List<IntRange>,
    currentMatch: Int,
    /** Increment to force the caret into view (e.g. after a jump). */
    revealRequest: Int,
    actions: EditorActions,
    modifier: Modifier = Modifier,
) {
    val colors = LocalSyntaxColors.current
    val settings = studio.settings
    val density = LocalDensity.current
    val textStyle = remember(settings.fontSize, colors) {
        TextStyle(
            fontFamily = CodeFont,
            fontSize = settings.fontSize.sp,
            lineHeight = (settings.fontSize * 1.55f).sp,
            color = colors.plain,
            lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None),
        )
    }
    val gutterStyle = remember(settings.fontSize, colors) { TextStyle(fontFamily = CodeFont, fontSize = (settings.fontSize - 2).coerceAtLeast(9).sp, color = colors.gutterText) }
    val highlighter = remember(studio.database) { SyntaxHighlighter(studio.database) }
    val text = doc.value.text
    val caret = doc.value.selection.start
    val spans = remember(text, highlighter, doc.isText) { if (doc.isText) emptyList() else highlighter.highlight(text) }
    val lineIndex = remember(text) { LineIndex(text) }
    val brackets = remember(text, caret, doc.isText) { if (doc.isText) null else BracketMatcher.match(text, caret) }
    val errorColor = MaterialTheme.colorScheme.error

    val marks = remember(searchMatches, currentMatch, brackets, doc.diagnostics, lineIndex, colors) {
        buildList {
            searchMatches.forEachIndexed { i, r ->
                add(r to SpanStyle(background = if (i == currentMatch) colors.searchCurrent else colors.searchMatch))
            }
            brackets?.let { (a, b) ->
                add(a..a to SpanStyle(background = colors.bracket))
                add(b..b to SpanStyle(background = colors.bracket))
            }
            doc.diagnostics.filter { it.line in 1..lineIndex.lineCount && it.severity != Severity.INFO }.forEach { d ->
                val lineStart = lineIndex.lineStart(d.line - 1)
                val start = (lineStart + (d.column - 1).coerceAtLeast(0)).coerceAtMost(text.length)
                val end = (start + d.length.coerceAtLeast(1)).coerceAtMost(text.length)
                val c = if (d.severity == Severity.ERROR) errorColor else Palette.Gold
                if (end > start) add(start until end to SpanStyle(textDecoration = TextDecoration.Underline, background = c.copy(alpha = 0.16f)))
            }
        }
    }
    val transformation = remember(spans, marks, colors) { SyntaxTransformation(spans, marks, colors) }
    val diagnosticLines = remember(doc.diagnostics) {
        doc.diagnostics.filter { it.line > 0 && it.severity != Severity.INFO }.associate { (it.line - 1) to it.severity }
    }

    var layout by remember { mutableStateOf<TextLayoutResult?>(null) }
    val vScroll = rememberScrollState()
    val hScroll = rememberScrollState()
    val measurer = rememberTextMeasurer()
    val padTop = 8.dp
    val padStart = 10.dp
    val digits = lineIndex.lineCount.toString().length.coerceAtLeast(2)
    val gutterWidth = (digits * (settings.fontSize * 0.68f) + 22).dp

    fun handleChange(incoming: TextFieldValue) {
        val old = doc.value
        var next = incoming
        if (settings.autoIndent && !doc.readOnly && old.selection.collapsed && incoming.selection.collapsed) {
            val at = old.selection.start
            val insertedOne = incoming.text.length == old.text.length + 1 && incoming.selection.start == at + 1 &&
                incoming.text.regionMatches(0, old.text, 0, at) && incoming.text.regionMatches(at + 1, old.text, at, old.text.length - at)
            if (insertedOne) {
                val ch = incoming.text[at]
                if (ch == '\n') {
                    val insertion = AutoIndent.newlineInsertion(old.text, at)
                    val t = old.text.substring(0, at) + insertion + old.text.substring(at)
                    next = TextFieldValue(t, TextRange(at + insertion.length))
                } else if (ch.isLetter()) {
                    val idx = LineIndex(incoming.text)
                    val line = idx.lineOf(at)
                    val start = idx.lineStart(line)
                    val endOfLine = incoming.text.indexOf('\n', start).let { if (it < 0) incoming.text.length else it }
                    val lineText = incoming.text.substring(start, endOfLine)
                    if (lineText.trim().lowercase() in setOf("end", "else", "then", "until")) {
                        AutoIndent.dedentFor(incoming.text, line)?.let { wanted ->
                            val current = lineText.takeWhile { it == ' ' || it == '\t' }
                            val t = incoming.text.substring(0, start) + wanted + incoming.text.substring(start + current.length)
                            next = TextFieldValue(t, TextRange((incoming.selection.start - current.length + wanted.length).coerceIn(0, t.length)))
                        }
                    }
                }
            }
        }
        studio.editor.update(doc, next)
    }

    fun insertAtCaret(insert: String) {
        val v = doc.value
        val t = v.text.replaceRange(v.selection.min, v.selection.max, insert)
        studio.editor.update(doc, TextFieldValue(t, TextRange(v.selection.min + insert.length)))
    }

    fun handleKey(e: KeyEvent): Boolean {
        if (e.type != KeyEventType.KeyDown) return false
        val ctrl = e.isCtrlPressed || e.isMetaPressed
        return when {
            ctrl && e.key == Key.Z && !e.isShiftPressed -> { studio.editor.undo(doc); true }
            ctrl && (e.key == Key.Y || (e.key == Key.Z && e.isShiftPressed)) -> { studio.editor.redo(doc); true }
            ctrl && e.key == Key.S -> { actions.onSave(); true }
            ctrl && e.isShiftPressed && e.key == Key.F -> { actions.onFormat(); true }
            ctrl && e.key == Key.F -> { actions.onFind(); true }
            ctrl && e.key == Key.B -> { actions.onCompile(); true }
            e.key == Key.Tab && !ctrl && !doc.readOnly -> {
                if (e.isShiftPressed) outdentLine(studio, doc) else insertAtCaret(BlockStructure.INDENT)
                true
            }
            else -> false
        }
    }

    // Keep the caret visible after typing and programmatic jumps.
    LaunchedEffect(caret, layout, revealRequest) {
        val l = layout ?: return@LaunchedEffect
        // Before the first measure the viewport is 0 px and every caret would look off-screen.
        if (vScroll.viewportSize == 0 || hScroll.viewportSize == 0) return@LaunchedEffect
        val rect = l.getCursorRect(caret.coerceIn(0, l.layoutInput.text.length))
        val pad = with(density) { padTop.toPx() }
        val margin = with(density) { 24.dp.toPx() }
        val top = rect.top + pad
        val bottom = rect.bottom + pad
        if (top < vScroll.value) vScroll.scrollTo((top - margin).toInt().coerceAtLeast(0))
        else if (bottom > vScroll.value + vScroll.viewportSize) vScroll.scrollTo((bottom - vScroll.viewportSize + margin).toInt())
        val left = rect.left + with(density) { padStart.toPx() }
        if (left < hScroll.value) hScroll.scrollTo((left - margin).toInt().coerceAtLeast(0))
        else if (left > hScroll.value + hScroll.viewportSize - margin) hScroll.scrollTo((left - hScroll.viewportSize + margin * 2).toInt())
    }

    BoxWithConstraints(modifier.background(MaterialTheme.colorScheme.surfaceContainerLowest)) {
        val viewportWidth = maxWidth
        Row(Modifier.fillMaxSize().verticalScroll(vScroll)) {
            val contentHeight = with(density) { ((layout?.size?.height ?: 0) + padTop.toPx() * 2).toDp() }
            Canvas(Modifier.width(gutterWidth).height(contentHeight).background(colors.gutter)) {
                val l = layout ?: return@Canvas
                val pad = padTop.toPx()
                val firstVisible = l.getLineForVerticalPosition((vScroll.value - pad).coerceAtLeast(0f))
                val lastVisible = l.getLineForVerticalPosition((vScroll.value + vScroll.viewportSize - pad).coerceAtLeast(0f))
                val caretLine = l.getLineForOffset(caret.coerceIn(0, l.layoutInput.text.length))
                for (i in firstVisible..lastVisible.coerceAtMost(l.lineCount - 1)) {
                    val top = l.getLineTop(i) + pad
                    val bottom = l.getLineBottom(i) + pad
                    val label = measurer.measure("${i + 1}", if (i == caretLine) gutterStyle.copy(color = colors.plain) else gutterStyle)
                    drawText(label, topLeft = Offset(size.width - 8.dp.toPx() - label.size.width, top + (bottom - top - label.size.height) / 2))
                    diagnosticLines[i]?.let { sev ->
                        drawCircle(if (sev == Severity.ERROR) errorColor else Palette.Gold, radius = 3.dp.toPx(), center = Offset(6.dp.toPx(), (top + bottom) / 2))
                    }
                }
            }
            Box(Modifier.weight(1f).horizontalScroll(hScroll)) {
                BasicTextField(
                    value = doc.value,
                    onValueChange = ::handleChange,
                    readOnly = doc.readOnly,
                    textStyle = textStyle,
                    cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                    visualTransformation = transformation,
                    onTextLayout = { layout = it },
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.None,
                        autoCorrectEnabled = false,
                        keyboardType = KeyboardType.Ascii,
                    ),
                    modifier = Modifier
                        .widthIn(min = viewportWidth - gutterWidth)
                        .onPreviewKeyEvent(::handleKey)
                        .padding(start = padStart, end = 48.dp, top = padTop, bottom = padTop)
                        .drawBehind {
                            val l = layout ?: return@drawBehind
                            val line = l.getLineForOffset(caret.coerceIn(0, l.layoutInput.text.length))
                            drawRect(colors.caretLine, topLeft = Offset(-padStart.toPx(), l.getLineTop(line)), size = Size(size.width + padStart.toPx() + 48.dp.toPx(), l.getLineBottom(line) - l.getLineTop(line)))
                        },
                )
            }
        }
    }
}

/** Removes one indentation level from the caret's line. */
fun outdentLine(studio: Studio, doc: EditorDocument) {
    val v = doc.value
    val idx = LineIndex(v.text)
    val start = idx.lineStart(idx.lineOf(v.selection.start))
    val leading = v.text.substring(start).takeWhile { it == ' ' }.length.coerceAtMost(BlockStructure.INDENT.length)
    if (leading == 0) return
    val t = v.text.removeRange(start, start + leading)
    studio.editor.update(doc, TextFieldValue(t, TextRange((v.selection.start - leading).coerceAtLeast(start))))
}
