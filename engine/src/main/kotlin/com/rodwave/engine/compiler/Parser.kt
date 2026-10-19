package com.rodwave.engine.compiler

import com.rodwave.engine.diagnostics.DiagnosticSink
import com.rodwave.engine.lang.Lexer
import com.rodwave.engine.lang.Token
import com.rodwave.engine.lang.TokenKind
import com.rodwave.engine.scm.ArrayElementType
import com.rodwave.engine.scm.VarStorage

/**
 * Line-oriented parser for Rodwave script source.
 *
 * Every statement occupies one logical line; block constructs (`if`/`while`/`repeat`/`for`,
 * `const`/`var`/`hex` blocks) span several lines and end with `end` (or `until`).
 */
class Parser(source: String, private val file: String?, private val sink: DiagnosticSink) {
    private class Line(val tokens: List<Token>) {
        val head: Token get() = tokens[0]
    }

    private val lines: List<Line>
    private var index = 0

    init {
        val all = Lexer(source).tokenize()
        val result = ArrayList<Line>()
        var current = ArrayList<Token>()
        for (t in all) {
            when {
                t.kind == TokenKind.NEWLINE -> {
                    if (current.isNotEmpty()) result += Line(current)
                    current = ArrayList()
                }
                t.isTrivia -> Unit
                else -> current += t
            }
        }
        if (current.isNotEmpty()) result += Line(current)
        lines = result
    }

    fun parse(): List<Stmt> {
        val (body, terminator) = parseBlock(emptySet())
        if (terminator != null) error(terminator.head, "P001", "Unexpected '${terminator.head.text}'")
        return body
    }

    // ---------------------------------------------------------------- blocks

    private fun parseBlock(terminators: Set<String>): Pair<List<Stmt>, Line?> {
        val out = ArrayList<Stmt>()
        while (index < lines.size) {
            val line = lines[index]
            val head = line.head
            if (head.kind == TokenKind.IDENT && head.text.lowercase() in terminators) {
                index++
                return out to line
            }
            index++
            parseStatement(line.tokens, out)
        }
        return out to null
    }

    private fun parseStatement(tokens: List<Token>, out: MutableList<Stmt>) {
        val head = tokens[0]
        when (head.kind) {
            TokenKind.DIRECTIVE -> {
                val inner = head.text.removePrefix("{$").removeSuffix("}").trim()
                val name = inner.substringBefore(' ').trim().uppercase()
                val value = inner.substringAfter(' ', "").trim()
                out += DirectiveStmt(name, value, loc(head))
                if (tokens.size > 1) parseStatement(tokens.drop(1), out)
            }
            TokenKind.LABEL_DEF -> {
                out += LabelStmt(head.text.substring(1), loc(head))
                if (tokens.size > 1) parseStatement(tokens.drop(1), out)
            }
            TokenKind.OPCODE -> parseOpcodeCommand(tokens, negatedPrefix = false)?.let { out += it }
            TokenKind.IDENT -> parseKeywordStatement(tokens, out)
            TokenKind.GLOBAL_VAR, TokenKind.LOCAL_VAR -> parseAssignment(tokens)?.let { out += it }
            TokenKind.ERROR -> error(head, "P002", "Unrecognised text '${head.text}'")
            else -> error(head, "P003", "A statement cannot start with '${head.text}'")
        }
    }

    private fun parseKeywordStatement(tokens: List<Token>, out: MutableList<Stmt>) {
        val head = tokens[0]
        when (head.text.lowercase()) {
            "if" -> out += parseIf(tokens)
            "while" -> parseWhile(tokens)?.let { out += it }
            "repeat" -> parseRepeat(tokens)?.let { out += it }
            "for" -> parseFor(tokens)?.let { out += it }
            "break" -> {
                expectEnd(tokens, 1)
                out += BreakStmt(loc(head))
            }
            "continue" -> {
                expectEnd(tokens, 1)
                out += ContinueStmt(loc(head))
            }
            "const" -> parseConst(tokens)?.let { out += it }
            "var" -> parseVarBlock(tokens)?.let { out += it }
            "int", "float" -> parseDecl(tokens)?.let { out += it }
            "hex" -> parseHex(tokens)?.let { out += it }
            "not" -> {
                if (tokens.size < 2) {
                    error(head, "P004", "'not' must be followed by a command")
                    return
                }
                val rest = tokens.drop(1)
                if (rest[0].kind == TokenKind.OPCODE) {
                    parseOpcodeCommand(rest, negatedPrefix = true)?.let { out += it }
                } else if (rest[0].kind == TokenKind.IDENT) {
                    parseKeywordCommand(rest, negated = true)?.let { out += it }
                } else {
                    error(rest[0], "P004", "'not' must be followed by a command")
                }
            }
            "end", "else", "until", "then" -> error(head, "P005", "'${head.text}' without a matching block start")
            else -> {
                if (tokens.size >= 2 && tokens[1].kind == TokenKind.OPERATOR ||
                    tokens.size >= 2 && tokens[1].kind == TokenKind.LPAREN && tokens.any { it.kind == TokenKind.OPERATOR }
                ) {
                    parseAssignment(tokens)?.let { out += it }
                } else {
                    parseKeywordCommand(tokens, negated = false)?.let { out += it }
                }
            }
        }
    }

