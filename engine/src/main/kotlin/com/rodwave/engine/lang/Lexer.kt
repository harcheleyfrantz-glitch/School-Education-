package com.rodwave.engine.lang

enum class TokenKind {
    /** `0001:` or `8256:` (negated). */
    OPCODE,
    /** `:NAME` at the start of a statement. */
    LABEL_DEF,
    /** `@NAME`. */
    LABEL_REF,
    /** `$NAME`, `$123`, `&123`, `s$NAME`, `v$NAME`. */
    GLOBAL_VAR,
    /** `0@`, `12@s`, `12@v`. */
    LOCAL_VAR,
    INT,
    FLOAT,
    STRING,
    /** `#CHEETAH`. */
    MODEL,
    /** `10i`, `4s` inside an array reference. */
    ARRAY_SIZE,
    IDENT,
    OPERATOR,
    LPAREN,
    RPAREN,
    COMMA,
    /** `{$CLEO .csa}`. */
    DIRECTIVE,
    COMMENT,
    WHITESPACE,
    NEWLINE,
    /** Characters the lexer could not classify (reported by the compiler). */
    ERROR,
}

data class Token(
    val kind: TokenKind,
    val text: String,
    /** Offset of the first character in the source text. */
    val start: Int,
    /** 1-based line and column of [start]. */
    val line: Int,
    val column: Int,
) {
    val end: Int get() = start + text.length
    val isTrivia: Boolean get() = kind == TokenKind.WHITESPACE || kind == TokenKind.COMMENT

    /** True for tokens that can start a parameter value. */
    val isValue: Boolean
        get() = when (kind) {
            TokenKind.INT, TokenKind.FLOAT, TokenKind.STRING, TokenKind.LABEL_REF, TokenKind.GLOBAL_VAR,
            TokenKind.LOCAL_VAR, TokenKind.MODEL -> true
            else -> false
        }

    fun isWord(word: String): Boolean = kind == TokenKind.IDENT && text.equals(word, ignoreCase = true)
}

/** Lexer state carried across lines for incremental highlighting. */
enum class LexState { NORMAL, IN_BLOCK_COMMENT_STAR, IN_BLOCK_COMMENT_BRACE }

/**
 * Tokenizer for Rodwave's Sanny Builder–compatible script syntax.
 *
 * The lexer never fails: unknown characters become [TokenKind.ERROR] tokens. Trivia (whitespace and
 * comments) is kept so the same token stream drives syntax highlighting.
 */
class Lexer(private val text: String, private val initialState: LexState = LexState.NORMAL) {
    private var pos = 0
    private var line = 1
    private var col = 1
    private val tokens = ArrayList<Token>()

    /** State at the end of the text (used to continue highlighting on the next line). */
    var endState: LexState = LexState.NORMAL
        private set

    fun tokenize(): List<Token> {
        if (initialState != LexState.NORMAL) {
            val close = if (initialState == LexState.IN_BLOCK_COMMENT_STAR) "*/" else "}"
            blockComment(close, alreadyOpened = true)
        }
        while (pos < text.length) {
            scanToken()
        }
        return tokens
    }

    private fun peek(offset: Int = 0): Char = if (pos + offset < text.length) text[pos + offset] else '\u0000'

    private fun emit(kind: TokenKind, start: Int, startLine: Int, startCol: Int) {
        tokens += Token(kind, text.substring(start, pos), start, startLine, startCol)
    }

    private fun advance(): Char {
        val c = text[pos++]
        if (c == '\n') {
            line++
            col = 1
        } else {
            col++
        }
        return c
    }

    /** True when only whitespace precedes [pos] on the current line (or the previous token is a statement starter). */
    private fun atStatementStart(): Boolean {
        for (i in tokens.indices.reversed()) {
            val t = tokens[i]
            when (t.kind) {
                TokenKind.WHITESPACE, TokenKind.COMMENT -> continue
                TokenKind.NEWLINE -> return true
                TokenKind.IDENT -> return t.text.lowercase() in STATEMENT_PREFIX_WORDS
                else -> return false
            }
        }
        return true
    }

