package com.rodwave.engine.editor

import com.rodwave.engine.compiler.ModelTable
import com.rodwave.engine.compiler.ScriptCompiler
import com.rodwave.engine.lang.Lexer
import com.rodwave.engine.lang.Token
import com.rodwave.engine.lang.TokenKind
import com.rodwave.engine.opcode.OpcodeDatabase
import com.rodwave.engine.opcode.OpcodeDefinition

/** Converts between character offsets and 0-based line/column positions. */
class LineIndex(text: String) {
    private val starts: IntArray = buildList {
        add(0)
        text.forEachIndexed { i, c -> if (c == '\n') add(i + 1) }
    }.toIntArray()

    val lineCount: Int get() = starts.size

    fun lineOf(offset: Int): Int {
        val i = starts.binarySearch(offset)
        return if (i >= 0) i else -i - 2
    }

    fun lineStart(line: Int): Int = starts[line.coerceIn(0, starts.lastIndex)]
    fun columnOf(offset: Int): Int = offset - lineStart(lineOf(offset))
}

// ---------------------------------------------------------------------------------------- brackets

object BracketMatcher {
    /** If the caret touches a parenthesis, returns the offsets of it and its partner. */
    fun match(text: String, caret: Int): Pair<Int, Int>? {
        val tokens = Lexer(text).tokenize()
        val parens = tokens.filter { it.kind == TokenKind.LPAREN || it.kind == TokenKind.RPAREN }
        val pairs = HashMap<Int, Int>()
        val stack = ArrayDeque<Int>()
        for (t in parens) {
            if (t.kind == TokenKind.LPAREN) {
                stack.addLast(t.start)
            } else {
                val open = stack.removeLastOrNull() ?: continue
                pairs[open] = t.start
                pairs[t.start] = open
            }
        }
        // Block comments and directives in braces match their own ends.
        tokens.filter { (it.kind == TokenKind.COMMENT || it.kind == TokenKind.DIRECTIVE) && it.text.startsWith("{") && it.text.endsWith("}") }
            .forEach { pairs[it.start] = it.end - 1; pairs[it.end - 1] = it.start }
        for (candidate in listOf(caret, caret - 1)) {
            pairs[candidate]?.let { return candidate to it }
        }
        return null
    }
}

// ---------------------------------------------------------------------------------------- search

data class SearchOptions(val caseSensitive: Boolean = false, val wholeWord: Boolean = false, val regex: Boolean = false)

data class SearchResult(val matches: List<IntRange>, val error: String? = null)

object SearchEngine {
    const val MAX_MATCHES = 10_000

    fun pattern(query: String, options: SearchOptions): Regex? {
        if (query.isEmpty()) return null
        val body = if (options.regex) query else Regex.escape(query)
        val bounded = if (options.wholeWord) "(?<![A-Za-z0-9_])(?:$body)(?![A-Za-z0-9_])" else body
        return Regex(bounded, if (options.caseSensitive) emptySet() else setOf(RegexOption.IGNORE_CASE))
    }

    fun findAll(text: String, query: String, options: SearchOptions = SearchOptions()): SearchResult {
        val regex = try {
            pattern(query, options)
        } catch (e: Exception) {
            return SearchResult(emptyList(), "Invalid regular expression: ${e.message?.lineSequence()?.firstOrNull()}")
        } ?: return SearchResult(emptyList())
        val matches = regex.findAll(text).filter { it.range.last >= it.range.first }.take(MAX_MATCHES).map { it.range }.toList()
        return SearchResult(matches)
    }

    /** Index of the first match at or after [caret], wrapping around. */
    fun nextIndex(matches: List<IntRange>, caret: Int): Int? =
        if (matches.isEmpty()) null else matches.indexOfFirst { it.first >= caret }.let { if (it < 0) 0 else it }

    fun previousIndex(matches: List<IntRange>, caret: Int): Int? =
        if (matches.isEmpty()) null else matches.indexOfLast { it.last < caret }.let { if (it < 0) matches.lastIndex else it }