    // ---------------------------------------------------------------- commands

    private fun parseOpcodeCommand(tokens: List<Token>, negatedPrefix: Boolean): CommandStmt? {
        val head = tokens[0]
        val word = head.text.dropLast(1).toInt(16)
        val args = parseArgs(tokens, 1, opcodeForm = true) ?: return null
        val negated = negatedPrefix || (word and 0x8000) != 0
        return CommandStmt(word and 0x7FFF, null, negated, args, SourceLoc.span(head, tokens.last(), file))
    }

    private fun parseKeywordCommand(tokens: List<Token>, negated: Boolean): CommandStmt? {
        val head = tokens[0]
        val args = parseArgs(tokens, 1, opcodeForm = false) ?: return null
        return CommandStmt(null, head.text, negated, args, SourceLoc.span(head, tokens.last(), file))
    }

    /**
     * Parses parameters. In opcode form (`0001: wait 0 ms`) plain words, operators and punctuation
     * are descriptive text and only value-like tokens are parameters, as in Sanny Builder.
     */
    private fun parseArgs(tokens: List<Token>, from: Int, opcodeForm: Boolean): List<Arg>? {
        val args = ArrayList<Arg>()
        var i = from
        while (i < tokens.size) {
            val t = tokens[i]
            when {
                t.kind == TokenKind.ERROR -> {
                    error(t, "P006", "Unrecognised text '${t.text}'")
                    return null
                }
                t.kind == TokenKind.OPERATOR || t.kind == TokenKind.COMMA || t.kind == TokenKind.LPAREN || t.kind == TokenKind.RPAREN -> {
                    if (!opcodeForm) {
                        error(t, "P007", "Unexpected '${t.text}' in command parameters")
                        return null
                    }
                    i++
                }
                t.kind == TokenKind.ARRAY_SIZE -> {
                    error(t, "P008", "Array size '${t.text}' outside an array reference")
                    return null
                }
                t.kind == TokenKind.OPCODE || t.kind == TokenKind.LABEL_DEF || t.kind == TokenKind.DIRECTIVE -> {
                    error(t, "P009", "Only one statement per line is allowed")
                    return null
                }
                else -> {
                    val (arg, next) = parseArg(tokens, i, decorative = opcodeForm) ?: return null
                    args += arg
                    i = next
                }
            }
        }
        return args
    }

    /** Parses one value starting at [i]; returns the argument and the index after it. */
    private fun parseArg(tokens: List<Token>, i: Int, decorative: Boolean = false): Pair<Arg, Int>? {
        val t = tokens[i]
        val base: Arg = when (t.kind) {
            TokenKind.INT -> IntArg(parseInt(t) ?: return null, loc(t))
            TokenKind.FLOAT -> {
                val v = t.text.toFloatOrNull()
                if (v == null || !v.isFinite()) {
                    error(t, "P010", "Invalid float '${t.text}'")
                    return null
                }
                FloatArg(v, loc(t))
            }
            TokenKind.STRING -> StringArg(t.text.substring(1, t.text.length - 1), t.text.startsWith('"'), loc(t))
            TokenKind.LABEL_REF -> LabelArg(t.text.substring(1), loc(t))
            TokenKind.MODEL -> ModelArg(t.text.substring(1), loc(t))
            TokenKind.GLOBAL_VAR -> parseGlobal(t) ?: return null
            TokenKind.LOCAL_VAR -> parseLocal(t)
            TokenKind.IDENT -> NameArg(t.text, loc(t), maybeDecorative = decorative)
            else -> {
                error(t, "P011", "Expected a value, found '${t.text}'")
                return null
            }
        }
        // Array reference: base(index,10i)
        val canBeArray = base is GlobalVarArg || base is LocalVarArg || base is NameArg
        if (canBeArray && i + 1 < tokens.size && tokens[i + 1].kind == TokenKind.LPAREN && tokens[i + 1].start == t.end) {
            return parseArrayTail(base, tokens, i + 1)
        }
        return base to (i + 1)
    }