    private fun scanToken() {
        val start = pos
        val startLine = line
        val startCol = col
        val c = peek()
        when {
            c == '\n' -> {
                advance()
                emit(TokenKind.NEWLINE, start, startLine, startCol)
            }
            c == '\r' && peek(1) == '\n' -> {
                advance()
                advance()
                emit(TokenKind.NEWLINE, start, startLine, startCol)
            }
            c == ' ' || c == '\t' || c == '\r' || c == '\u000C' -> {
                while (peek() == ' ' || peek() == '\t' || (peek() == '\r' && peek(1) != '\n') || peek() == '\u000C') advance()
                emit(TokenKind.WHITESPACE, start, startLine, startCol)
            }
            c == '/' && peek(1) == '/' -> {
                while (pos < text.length && peek() != '\n' && !(peek() == '\r' && peek(1) == '\n')) advance()
                emit(TokenKind.COMMENT, start, startLine, startCol)
            }
            c == '/' && peek(1) == '*' -> {
                advance(); advance()
                blockComment("*/", alreadyOpened = true, start = start, startLine = startLine, startCol = startCol)
            }
            c == '{' && peek(1) == '$' -> {
                while (pos < text.length && peek() != '}' && peek() != '\n') advance()
                if (peek() == '}') {
                    advance()
                    emit(TokenKind.DIRECTIVE, start, startLine, startCol)
                } else {
                    emit(TokenKind.ERROR, start, startLine, startCol)
                }
            }
            c == '{' -> {
                advance()
                blockComment("}", alreadyOpened = true, start = start, startLine = startLine, startCol = startCol)
            }
            c == '\'' || c == '"' -> scanString(c, start, startLine, startCol)
            c == ':' && isIdentPart(peek(1)) && atStatementStart() -> {
                advance()
                while (isIdentPart(peek())) advance()
                emit(TokenKind.LABEL_DEF, start, startLine, startCol)
            }
            c == '@' && isIdentPart(peek(1)) -> {
                advance()
                while (isIdentPart(peek())) advance()
                emit(TokenKind.LABEL_REF, start, startLine, startCol)
            }
            c == '$' || c == '&' -> {
                advance()
                if (isIdentPart(peek())) {
                    while (isIdentPart(peek())) advance()
                    emit(TokenKind.GLOBAL_VAR, start, startLine, startCol)
                } else {
                    emit(TokenKind.ERROR, start, startLine, startCol)
                }
            }
            (c == 's' || c == 'S' || c == 'v' || c == 'V') && peek(1) == '$' && isIdentPart(peek(2)) && !prevIsIdentChar() -> {
                advance(); advance()
                while (isIdentPart(peek())) advance()
                emit(TokenKind.GLOBAL_VAR, start, startLine, startCol)
            }
            c == '#' && isIdentPart(peek(1)) -> {
                advance()
                while (isIdentPart(peek())) advance()
                emit(TokenKind.MODEL, start, startLine, startCol)
            }
            c == '-' && (peek(1).isDigit() || peek(1) == '.' && peek(2).isDigit()) && negativeNumberAllowed() -> {
                advance()
                scanNumberLike(start, startLine, startCol)
            }
            c.isDigit() || c == '.' && peek(1).isDigit() -> scanNumberLike(start, startLine, startCol)
            isIdentStart(c) -> {
                while (isIdentPart(peek()) || peek() == '.' && isIdentStart(peek(1))) advance()
                emit(TokenKind.IDENT, start, startLine, startCol)
            }
            c == '(' -> { advance(); emit(TokenKind.LPAREN, start, startLine, startCol) }
            c == ')' -> { advance(); emit(TokenKind.RPAREN, start, startLine, startCol) }
            c == ',' -> { advance(); emit(TokenKind.COMMA, start, startLine, startCol) }
            else -> scanOperatorOrError(start, startLine, startCol)
        }
    }

    private fun blockComment(close: String, alreadyOpened: Boolean, start: Int = pos, startLine: Int = line, startCol: Int = col) {
        check(alreadyOpened)
        while (pos < text.length && !text.startsWith(close, pos)) advance()
        if (pos < text.length) {
            repeat(close.length) { advance() }
            endState = LexState.NORMAL
        } else {
            endState = if (close == "*/") LexState.IN_BLOCK_COMMENT_STAR else LexState.IN_BLOCK_COMMENT_BRACE
        }
        if (pos > start) emit(TokenKind.COMMENT, start, startLine, startCol)
    }

