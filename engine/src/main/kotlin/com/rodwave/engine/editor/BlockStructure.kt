package com.rodwave.engine.editor

/**
 * Line-level block structure of a script (if/then/else/end, loops, const/var/hex blocks), shared
 * by the formatter, auto-indent and block matching. Works on plain text and tolerates broken code.
 */
object BlockStructure {
    const val INDENT = "    "

    private enum class Block { IF_CONDITIONS, IF_BODY, LOOP, REPEAT, DATA }
    private data class Open(val block: Block, val level: Int, val line: Int)

    private val JF_WORDS = setOf("jf", "goto_if_false", "jump_if_false", "else_jump")

    data class LineInfo(
        /** Indentation level this line should have. */
        val level: Int,
        /** Line index of the block opener this line belongs to (for then/else/end/until/jf). */
        val partnerLine: Int?,
        /** True if the line is inside a multi-line comment and must not be changed. */
        val inComment: Boolean,
    )

    fun analyze(lines: List<String>): List<LineInfo> {
        val stack = ArrayDeque<Open>()
        val result = ArrayList<LineInfo>(lines.size)
        var inBraceComment = false
        var inStarComment = false
        for ((index, raw) in lines.withIndex()) {
            if (inBraceComment || inStarComment) {
                result += LineInfo(stack.size, null, true)
                if (inBraceComment && raw.contains('}')) inBraceComment = false
                if (inStarComment && raw.contains("*/")) inStarComment = false
                continue
            }
            val code = stripTrailingComment(raw)
            val trimmed = code.trim()
            // Track comments that continue onto the next line.
            val braceOpen = raw.indexOf('{').let { it >= 0 && !raw.startsWith("{$", it) && raw.indexOf('}', it) < 0 && !insideString(raw, it) }
            val starOpen = raw.indexOf("/*").let { it >= 0 && raw.indexOf("*/", it) < 0 && !insideString(raw, it) }
            val words = trimmed.split(Regex("\\s+")).filter { it.isNotEmpty() }
            val first = words.firstOrNull()?.lowercase().orEmpty()
            val top = stack.lastOrNull()
            var level = stack.size
            var partner: Int? = null
            when {
                trimmed.isEmpty() -> Unit
                trimmed.startsWith(":") || trimmed.startsWith("{$") -> level = 0
                top?.block == Block.DATA && first != "end" -> Unit
                top?.block == Block.IF_CONDITIONS && (first == "then" || first in JF_WORDS || first == "004d:") -> {
                    level = top.level
                    partner = top.line
                    stack.removeLast()
                    if (first == "then") stack.addLast(Open(Block.IF_BODY, top.level, top.line))
                }
                first == "else" && top?.block == Block.IF_BODY -> {
                    level = top.level
                    partner = top.line
                }
                first == "end" && top != null && top.block != Block.IF_CONDITIONS && top.block != Block.REPEAT -> {
                    level = top.level
                    partner = top.line
                    stack.removeLast()
                }
                first == "until" && top?.block == Block.REPEAT -> {
                    level = top.level
                    partner = top.line
                    stack.removeLast()
                }
                first == "if" -> {
                    val endsWithThen = words.size > 1 && words.last().equals("then", true)
                    stack.addLast(Open(if (endsWithThen) Block.IF_BODY else Block.IF_CONDITIONS, level, index))
                }
                first == "while" || first == "for" -> stack.addLast(Open(Block.LOOP, level, index))
                first == "repeat" -> stack.addLast(Open(Block.REPEAT, level, index))
                (first == "const" || first == "var" || first == "hex") && words.size == 1 -> stack.addLast(Open(Block.DATA, level, index))
                top?.block == Block.IF_CONDITIONS && words.last().equals("then", true) -> {
                    // A condition line ending in 'then' starts the body.
                    stack.removeLast()
                    stack.addLast(Open(Block.IF_BODY, top.level, top.line))
                }
            }
            result += LineInfo(level, partner, false)
            if (braceOpen) inBraceComment = true
            if (starOpen) inStarComment = true
        }
        return result
    }

    private fun stripTrailingComment(line: String): String {
        var inSingle = false
        var inDouble = false
        var i = 0
        while (i < line.length) {
            val c = line[i]
            when {
                c == '\'' && !inDouble -> inSingle = !inSingle
                c == '"' && !inSingle -> inDouble = !inDouble
                !inSingle && !inDouble && c == '/' && i + 1 < line.length && line[i + 1] == '/' -> return line.substring(0, i)
            }
            i++
        }
        return line
    }

    private fun insideString(line: String, at: Int): Boolean {
        var inSingle = false
        var inDouble = false
        for (i in 0 until at) {
            when (line[i]) {
                '\'' -> if (!inDouble) inSingle = !inSingle
                '"' -> if (!inSingle) inDouble = !inDouble
            }
        }
        return inSingle || inDouble
    }

    /** Re-indents every line; only leading and trailing whitespace changes. */
    fun format(text: String): String {
        val lines = text.split('\n').map { it.trimEnd('\r') }
        val info = analyze(lines)
        return lines.mapIndexed { i, line ->
            when {
                info[i].inComment -> line.trimEnd()
                line.isBlank() -> ""
                else -> INDENT.repeat(info[i].level) + line.trim()
            }
        }.joinToString("\n")
    }

    /** Lines related to [lineIndex] through block structure (opener, then/else, end). */
    fun relatedLines(text: String, lineIndex: Int): List<Int> {
        val lines = text.split('\n')
        val info = analyze(lines)
        if (lineIndex !in info.indices) return emptyList()
        val opener = info[lineIndex].partnerLine ?: lineIndex
        val members = info.indices.filter { info[it].partnerLine == opener }
        return if (members.isEmpty()) emptyList() else (listOf(opener) + members).distinct().sorted()
    }
}

/** Indentation helpers used while typing. */
object AutoIndent {
    private val OPENERS = setOf("then", "else", "repeat", "while", "for", "if")
    private val CLOSERS = setOf("end", "else", "then", "until")

    /** Text to insert when the user presses Enter at [cursor]: a newline plus indentation. */
    fun newlineInsertion(text: String, cursor: Int): String {
        val lineStart = text.lastIndexOf('\n', (cursor - 1).coerceAtLeast(0)).let { if (cursor == 0) 0 else it + 1 }
        val currentLine = text.substring(lineStart, cursor)
        val indent = currentLine.takeWhile { it == ' ' || it == '\t' }
        val first = currentLine.trim().split(Regex("\\s+")).firstOrNull()?.lowercase().orEmpty()
        val opensBlock = first in OPENERS || (first in setOf("const", "var", "hex") && currentLine.trim().equals(first, true)) ||
            currentLine.trimEnd().endsWith(" then", ignoreCase = true)
        return "\n" + indent + if (opensBlock) BlockStructure.INDENT else ""
    }

    /**
     * After the user types a word at the start of a line, returns the corrected line indentation if
     * that word closes a block (end, else, then, until), or null when nothing should change.
     */
    fun dedentFor(text: String, lineIndex: Int): String? {
        val lines = text.split('\n')
        val line = lines.getOrNull(lineIndex) ?: return null
        val first = line.trim().split(Regex("\\s+")).firstOrNull()?.lowercase() ?: return null
        if (first !in CLOSERS) return null
        val level = BlockStructure.analyze(lines)[lineIndex].level
        val wanted = BlockStructure.INDENT.repeat(level)
        val current = line.takeWhile { it == ' ' || it == '\t' }
        return if (current == wanted) null else wanted
    }
}