    private fun parseArrayTail(base: Arg, tokens: List<Token>, lparen: Int): Pair<Arg, Int>? {
        // base ( index , size )
        if (lparen + 4 > tokens.lastIndex) {
            error(tokens[lparen], "P012", "Incomplete array reference; expected base(index,10i)")
            return null
        }
        val idxTok = tokens[lparen + 1]
        val index: Arg = when (idxTok.kind) {
            TokenKind.LOCAL_VAR -> parseLocal(idxTok)
            TokenKind.GLOBAL_VAR -> parseGlobal(idxTok) ?: return null
            TokenKind.IDENT -> NameArg(idxTok.text, loc(idxTok))
            else -> {
                error(idxTok, "P013", "Array index must be a variable")
                return null
            }
        }
        if (tokens[lparen + 2].kind != TokenKind.COMMA) {
            error(tokens[lparen + 2], "P012", "Expected ',' in array reference base(index,10i)")
            return null
        }
        val sizeTok = tokens[lparen + 3]
        if (sizeTok.kind != TokenKind.ARRAY_SIZE) {
            error(sizeTok, "P014", "Expected array size and type such as 10i, 4f, 2s or 2v")
            return null
        }
        if (tokens[lparen + 4].kind != TokenKind.RPAREN) {
            error(tokens[lparen + 4], "P012", "Expected ')' to close the array reference")
            return null
        }
        val size = sizeTok.text.dropLast(1).toIntOrNull()
        val elem = ArrayElementType.fromSuffix(sizeTok.text.last())
        if (size == null || size !in 1..255 || elem == null) {
            error(sizeTok, "P014", "Array size must be 1-255 followed by i, f, s or v")
            return null
        }
        val first = tokens[lparen - 1]
        val last = tokens[lparen + 4]
        return ArrayArg(base, index, size, elem, SourceLoc.span(first, last, file)) to (lparen + 5)
    }

    private fun parseInt(t: Token): Int? {
        val text = t.text
        val negative = text.startsWith('-')
        val body = text.removePrefix("-")
        val magnitude = if (body.startsWith("0x") || body.startsWith("0X")) body.substring(2).toLongOrNull(16) else body.toLongOrNull()
        if (magnitude == null) {
            error(t, "P015", "Invalid integer '$text'")
            return null
        }
        val value = if (negative) -magnitude else magnitude
        if (value < Int.MIN_VALUE || value > 0xFFFF_FFFFL) {
            error(t, "P016", "Integer '$text' does not fit in 32 bits")
            return null
        }
        return value.toInt()
    }

    private fun parseGlobal(t: Token): GlobalVarArg? {
        var text = t.text
        val storage = when {
            text.startsWith("s$", ignoreCase = true) -> VarStorage.STRING8.also { text = text.substring(1) }
            text.startsWith("v$", ignoreCase = true) -> VarStorage.STRING16.also { text = text.substring(1) }
            else -> VarStorage.NUMBER
        }
        val raw = text.startsWith('&')
        val body = text.substring(1)
        val number = body.toIntOrNull()
        if (raw && number == null) {
            error(t, "P017", "'&' must be followed by a byte offset")
            return null
        }
        if (number != null && (number < 0 || (if (raw) number else number * 4) > 0xFFFF)) {
            error(t, "P018", "Global variable offset out of range: ${t.text}")
            return null
        }
        return if (number != null) {
            GlobalVarArg(null, number, raw, storage, loc(t))
        } else {
            GlobalVarArg(body, null, false, storage, loc(t))
        }
    }