    fun replaceRange(text: String, range: IntRange, replacement: String): String =
        text.substring(0, range.first) + replacement + text.substring(range.last + 1)

    /**
     * The text that replaces the match at [range]: [replacement] itself, or with `$0`..`$9` expanded
     * from the match's groups in regex mode. Returns null if [range] is no longer a match.
     */
    fun replacementFor(text: String, range: IntRange, query: String, replacement: String, options: SearchOptions = SearchOptions()): String? {
        val regex = runCatching { pattern(query, options) }.getOrNull() ?: return null
        val match = regex.find(text, range.first)?.takeIf { it.range == range } ?: return null
        return expand(match, replacement, options)
    }

    /** Replaces every match; returns the new text and the number of replacements. */
    fun replaceAll(text: String, query: String, replacement: String, options: SearchOptions = SearchOptions()): Pair<String, Int> {
        val regex = runCatching { pattern(query, options) }.getOrNull() ?: return text to 0
        var count = 0
        val result = regex.replace(text) {
            count++
            expand(it, replacement, options)
        }
        return result to count
    }

    private fun expand(match: MatchResult, replacement: String, options: SearchOptions): String =
        if (options.regex) Regex("\\$(\\d)").replace(replacement) { g -> match.groupValues.getOrNull(g.groupValues[1].toInt()) ?: g.value } else replacement
}

// ---------------------------------------------------------------------------------------- completion

enum class CompletionKind { KEYWORD, COMMAND, LABEL, VARIABLE, CONSTANT, ENUM_MEMBER, MODEL }

data class Completion(val label: String, val insertText: String, val detail: String, val kind: CompletionKind, val opcode: Int? = null)

data class CompletionResult(val replaceStart: Int, val replaceEnd: Int, val prefix: String, val items: List<Completion>)

/** Context-aware completion from the opcode database, the current file and model names. */
class CompletionEngine(private val database: OpcodeDatabase, private val models: ModelTable = ModelTable.SAN_ANDREAS) {

