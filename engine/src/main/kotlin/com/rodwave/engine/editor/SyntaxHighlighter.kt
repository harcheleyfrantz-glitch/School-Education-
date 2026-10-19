package com.rodwave.engine.editor

import com.rodwave.engine.compiler.ScriptCompiler
import com.rodwave.engine.lang.Lexer
import com.rodwave.engine.lang.TokenKind
import com.rodwave.engine.opcode.OpcodeDatabase

enum class SyntaxStyle {
    KEYWORD, COMMAND, OPCODE, LABEL, GLOBAL_VAR, LOCAL_VAR, NUMBER, STRING, COMMENT, DIRECTIVE, OPERATOR, MODEL, CONSTANT, ERROR, PLAIN
}

data class StyledSpan(val start: Int, val end: Int, val style: SyntaxStyle)

/** Classifies source text for colouring. Uses the same lexer as the compiler. */
class SyntaxHighlighter(private val database: OpcodeDatabase) {

    fun highlight(text: String): List<StyledSpan> {
        val spans = ArrayList<StyledSpan>()
        for (t in Lexer(text).tokenize()) {
            val style = when (t.kind) {
                TokenKind.OPCODE -> SyntaxStyle.OPCODE
                TokenKind.LABEL_DEF, TokenKind.LABEL_REF -> SyntaxStyle.LABEL
                TokenKind.GLOBAL_VAR -> SyntaxStyle.GLOBAL_VAR
                TokenKind.LOCAL_VAR -> SyntaxStyle.LOCAL_VAR
                TokenKind.INT, TokenKind.FLOAT, TokenKind.ARRAY_SIZE -> SyntaxStyle.NUMBER
                TokenKind.STRING -> SyntaxStyle.STRING
                TokenKind.MODEL -> SyntaxStyle.MODEL
                TokenKind.COMMENT -> SyntaxStyle.COMMENT
                TokenKind.DIRECTIVE -> SyntaxStyle.DIRECTIVE
                TokenKind.OPERATOR -> SyntaxStyle.OPERATOR
                TokenKind.ERROR -> SyntaxStyle.ERROR
                TokenKind.IDENT -> classifyWord(t.text)
                else -> null
            } ?: continue
            spans += StyledSpan(t.start, t.end, style)
        }
        return spans
    }

    private fun classifyWord(word: String): SyntaxStyle {
        val lower = word.lowercase()
        return when {
            lower in KEYWORDS -> SyntaxStyle.KEYWORD
            lower in CONSTANT_WORDS -> SyntaxStyle.CONSTANT
            '.' in word -> SyntaxStyle.CONSTANT
            lower in ScriptCompiler.KEYWORD_ALIASES -> SyntaxStyle.COMMAND
            database.findByName(lower).isNotEmpty() -> SyntaxStyle.COMMAND
            else -> SyntaxStyle.PLAIN
        }
    }

    companion object {
        val KEYWORDS = setOf(
            "if", "then", "else", "end", "while", "repeat", "until", "for", "to", "downto", "step", "break", "continue",
            "not", "and", "or", "const", "var", "int", "float", "hex",
        )
        val CONSTANT_WORDS = setOf("true", "false", "timera", "timerb")
    }
}