    private fun parseLocal(t: Token): LocalVarArg {
        val number = t.text.substringBefore('@').toInt()
        val storage = when (t.text.substringAfter('@').lowercase()) {
            "s" -> VarStorage.STRING8
            "v" -> VarStorage.STRING16
            else -> VarStorage.NUMBER
        }
        return LocalVarArg(number, storage, loc(t))
    }

    // ---------------------------------------------------------------- assignments and conditions

    private val assignOps = setOf("=", "+=", "-=", "*=", "/=", "+=@", "-=@", "=#", "++", "--")
    private val compareOps = setOf("==", "!=", "<>", ">", ">=", "<", "<=")

    private fun parseAssignment(tokens: List<Token>): Stmt? {
        val (target, next) = parseArg(tokens, 0) ?: return null
        if (next >= tokens.size || tokens[next].kind != TokenKind.OPERATOR) {
            error(tokens[0], "P019", "Expected an operator such as =, += or ++ after '${tokens[0].text}'")
            return null
        }
        val opTok = tokens[next]
        val op = opTok.text
        if (op in compareOps) {
            error(opTok, "P020", "Comparison '$op' is only allowed in a condition (if/while/until)")
            return null
        }
        if (op !in assignOps) {
            error(opTok, "P021", "Unsupported operator '$op'")
            return null
        }
        if (op == "++" || op == "--") {
            expectEnd(tokens, next + 1)
            return AssignStmt(target, op, null, SourceLoc.span(tokens[0], tokens.last(), file))
        }
        if (next + 1 >= tokens.size) {
            error(opTok, "P022", "Missing value after '$op'")
            return null
        }
        val (value, after) = parseArg(tokens, next + 1) ?: return null
        if (after < tokens.size) {
            val extra = tokens[after]
            if (extra.kind == TokenKind.OPERATOR) {
                error(extra, "P023", "Expressions with more than one operator are not supported; split them into separate statements")
            } else {
                error(extra, "P024", "Unexpected '${extra.text}' after the assigned value")
            }
            return null
        }
        return AssignStmt(target, op, value, SourceLoc.span(tokens[0], tokens.last(), file))
    }

    /** Parses one condition line; returns the condition and whether it ended with `then`. */
    private fun parseConditionLine(rawTokens: List<Token>): Pair<Condition?, Boolean> {
        var tokens = rawTokens
        var hasThen = false
        if (tokens.isNotEmpty() && tokens.last().isWord("then")) {
            hasThen = true
            tokens = tokens.dropLast(1)
        }
        if (tokens.isEmpty()) return null to hasThen
        return parseCondition(tokens) to hasThen
    }

    private fun parseCondition(rawTokens: List<Token>): Condition? {
        var tokens = rawTokens
        var negated = false
        if (tokens[0].isWord("not")) {
            negated = true
            tokens = tokens.drop(1)
            if (tokens.isEmpty()) {
                error(rawTokens[0], "P004", "'not' must be followed by a condition")
                return null
            }
        }
        val head = tokens[0]
        if (head.kind == TokenKind.OPCODE) {
            return parseOpcodeCommand(tokens, negatedPrefix = negated)?.let { CommandCondition(it) }
        }
        // Comparison: <arg> <op> <arg>
        val firstArg = if (head.kind == TokenKind.IDENT && tokens.size > 1 && tokens[1].kind != TokenKind.OPERATOR && tokens[1].kind != TokenKind.LPAREN) {
            null
        } else {
            parseArg(tokens, 0)
        }
        if (firstArg != null) {
            val (left, next) = firstArg
            if (next < tokens.size && tokens[next].kind == TokenKind.OPERATOR) {
                val opTok = tokens[next]
                val op = if (opTok.text == "=") "==" else opTok.text
                if (op !in compareOps) {
                    error(opTok, "P025", "'${opTok.text}' is not a comparison operator; use ==, <>, >, >=, < or <=")
                    return null
                }
                if (next + 1 >= tokens.size) {
                    error(opTok, "P022", "Missing value after '${opTok.text}'")
                    return null
                }
                val (right, after) = parseArg(tokens, next + 1) ?: return null
                if (after < tokens.size) {
                    error(tokens[after], "P024", "Unexpected '${tokens[after].text}' in condition")
                    return null
                }
                return CompareCondition(left, op, right, negated, SourceLoc.span(tokens[0], tokens.last(), file))
            }
        }
        if (head.kind == TokenKind.IDENT) {
            return parseKeywordCommand(tokens, negated)?.let { CommandCondition(it) }
        }
        error(head, "P026", "Expected a condition: a command or a comparison such as 0@ > 5")
        return null
    }