    fun complete(text: String, caret: Int, limit: Int = 60): CompletionResult {
        val safeCaret = caret.coerceIn(0, text.length)
        var start = safeCaret
        while (start > 0 && (text[start - 1].isLetterOrDigit() || text[start - 1] in "_.@#$")) start--
        val prefix = text.substring(start, safeCaret)
        val lineStart = text.lastIndexOf('\n', (start - 1).coerceAtLeast(0)).let { if (start == 0) 0 else it + 1 }
        val before = text.substring(lineStart, start)
        val lineHasOpcode = Regex("^\\s*(not\\s+)?[0-9A-Fa-f]{4}:").containsMatchIn(before)
        val atStatementStart = before.isBlank() || Regex("^\\s*(not|if|while|until|and|or)\\s*$", RegexOption.IGNORE_CASE).matches(before)

        val items: List<Completion> = when {
            prefix.startsWith("@") -> labels(text).filter { it.startsWith(prefix.drop(1), true) }
                .map { Completion("@$it", "@$it", "label", CompletionKind.LABEL) }
            prefix.startsWith("#") -> modelCompletions(prefix.drop(1))
            '.' in prefix -> enumCompletions(prefix)
            prefix.length == 4 && prefix.all { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' } && atStatementStart ->
                database[prefix.toInt(16)]?.let { listOf(commandCompletion(it, withOpcode = true)) }.orEmpty()
            else -> {
                val p = prefix.lowercase()
                val result = ArrayList<Completion>()
                if (atStatementStart) {
                    KEYWORDS.filter { it.startsWith(p) && p.isNotEmpty() }.forEach { result += Completion(it, it, "keyword", CompletionKind.KEYWORD) }
                }
                if (atStatementStart || lineHasOpcode) {
                    if (p.length >= 2) {
                        database.search(p, limit = limit).forEach { def ->
                            result += commandCompletion(def, withOpcode = atStatementStart && !lineHasOpcode)
                        }
                    }
                }
                symbols(text).filter { it.first.startsWith(p, true) && p.isNotEmpty() }
                    .forEach { (name, kind) -> result += Completion(name, name, kind.name.lowercase().replace('_', ' '), kind) }
                listOf("TIMERA", "TIMERB", "true", "false").filter { p.isNotEmpty() && it.startsWith(p, true) }
                    .forEach { result += Completion(it, it, "built-in", CompletionKind.CONSTANT) }
                result
            }
        }
        val distinct = items.distinctBy { it.label + it.insertText }.take(limit)
        return CompletionResult(start, safeCaret, prefix, distinct)
    }

    private fun commandCompletion(def: OpcodeDefinition, withOpcode: Boolean): Completion {
        val insert = if (withOpcode) "${def.hexId}: ${def.keyword} " else "${def.keyword} "
        val label = "${def.hexId} ${def.keyword}"
        return Completion(label, insert, def.description.ifBlank { def.signature }, CompletionKind.COMMAND, def.id)
    }

    private fun modelCompletions(prefix: String): List<Completion> {
        val names = (400..611).mapNotNull { models.nameOf(it) } + (321..372).mapNotNull { models.nameOf(it) }
        return names.filter { it.startsWith(prefix, true) }.take(40).map { Completion("#$it", "#$it", "model ${models.idOf(it)}", CompletionKind.MODEL) }
    }

    private fun enumCompletions(prefix: String): List<Completion> {
        val enumName = prefix.substringBefore('.')
        val member = prefix.substringAfter('.')
        val e = database.enum(enumName) ?: return database.enums.filter { it.name.startsWith(enumName, true) }
            .map { Completion(it.name + ".", it.name + ".", "enum", CompletionKind.ENUM_MEMBER) }
        return e.members.filter { it.key.startsWith(member, true) }
            .map { (k, v) -> Completion("${e.name}.$k", "${e.name}.$k", "= $v", CompletionKind.ENUM_MEMBER) }
    }

    private fun labels(text: String): List<String> =
        Lexer(text).tokenize().filter { it.kind == TokenKind.LABEL_DEF }.map { it.text.substring(1) }.distinct()

    /** Constants and named variables declared in the file. */
    private fun symbols(text: String): List<Pair<String, CompletionKind>> {
        val out = ArrayList<Pair<String, CompletionKind>>()
        for (line in text.lineSequence()) {
            val t = line.trim()
            val lower = t.lowercase()
            when {
                lower.startsWith("const ") -> t.substring(6).split(',').mapNotNull { it.substringBefore('=').trim().takeIf { n -> n.isNotEmpty() && n.all { c -> c.isLetterOrDigit() || c == '_' } } }
                    .forEach { out += it to CompletionKind.CONSTANT }
                lower.startsWith("int ") || lower.startsWith("float ") -> t.substringAfter(' ').split(',').map { it.substringBefore('=').trim() }
                    .filter { n -> n.isNotEmpty() && n[0].isLetter() && n.all { c -> c.isLetterOrDigit() || c == '_' } }
                    .forEach { out += it to CompletionKind.VARIABLE }
                Regex("^[A-Za-z_][A-Za-z0-9_]*\\s*=\\s*[^=]").containsMatchIn(t) && !lower.startsWith("if") ->
                    t.substringBefore('=').trim().takeIf { it.all { c -> c.isLetterOrDigit() || c == '_' } && it.uppercase() == it }?.let { out += it to CompletionKind.CONSTANT }
            }
        }
        return out.distinctBy { it.first.lowercase() }
    }

    companion object {
        val KEYWORDS = listOf(
            "if", "if and", "if or", "then", "else", "end", "while", "while true", "repeat", "until", "for", "break",
            "continue", "not", "const", "int", "float", "hex", "jump", "jf", "gosub", "return", "wait",
        )
    }
}

// ---------------------------------------------------------------------------------------- command help

data class CommandHelp(
    val definition: OpcodeDefinition,
    /** Index of the parameter the caret is on (or after), or -1 before the first one. */
    val paramIndex: Int,
    val writtenParams: Int,
) {
    /** One-line status text in the style of Sanny Builder's status bar. */
    val statusText: String
        get() = buildString {
            val p = definition.params
            append(definition.hexId).append(": ")
            if (definition.isVariadic) append("expecting at least ${definition.fixedParamCount} params") else append("expecting ${p.size} params")
            if (definition.description.isNotBlank()) append(" | ").append(definition.description)
        }

    val currentParamText: String?
        get() {
            val p = definition.params.getOrNull(paramIndex) ?: return null
            return (if (p.isOutput) "output " else "") + p.displayName + if (p.name.isNotBlank()) ": ${p.typeName}" else ""
        }
}

object CommandHelpProvider {
    /** Describes the command on the caret's line and which parameter is being edited. */
    fun at(text: String, caret: Int, database: OpcodeDatabase): CommandHelp? {
        val c = caret.coerceIn(0, text.length)
        val lineStart = text.lastIndexOf('\n', (c - 1).coerceAtLeast(0)).let { if (c == 0) 0 else it + 1 }
        val lineEnd = text.indexOf('\n', c).let { if (it < 0) text.length else it }
        val line = text.substring(lineStart, lineEnd)
        val tokens: List<Token> = Lexer(line).tokenize().filter { !it.isTrivia && it.kind != TokenKind.NEWLINE }
        if (tokens.isEmpty()) return null
        var i = 0
        while (i < tokens.size && (tokens[i].isWord("not") || tokens[i].isWord("if") || tokens[i].isWord("while") || tokens[i].isWord("until"))) i++
        val head = tokens.getOrNull(i) ?: return null
        val def = when (head.kind) {
            TokenKind.OPCODE -> database[head.text.dropLast(1).toInt(16) and 0x7FFF]
            TokenKind.IDENT -> ScriptCompiler.KEYWORD_ALIASES[head.text.lowercase()]?.let { database[it] }
                ?: database.findByName(head.text).firstOrNull()
            else -> null
        } ?: return null
        val local = c - lineStart
        val values = tokens.drop(i + 1).filter { it.isValue }
        val written = values.size
        val before = values.count { it.end <= local }
        val onToken = values.indexOfFirst { local in it.start..it.end }
        val paramIndex = if (onToken >= 0) onToken else before
        return CommandHelp(def, paramIndex, written)
    }
}

// ---------------------------------------------------------------------------------------- outline

enum class OutlineKind { LABEL, CONSTANT, VARIABLE, DIRECTIVE }

data class OutlineItem(val name: String, val line: Int, val kind: OutlineKind)

object Outline {
    fun of(text: String): List<OutlineItem> {
        val items = ArrayList<OutlineItem>()
        for (t in Lexer(text).tokenize()) {
            when (t.kind) {
                TokenKind.LABEL_DEF -> items += OutlineItem(t.text.substring(1), t.line - 1, OutlineKind.LABEL)
                TokenKind.DIRECTIVE -> items += OutlineItem(t.text, t.line - 1, OutlineKind.DIRECTIVE)
                else -> Unit
            }
        }
        text.lineSequence().forEachIndexed { i, raw ->
            val l = raw.trim().lowercase()
            if (l.startsWith("const ")) {
                raw.trim().substring(6).split(',').mapNotNull { it.substringBefore('=').trim().takeIf { n -> n.isNotEmpty() } }
                    .forEach { items += OutlineItem(it, i, OutlineKind.CONSTANT) }
            } else if (l.startsWith("int ") || l.startsWith("float ")) {
                raw.trim().substringAfter(' ').split(',').map { it.substringBefore('=').trim() }.filter { it.isNotEmpty() }
                    .forEach { items += OutlineItem(it, i, OutlineKind.VARIABLE) }
            }
        }
        return items.sortedBy { it.line }
    }

    /** 0-based line of the label definition, or null. */
    fun findLabel(text: String, name: String): Int? =
        Lexer(text).tokenize().firstOrNull { it.kind == TokenKind.LABEL_DEF && it.text.substring(1).equals(name.removePrefix("@"), true) }?.line?.minus(1)
}
