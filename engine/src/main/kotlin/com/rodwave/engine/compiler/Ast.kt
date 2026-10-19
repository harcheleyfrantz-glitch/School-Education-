package com.rodwave.engine.compiler

import com.rodwave.engine.lang.Token
import com.rodwave.engine.scm.ArrayElementType
import com.rodwave.engine.scm.VarStorage

data class SourceLoc(val file: String?, val line: Int, val column: Int, val length: Int) {
    companion object {
        fun of(token: Token, file: String?) = SourceLoc(file, token.line, token.column, token.text.length)
        fun span(first: Token, last: Token, file: String?) =
            SourceLoc(file, first.line, first.column, if (first.line == last.line) last.end - first.start else first.text.length)
    }
}

/** A parameter as written in source, before resolution against the opcode database. */
sealed class Arg {
    abstract val loc: SourceLoc
}

data class IntArg(val value: Int, override val loc: SourceLoc) : Arg()
data class FloatArg(val value: Float, override val loc: SourceLoc) : Arg()
data class StringArg(val text: String, val doubleQuoted: Boolean, override val loc: SourceLoc) : Arg()
data class LabelArg(val name: String, override val loc: SourceLoc) : Arg()
data class ModelArg(val name: String, override val loc: SourceLoc) : Arg()

/**
 * Global variable. Exactly one of [name] / [index] is set. [index] is a slot index (`$12` = byte
 * offset 48) unless [rawOffset] is true (`&48`).
 */
data class GlobalVarArg(
    val name: String?,
    val index: Int?,
    val rawOffset: Boolean,
    val storage: VarStorage,
    override val loc: SourceLoc,
) : Arg()

data class LocalVarArg(val index: Int, val storage: VarStorage, override val loc: SourceLoc) : Arg()

/** Identifier resolved later: constant, named variable, enum member, `true`/`false`, `TIMERA`/`TIMERB`. */
data class NameArg(val name: String, override val loc: SourceLoc, val maybeDecorative: Boolean = false) : Arg()

data class ArrayArg(
    val base: Arg,
    val index: Arg,
    val size: Int,
    val elementType: ArrayElementType,
    override val loc: SourceLoc,
) : Arg()

enum class ConditionMode { SINGLE, AND, OR }

sealed class Condition {
    abstract val loc: SourceLoc
}

/** A command used as a condition (e.g. `0256: player $PLAYER_CHAR defined`). Negation lives in [command]. */
data class CommandCondition(val command: CommandStmt) : Condition() {
    override val loc: SourceLoc get() = command.loc
}

/** `a > b`, `a == b`, ... */
data class CompareCondition(
    val left: Arg,
    val operator: String,
    val right: Arg,
    val negated: Boolean,
    override val loc: SourceLoc,
) : Condition()

sealed class Stmt {
    abstract val loc: SourceLoc
}

data class LabelStmt(val name: String, override val loc: SourceLoc) : Stmt()

/** Command written as `XXXX: ...` ([opcode] set) or by keyword ([keyword] set). */
data class CommandStmt(
    val opcode: Int?,
    val keyword: String?,
    val negated: Boolean,
    val args: List<Arg>,
    override val loc: SourceLoc,
) : Stmt()

/** `a = b`, `a += b`, `a ++` ([value] is null for `++`/`--`). */
data class AssignStmt(val target: Arg, val operator: String, val value: Arg?, override val loc: SourceLoc) : Stmt()

class HexStmt(val bytes: ByteArray, override val loc: SourceLoc) : Stmt()

data class IfStmt(
    val mode: ConditionMode,
    val conditions: List<Condition>,
    val thenBody: List<Stmt>?,
    val elseBody: List<Stmt>?,
    /** Classic form: `if ... jf @label` without a body. */
    val jumpIfFalse: LabelArg?,
    override val loc: SourceLoc,
) : Stmt()

/** `while <cond> ... end`; [condition] is null for `while true`. */
data class WhileStmt(val condition: Condition?, val body: List<Stmt>, override val loc: SourceLoc) : Stmt()

data class RepeatStmt(val body: List<Stmt>, val until: Condition, override val loc: SourceLoc) : Stmt()

data class ForStmt(
    val variable: Arg,
    val from: Arg,
    val to: Arg,
    val step: Arg?,
    val downTo: Boolean,
    val body: List<Stmt>,
    override val loc: SourceLoc,
) : Stmt()

data class BreakStmt(override val loc: SourceLoc) : Stmt()
data class ContinueStmt(override val loc: SourceLoc) : Stmt()

enum class ValueType { INT, FLOAT }

/** `int a, b = 5` or `float 0@`. Targets are [NameArg] (new named local) or variables. */
data class DeclStmt(val type: ValueType, val entries: List<Pair<Arg, Arg?>>, override val loc: SourceLoc) : Stmt()

data class ConstStmt(val entries: List<Pair<String, Arg>>, override val loc: SourceLoc) : Stmt()

data class DirectiveStmt(val name: String, val value: String, override val loc: SourceLoc) : Stmt()