    private fun isJumpIfFalse(line: Line): Boolean {
        val h = line.head
        return h.kind == TokenKind.IDENT && h.text.lowercase() in setOf("jf", "goto_if_false", "jump_if_false", "else_jump") ||
            h.kind == TokenKind.OPCODE && h.text.dropLast(1).toInt(16) == 0x004D
    }

    private fun parseIf(tokens: List<Token>): Stmt {
        val head = tokens[0]
        var i = 1
        var mode = ConditionMode.SINGLE
        if (i < tokens.size && tokens[i].isWord("and")) { mode = ConditionMode.AND; i++ }
        else if (i < tokens.size && tokens[i].isWord("or")) { mode = ConditionMode.OR; i++ }
        val conditions = ArrayList<Condition>()
        var thenFound = false
        var jf: LabelArg? = null
        if (i < tokens.size) {
            val (cond, hadThen) = parseConditionLine(tokens.drop(i))
            cond?.let { conditions += it }
            thenFound = hadThen
        }
        while (!thenFound && jf == null) {
            if (index >= lines.size) {
                error(head, "P027", "'if' without 'then' or 'jf'")
                break
            }
            val line = lines[index]
            val h = line.head
            when {
                h.isWord("then") -> {
                    index++
                    expectEnd(line.tokens, 1)
                    thenFound = true
                }
                isJumpIfFalse(line) -> {
                    index++
                    val labelTok = line.tokens.drop(1).firstOrNull { it.kind == TokenKind.LABEL_REF }
                    if (labelTok == null) {
                        error(h, "P028", "Expected a label after '${h.text}'")
                        break
                    }
                    jf = LabelArg(labelTok.text.substring(1), loc(labelTok))
                }
                h.isWord("end") || h.isWord("else") -> {
                    error(h, "P027", "Missing 'then' before '${h.text}'")
                    break
                }
                else -> {
                    index++
                    val (cond, hadThen) = parseConditionLine(line.tokens)
                    cond?.let { conditions += it }
                    thenFound = hadThen
                }
            }
        }
        if (conditions.isEmpty()) error(head, "P029", "'if' needs at least one condition")
        var thenBody: List<Stmt>? = null
        var elseBody: List<Stmt>? = null
        if (thenFound) {
            val (body, term) = parseBlock(setOf("else", "end"))
            thenBody = body
            when {
                term == null -> error(head, "P030", "'if' block is missing 'end'")
                term.head.isWord("else") -> {
                    expectEnd(term.tokens, 1)
                    val (eb, term2) = parseBlock(setOf("end"))
                    elseBody = eb
                    if (term2 == null) error(head, "P030", "'if' block is missing 'end'") else expectEnd(term2.tokens, 1)
                }
                else -> expectEnd(term.tokens, 1)
            }
        }
        return IfStmt(mode, conditions, thenBody, elseBody, jf, loc(head))
    }

    private fun parseWhile(tokens: List<Token>): Stmt? {
        val head = tokens[0]
        val rest = tokens.drop(1)
        if (rest.isEmpty()) {
            error(head, "P031", "'while' needs a condition; use 'while true' for an endless loop")
            return null
        }
        val condition: Condition? = when {
            rest.size == 1 && (rest[0].isWord("true") || rest[0].kind == TokenKind.INT && rest[0].text == "1") -> null
            rest[0].isWord("and") || rest[0].isWord("or") -> {
                error(rest[0], "P032", "'while' supports one condition; use 'while true' with 'if ... break' for several")
                return null
            }
            else -> parseCondition(rest) ?: return null
        }
        val (body, term) = parseBlock(setOf("end"))
        if (term == null) error(head, "P033", "'while' loop is missing 'end'") else expectEnd(term.tokens, 1)
        return WhileStmt(condition, body, loc(head))
    }

    private fun parseRepeat(tokens: List<Token>): Stmt? {
        val head = tokens[0]
        expectEnd(tokens, 1)
        val (body, term) = parseBlock(setOf("until"))
        if (term == null) {
            error(head, "P034", "'repeat' loop is missing 'until <condition>'")
            return null
        }
        val condTokens = term.tokens.drop(1)
        if (condTokens.isEmpty()) {
            error(term.head, "P034", "'until' needs a condition")
            return null
        }
        val cond = parseCondition(condTokens) ?: return null
        return RepeatStmt(body, cond, loc(head))
    }