    private fun scanString(quote: Char, start: Int, startLine: Int, startCol: Int) {
        advance()
        while (pos < text.length && peek() != quote && peek() != '\n') advance()
        if (peek() == quote) {
            advance()
            emit(TokenKind.STRING, start, startLine, startCol)
        } else {
            emit(TokenKind.ERROR, start, startLine, startCol)
        }
    }

    private fun scanNumberLike(start: Int, startLine: Int, startCol: Int) {
        // Opcode prefix: exactly four hex digits followed by ':'.
        if (pos == start && isHex(peek()) && isHex(peek(1)) && isHex(peek(2)) && isHex(peek(3)) && peek(4) == ':' &&
            !isIdentPart(peek(5)) && atStatementStart()
        ) {
            repeat(5) { advance() }
            emit(TokenKind.OPCODE, start, startLine, startCol)
            return
        }
        while (isIdentPart(peek()) || peek() == '.' || peek() == '@' ||
            ((peek() == '+' || peek() == '-') && (text[pos - 1] == 'e' || text[pos - 1] == 'E') && !text.substring(start, pos).startsWith("0x", true))
        ) {
            if (peek() == '@') {
                advance()
                if (peek() == 's' || peek() == 'v' || peek() == 'S' || peek() == 'V') {
                    if (!isIdentPart(peek(1))) advance()
                }
                break
            }
            advance()
        }
        val word = text.substring(start, pos)
        val kind = classifyNumber(word)
        emit(kind, start, startLine, startCol)
    }

    private fun scanOperatorOrError(start: Int, startLine: Int, startCol: Int) {
        val ops = listOf("+=@", "-=@", "=#", "==", "!=", "<>", ">=", "<=", "+=", "-=", "*=", "/=", "++", "--", "=", ">", "<", "+", "-", "*", "/")
        val op = ops.firstOrNull { text.startsWith(it, pos) }
        if (op != null) {
            repeat(op.length) { advance() }
            emit(TokenKind.OPERATOR, start, startLine, startCol)
        } else {
            advance()
            emit(TokenKind.ERROR, start, startLine, startCol)
        }
    }

    private fun negativeNumberAllowed(): Boolean {
        if (pos == 0) return true
        val prev = text[pos - 1]
        return prev == ' ' || prev == '\t' || prev == '(' || prev == ',' || prev == '=' || prev == '\n' || prev == '\r' ||
            prev == '>' || prev == '<'
    }

    private fun prevIsIdentChar(): Boolean = pos > 0 && isIdentPart(text[pos - 1])

    companion object {
        /** Words after which an opcode prefix (`0001:`) may follow on the same line. */
        private val STATEMENT_PREFIX_WORDS = setOf("not", "then", "else", "and", "or", "if", "while", "until")

        private val INT_RE = Regex("-?(0[xX][0-9a-fA-F]+|[0-9]+)")
        private val FLOAT_RE = Regex("-?([0-9]+\\.[0-9]*|\\.[0-9]+)([eE][+-]?[0-9]+)?|-?[0-9]+[eE][+-]?[0-9]+")
        private val LOCAL_RE = Regex("[0-9]+@[sSvV]?")
        private val ARRAY_SIZE_RE = Regex("[0-9]+[ifsvIFSV]")

        fun classifyNumber(word: String): TokenKind = when {
            INT_RE.matches(word) -> TokenKind.INT
            FLOAT_RE.matches(word) -> TokenKind.FLOAT
            LOCAL_RE.matches(word) -> TokenKind.LOCAL_VAR
            ARRAY_SIZE_RE.matches(word) -> TokenKind.ARRAY_SIZE
            else -> TokenKind.ERROR
        }

        fun isIdentStart(c: Char): Boolean = c.isLetter() || c == '_'
        fun isIdentPart(c: Char): Boolean = c.isLetterOrDigit() || c == '_'
        private fun isHex(c: Char): Boolean = c.isDigit() || c in 'a'..'f' || c in 'A'..'F'

        fun tokenize(text: String): List<Token> = Lexer(text).tokenize()
    }
}