    private fun parseFor(tokens: List<Token>): Stmt? {
        val head = tokens[0]
        // for <var> = <from> to|downto <to> [step <n>]
        if (tokens.size < 6) {
            error(head, "P035", "Expected 'for <var> = <start> to <end> [step <n>]'")
            return null
        }
        val (variable, afterVar) = parseArg(tokens, 1) ?: return null
        if (afterVar >= tokens.size || tokens[afterVar].text != "=") {
            error(tokens.getOrElse(afterVar) { head }, "P035", "Expected '=' after the loop variable")
            return null
        }
        val (from, afterFrom) = parseArg(tokens, afterVar + 1) ?: return null
        val dirTok = tokens.getOrNull(afterFrom)
        val down = when {
            dirTok?.isWord("to") == true -> false
            dirTok?.isWord("downto") == true -> true
            else -> {
                error(dirTok ?: head, "P035", "Expected 'to' or 'downto'")
                return null
            }
        }
        if (afterFrom + 1 >= tokens.size) {
            error(dirTok, "P035", "Missing loop end value")
            return null
        }
        val (to, afterTo) = parseArg(tokens, afterFrom + 1) ?: return null
        var step: Arg? = null
        if (afterTo < tokens.size) {
            if (!tokens[afterTo].isWord("step") || afterTo + 1 >= tokens.size) {
                error(tokens[afterTo], "P035", "Expected 'step <n>' or end of line")
                return null
            }
            val (s, afterStep) = parseArg(tokens, afterTo + 1) ?: return null
            step = s
            expectEnd(tokens, afterStep)
        }
        val (body, term) = parseBlock(setOf("end"))
        if (term == null) error(head, "P036", "'for' loop is missing 'end'") else expectEnd(term.tokens, 1)
        return ForStmt(variable, from, to, step, down, body, loc(head))
    }

    // ---------------------------------------------------------------- declarations and data

    private fun parseConst(tokens: List<Token>): Stmt? {
        val head = tokens[0]
        val entries = ArrayList<Pair<String, Arg>>()
        var body = tokens.drop(1)
        val singleLine = body.isNotEmpty()
        if (singleLine) {
            if (body.last().isWord("end")) body = body.dropLast(1)
            parseConstEntries(body, entries)
        } else {
            while (true) {
                if (index >= lines.size) {
                    error(head, "P037", "'const' block is missing 'end'")
                    break
                }
                val line = lines[index++]
                if (line.head.isWord("end")) {
                    expectEnd(line.tokens, 1)
                    break
                }
                parseConstEntries(line.tokens, entries)
            }
        }
        return ConstStmt(entries, loc(head))
    }

    private fun parseConstEntries(tokens: List<Token>, into: MutableList<Pair<String, Arg>>) {
        var i = 0
        while (i < tokens.size) {
            val nameTok = tokens[i]
            if (nameTok.kind != TokenKind.IDENT) {
                error(nameTok, "P038", "Expected a constant name")
                return
            }
            if (tokens.getOrNull(i + 1)?.text != "=") {
                error(nameTok, "P038", "Expected '=' after constant name '${nameTok.text}'")
                return
            }
            if (i + 2 >= tokens.size) {
                error(nameTok, "P038", "Missing value for constant '${nameTok.text}'")
                return
            }
            val (value, next) = parseArg(tokens, i + 2) ?: return
            into += nameTok.text to value
            i = next
            if (i < tokens.size) {
                if (tokens[i].kind != TokenKind.COMMA) {
                    error(tokens[i], "P038", "Expected ',' between constants")
                    return
                }
                i++
            }
        }
    }

    /** Sanny Builder 3 style: `var 0@: Int, $X: Float end` or a multi-line block. */
    private fun parseVarBlock(tokens: List<Token>): Stmt? {
        val head = tokens[0]
        val ints = ArrayList<Pair<Arg, Arg?>>()
        val floats = ArrayList<Pair<Arg, Arg?>>()
        fun parseEntries(line: List<Token>) {
            var i = 0
            while (i < line.size) {
                val (target, next) = parseArg(line, i) ?: return
                if (next >= line.size || line[next].text != ":") {
                    error(line[i], "P039", "Expected ':' and a type after the variable")
                    return
                }
                val typeTok = line.getOrNull(next + 1)
                when {
                    typeTok == null -> { error(line[next], "P039", "Missing type"); return }
                    typeTok.isWord("int") || typeTok.isWord("integer") -> ints += target to null
                    typeTok.isWord("float") -> floats += target to null
                    else -> { error(typeTok, "P039", "Unsupported type '${typeTok.text}'; use Int or Float"); return }
                }
                i = next + 2
                if (i < line.size && line[i].kind == TokenKind.COMMA) i++
            }
        }
        var body = tokens.drop(1)
        if (body.isNotEmpty()) {
            if (body.last().isWord("end")) body = body.dropLast(1) else error(head, "P040", "Single-line 'var' must end with 'end'")
            parseEntries(body)
        } else {
            while (true) {
                if (index >= lines.size) {
                    error(head, "P040", "'var' block is missing 'end'")
                    break
                }
                val line = lines[index++]
                if (line.head.isWord("end")) break
                parseEntries(line.tokens)
            }
        }
        val l = loc(head)
        return when {
            ints.isNotEmpty() && floats.isNotEmpty() -> ForwardingDecls(listOf(DeclStmt(ValueType.INT, ints, l), DeclStmt(ValueType.FLOAT, floats, l)), l)
            floats.isNotEmpty() -> DeclStmt(ValueType.FLOAT, floats, l)
            else -> DeclStmt(ValueType.INT, ints, l)
        }
    }

    private fun parseDecl(tokens: List<Token>): Stmt? {
        val head = tokens[0]
        val type = if (head.isWord("int")) ValueType.INT else ValueType.FLOAT
        val entries = ArrayList<Pair<Arg, Arg?>>()
        var i = 1
        if (i >= tokens.size) {
            error(head, "P041", "Expected a variable name after '${head.text}'")
            return null
        }
        while (i < tokens.size) {
            val (target, next) = parseArg(tokens, i) ?: return null
            if (target !is NameArg && target !is LocalVarArg && target !is GlobalVarArg) {
                error(tokens[i], "P041", "Expected a variable name")
                return null
            }
            var init: Arg? = null
            var j = next
            if (j < tokens.size && tokens[j].text == "=") {
                if (j + 1 >= tokens.size) {
                    error(tokens[j], "P022", "Missing initial value")
                    return null
                }
                val (v, after) = parseArg(tokens, j + 1) ?: return null
                init = v
                j = after
            }
            entries += target to init
            if (j < tokens.size) {
                if (tokens[j].kind != TokenKind.COMMA) {
                    error(tokens[j], "P041", "Expected ',' between declarations")
                    return null
                }
                j++
            }
            i = j
        }
        return DeclStmt(type, entries, loc(head))
    }

    private fun parseHex(tokens: List<Token>): Stmt? {
        val head = tokens[0]
        val hex = StringBuilder()
        var closed = false
        fun take(line: List<Token>) {
            for (t in line) {
                if (t.isWord("end")) {
                    closed = true
                    return
                }
                hex.append(t.text)
            }
        }
        take(tokens.drop(1))
        while (!closed) {
            if (index >= lines.size) break
            take(lines[index++].tokens)
        }
        if (!closed) {
            error(head, "P042", "'hex' block is missing 'end'")
            return null
        }
        val digits = hex.toString()
        if (digits.length % 2 != 0 || !digits.all { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' }) {
            error(head, "P043", "'hex' block must contain pairs of hexadecimal digits")
            return null
        }
        val bytes = ByteArray(digits.length / 2) { digits.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
        return HexStmt(bytes, loc(head))
    }

    // ---------------------------------------------------------------- helpers

    private fun expectEnd(tokens: List<Token>, from: Int) {
        if (from < tokens.size) error(tokens[from], "P044", "Unexpected '${tokens[from].text}' at end of statement")
    }

    private fun loc(t: Token) = SourceLoc.of(t, file)

    private fun error(t: Token?, code: String, message: String) {
        if (t == null) sink.error(code, message) else sink.error(code, message, t.line, t.column, t.text.length)
    }
}

/** Wraps several declarations produced by one `var` block. */
data class ForwardingDecls(val decls: List<DeclStmt>, override val loc: SourceLoc) : Stmt()
