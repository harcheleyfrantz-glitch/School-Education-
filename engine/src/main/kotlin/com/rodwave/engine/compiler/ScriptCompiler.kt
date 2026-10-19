package com.rodwave.engine.compiler

import com.rodwave.engine.diagnostics.Diagnostic
import com.rodwave.engine.diagnostics.DiagnosticSink
import com.rodwave.engine.diagnostics.Severity
import com.rodwave.engine.opcode.OpcodeDatabase
import com.rodwave.engine.opcode.OpcodeDefinition
import com.rodwave.engine.opcode.ParamDefinition
import com.rodwave.engine.opcode.ParamSource
import com.rodwave.engine.opcode.ParamType
import com.rodwave.engine.scm.ArrayElementType
import com.rodwave.engine.scm.ArrayOperand
import com.rodwave.engine.scm.BytecodeWriter
import com.rodwave.engine.scm.DataType
import com.rodwave.engine.scm.DecodeResult
import com.rodwave.engine.scm.EndOfArgs
import com.rodwave.engine.scm.FloatOperand
import com.rodwave.engine.scm.InstructionDecoder
import com.rodwave.engine.scm.IntOperand
import com.rodwave.engine.scm.Opcodes
import com.rodwave.engine.scm.Operand
import com.rodwave.engine.scm.ScriptFormat
import com.rodwave.engine.scm.StringOperand
import com.rodwave.engine.scm.VarOperand
import com.rodwave.engine.scm.VarStorage

/** Supplies the text of `{$INCLUDE file}` targets. */
fun interface IncludeResolver {
    /** Returns the included source, or null if it cannot be found. */
    fun resolve(path: String, fromFile: String?): IncludedSource?
}

data class IncludedSource(val name: String, val text: String)

/** Global variable names known without declaration (Sanny Builder's San Andreas conventions). */
object PredefinedGlobals {
    val SAN_ANDREAS: Map<String, Int> = mapOf("PLAYER_CHAR" to 2, "PLAYER_ACTOR" to 3)
}

data class CompileOptions(
    /** Output format when the source has no `{$CLEO .ext}` directive. */
    val format: ScriptFormat = ScriptFormat.CLEO_ANDROID_AUTO,
    val fileName: String? = null,
    val includeResolver: IncludeResolver? = null,
    val models: ModelTable = ModelTable.SAN_ANDREAS,
    /** Global variable aliases: name -> slot index (`$NAME` = byte offset index*4). */
    val globals: Map<String, Int> = PredefinedGlobals.SAN_ANDREAS,
)

data class SourceMapping(val offset: Int, val length: Int, val file: String?, val line: Int)

data class CompileResult(
    /** Compiled bytes; null when compilation or output validation failed. */
    val bytes: ByteArray?,
    val diagnostics: List<Diagnostic>,
    val format: ScriptFormat,
    val labels: Map<String, Int>,
    val instructionCount: Int,
    val sourceMap: List<SourceMapping>,
) {
    val success: Boolean get() = bytes != null
    val errors: List<Diagnostic> get() = diagnostics.filter { it.isError }
    val warnings: List<Diagnostic> get() = diagnostics.filter { it.severity == Severity.WARNING }
}

/**
 * Compiles Rodwave/Sanny Builder–style source into headerless CLEO bytecode.
 *
 * Output is only returned after an independent validation pass decodes every emitted instruction
 * again and checks label targets; any mismatch is reported as an error and no bytes are produced.
 */
class ScriptCompiler(private val database: OpcodeDatabase) {

    fun compile(source: String, options: CompileOptions = CompileOptions()): CompileResult =
        Compilation(database, options).run(source)

    companion object {
        /** Classic Sanny Builder keywords mapped to opcodes. */
        val KEYWORD_ALIASES: Map<String, Int> = mapOf(
            "jump" to Opcodes.GOTO,
            "goto" to Opcodes.GOTO,
            "jf" to Opcodes.GOTO_IF_FALSE,
            "jump_if_false" to Opcodes.GOTO_IF_FALSE,
            "goto_if_false" to Opcodes.GOTO_IF_FALSE,
            "else_jump" to Opcodes.GOTO_IF_FALSE,
            "gosub" to Opcodes.GOSUB,
            "return" to Opcodes.RETURN,
            "end_thread" to Opcodes.TERMINATE_THIS_SCRIPT,
            "terminate_this_script" to Opcodes.TERMINATE_THIS_SCRIPT,
            "create_thread" to Opcodes.START_NEW_SCRIPT,
            "start_new_script" to Opcodes.START_NEW_SCRIPT,
            "thread" to Opcodes.SCRIPT_NAME,
            "name_thread" to Opcodes.SCRIPT_NAME,
            "script_name" to Opcodes.SCRIPT_NAME,
            "wait" to Opcodes.WAIT,
            "nop" to Opcodes.NOP,
        )

        /** PC CLEO keywords that have no equivalent in CLEO Android, with the replacement to suggest. */
        val PC_ONLY_KEYWORDS: Map<String, String> = mapOf(
            "end_custom_thread" to "CLEO Android scripts end with 004E: terminate_this_script",
            "terminate_this_custom_script" to "CLEO Android scripts end with 004E: terminate_this_script",
            "0a93" to "CLEO Android scripts end with 004E: terminate_this_script",
            "print_help_string" to "CLEO Android has no direct-string printing; add a text key to an .fxt file and use 03E5: print_help",
            "print_string_now" to "use an .fxt text key with 00BC: print_now",
            "print_formatted_now" to "use an .fxt text key with 01E5: print_with_number_now",
            "write_memory" to "use 0DD9: write_memory (CLEO Android) — note the different parameters",
            "read_memory" to "use 0DD8: read_memory (CLEO Android) — note the different parameters",
            "is_key_pressed" to "Android has no keyboard keys; use 0DE0: get_touch_point_state or 00E1 with touch points",
            "cleo_call" to "CLEO Android has no 0AB1 call; use gosub (0050) with local variables",
        )
    }
}

/** One compilation run. */
private class Compilation(private val db: OpcodeDatabase, private val options: CompileOptions) {
    private val sink = DiagnosticSink(options.fileName)
    private var format = options.format
    private val writer = BytecodeWriter()
    private val decoder = InstructionDecoder(db)

    // Symbols
    private val constants = HashMap<String, Arg>()
    private val namedLocals = HashMap<String, Int>()
    private val declaredTypes = HashMap<VarKey, ValueType>()
    private val inferredTypes = HashMap<VarKey, ValueType?>()

    // Code generation state
    private val labels = HashMap<String, Int>()
    private val userLabels = LinkedHashMap<String, Int>()
    private val fixups = ArrayList<Fixup>()
    private val emitted = ArrayList<Emitted>()
    private val dataRegions = ArrayList<IntRange>()
    private val loops = ArrayDeque<LoopLabels>()
    private var generatedLabelCounter = 0
    private val resolving = HashSet<String>()

    private data class VarKey(val global: Boolean, val index: Int)
    private data class LoopLabels(val breakLabel: String, val continueLabel: String)
    private class Emitted(val offset: Int, val opcode: Int, val negated: Boolean, val operands: MutableList<Operand>, val loc: SourceLoc) {
        var length = 0
    }
    private class Fixup(val emittedIndex: Int, val operandIndex: Int, val position: Int, val label: String, val loc: SourceLoc)

    /** A resolved value. */
    private sealed class Value {
        data class IntConst(val value: Int) : Value()
        data class FloatConst(val value: Float) : Value()
        data class Str(val text: String, val doubleQuoted: Boolean) : Value()
        data class Label(val name: String) : Value()
        data class Var(
            val global: Boolean,
            val index: Int,
            val storage: VarStorage,
            val array: ArrayInfo? = null,
        ) : Value() {
            val key get() = VarKey(global, index)
        }
    }

    private data class ArrayInfo(val indexGlobal: Boolean, val indexVar: Int, val size: Int, val elementType: ArrayElementType)

    fun run(source: String): CompileResult {
        val statements = parseWithIncludes(source, options.fileName, depth = 0, stack = mutableListOf())
        applyDirectives(statements)
        collectConstants(statements)
        allocateNamedLocals(statements)
        inferTypes(statements)
        if (!sink.hasErrors) {
            generateBlock(statements)
            resolveFixups()
        }
        var bytes: ByteArray? = null
        if (!sink.hasErrors) {
            val output = writer.toByteArray()
            if (output.isEmpty()) {
                sink.error("C100", "The script is empty: it contains no instructions")
            } else if (validate(output)) {
                lint(output)
                bytes = output
            }
        }
        return CompileResult(
            bytes = if (sink.hasErrors) null else bytes,
            diagnostics = sink.diagnostics,
            format = format,
            labels = userLabels.toMap(),
            instructionCount = emitted.size,
            sourceMap = emitted.map { SourceMapping(it.offset, it.length, it.loc.file, it.loc.line) },
        )
    }

    // ------------------------------------------------------------------ front end

    private fun parseWithIncludes(text: String, file: String?, depth: Int, stack: MutableList<String>): List<Stmt> {
        val parsed = Parser(text, file, sink).parse()
        val out = ArrayList<Stmt>(parsed.size)
        for (stmt in parsed) {
            if (stmt is DirectiveStmt && (stmt.name == "INCLUDE" || stmt.name == "I")) {
                val path = stmt.value.trim().trim('"', '\'')
                val resolver = options.includeResolver
                when {
                    resolver == null -> error(stmt.loc, "C001", "{\$INCLUDE} is not available here: no project folder to read '$path' from")
                    depth >= 16 -> error(stmt.loc, "C002", "Includes are nested too deeply (limit 16)")
                    path in stack -> error(stmt.loc, "C003", "Circular include of '$path'")
                    else -> {
                        val included = resolver.resolve(path, file)
                        if (included == null) {
                            error(stmt.loc, "C004", "Included file '$path' was not found")
                        } else {
                            stack += path
                            out += parseWithIncludes(included.text, included.name, depth + 1, stack)
                            stack.removeAt(stack.lastIndex)
                        }
                    }
                }
            } else {
                out += stmt
            }
        }
        return out
    }

    private fun applyDirectives(statements: List<Stmt>) {
        var seenCleo = false
        forEachStmt(statements) { stmt ->
            if (stmt !is DirectiveStmt) return@forEachStmt
            when (stmt.name) {
                "CLEO" -> {
                    seenCleo = true
                    val ext = stmt.value.trim()
                    if (ext.isNotEmpty()) {
                        val f = ScriptFormat.fromExtension(ext)
                        if (f == null || f == ScriptFormat.MAIN_SCM) {
                            error(stmt.loc, "C010", "Unknown CLEO extension '$ext'; use .csa, .csi or .cs")
                        } else {
                            format = f
                            if (f == ScriptFormat.CLEO_PC) {
                                warning(stmt.loc, "C011", "'.cs' is the Windows CLEO extension; CLEO Android loads .csa (auto-start) and .csi (menu) scripts")
                            }
                        }
                    }
                }
                "VERSION", "USE", "O", "OPCODE", "NOSOURCE", "EXTERNAL" ->
                    sink.info("C012", "Directive {\$${stmt.name}} has no effect in Rodwave", stmt.loc.line, stmt.loc.column, stmt.loc.length)
                else -> warning(stmt.loc, "C013", "Unknown directive {\$${stmt.name}} ignored")
            }
        }
        if (!seenCleo) {
            sink.info("C014", "No {\$CLEO} directive; compiling as ${format.title}")
        }
    }

    private fun collectConstants(statements: List<Stmt>) {
        forEachStmt(statements) { stmt ->
            if (stmt is ConstStmt) {
                for ((name, value) in stmt.entries) {
                    val key = name.lowercase()
                    when {
                        key in RESERVED -> error(stmt.loc, "C020", "'$name' is a reserved word and cannot be a constant")
                        constants.containsKey(key) -> error(stmt.loc, "C021", "Constant '$name' is already defined")
                        else -> constants[key] = value
                    }
                }
            }
        }
    }

    private fun allocateNamedLocals(statements: List<Stmt>) {
        val used = HashSet<Int>()
        forEachArg(statements) { arg ->
            if (arg is LocalVarArg) {
                for (s in 0 until arg.storage.slots) used += arg.index + s
            }
        }
        var next = 0
        forEachStmt(statements) { stmt ->
            val decls = when (stmt) {
                is DeclStmt -> listOf(stmt)
                is ForwardingDecls -> stmt.decls
                else -> emptyList()
            }
            for (decl in decls) {
                for ((target, _) in decl.entries) {
                    when (target) {
                        is NameArg -> {
                            val key = target.name.lowercase()
                            if (key in RESERVED || key in constants) {
                                error(target.loc, "C022", "'${target.name}' is already used as a keyword or constant")
                                continue
                            }
                            if (key in namedLocals) {
                                error(target.loc, "C023", "Variable '${target.name}' is already declared")
                                continue
                            }
                            while (next < 32 && next in used) next++
                            if (next >= 32) {
                                error(target.loc, "C024", "No free local variable for '${target.name}' (0@-31@ are in use)")
                                continue
                            }
                            namedLocals[key] = next
                            used += next
                            declaredTypes[VarKey(false, next)] = decl.type
                        }
                        else -> {
                            val v = resolveVar(target, silent = true)
                            if (v != null) declaredTypes[v.key] = decl.type
                        }
                    }
                }
            }
        }
    }

    private fun inferTypes(statements: List<Stmt>) {
        fun note(v: Value?, type: ValueType) {
            if (v !is Value.Var || v.array != null || v.storage != VarStorage.NUMBER) return
            val key = v.key
            if (!inferredTypes.containsKey(key)) inferredTypes[key] = type else if (inferredTypes[key] != type) inferredTypes[key] = null
        }
        fun literalType(v: Value?): ValueType? = when (v) {
            is Value.IntConst -> ValueType.INT
            is Value.FloatConst -> ValueType.FLOAT
            else -> null
        }
        fun visitCompare(left: Arg, right: Arg) {
            val l = resolveSilently(left)
            val r = resolveSilently(right)
            literalType(r)?.let { note(l, it) }
            literalType(l)?.let { note(r, it) }
        }
        forEachStmt(statements) { stmt ->
            when (stmt) {
                is AssignStmt -> {
                    val target = resolveSilently(stmt.target)
                    when (stmt.operator) {
                        "+=@", "-=@" -> note(target, ValueType.FLOAT)
                        "=#" -> Unit
                        else -> literalType(stmt.value?.let { resolveSilently(it) })?.let { note(target, it) }
                    }
                }
                is ForStmt -> literalType(resolveSilently(stmt.from))?.let { note(resolveSilently(stmt.variable), it) }
                is CommandStmt -> inferFromCommand(stmt, ::note)
                is DeclStmt, is ForwardingDecls -> Unit
                else -> Unit
            }
            conditionsOf(stmt).forEach { c ->
                when (c) {
                    is CompareCondition -> visitCompare(c.left, c.right)
                    is CommandCondition -> inferFromCommand(c.command, ::note)
                }
            }
        }
    }

    private fun inferFromCommand(stmt: CommandStmt, note: (Value?, ValueType) -> Unit) {
        val def = lookupCommand(stmt, report = false) ?: return
        val values = stmt.args.mapNotNull { resolveSilently(it, dropDecorative = true) }
        def.params.zip(values).forEach { (p, v) ->
            when (p.typeName) {
                "float" -> note(v, ValueType.FLOAT)
                "int", "bool" -> note(v, ValueType.INT)
                else -> if (p.type == ParamType.HANDLE || p.type == ParamType.MODEL) note(v, ValueType.INT)
            }
        }
    }

    // ------------------------------------------------------------------ value resolution

    private fun resolveSilently(arg: Arg, dropDecorative: Boolean = false): Value? {
        if (dropDecorative && arg is NameArg && arg.maybeDecorative && !isKnownName(arg.name)) return null
        val probe = DiagnosticSink()
        return resolveInto(arg, probe)
    }

    private fun resolve(arg: Arg): Value? = resolveInto(arg, sink)

    private fun isKnownName(name: String): Boolean {
        val key = name.lowercase()
        return key == "true" || key == "false" || key == "timera" || key == "timerb" || key in constants || key in namedLocals ||
            enumValue(name) != null
    }

    private fun enumValue(name: String): Int? {
        val dot = name.indexOf('.')
        if (dot <= 0 || dot == name.lastIndex) return null
        return db.enumValue(name.substring(0, dot), name.substring(dot + 1))
    }

    private fun resolveInto(arg: Arg, out: DiagnosticSink): Value? {
        fun err(code: String, msg: String, hint: String? = null): Value? {
            out.error(code, msg, arg.loc.line, arg.loc.column, arg.loc.length, hint, arg.loc.file)
            return null
        }
        return when (arg) {
            is IntArg -> Value.IntConst(arg.value)
            is FloatArg -> Value.FloatConst(arg.value)
            is StringArg -> Value.Str(arg.text, arg.doubleQuoted)
            is LabelArg -> Value.Label(arg.name)
            is ModelArg -> options.models.idOf(arg.name)?.let { Value.IntConst(it) }
                ?: err("C030", "Unknown model #${arg.name}", "use the numeric model id or import your game's .ide files")
            is GlobalVarArg -> {
                val offset = when {
                    arg.index != null -> if (arg.rawOffset) arg.index else arg.index * 4
                    else -> options.globals.entries.firstOrNull { it.key.equals(arg.name, ignoreCase = true) }?.value?.times(4)
                        ?: constants[arg.name!!.lowercase()]?.let { return resolveInto(it, out) }
                        ?: return err(
                            "C031", "Unknown global variable \$${arg.name}",
                            "CLEO scripts can only use numbered globals (\$123) or predefined ones like \$PLAYER_CHAR",
                        )
                }
                if (offset > 0xFFFF) return err("C032", "Global variable offset $offset is out of range")
                Value.Var(true, offset, arg.storage)
            }
            is LocalVarArg -> {
                if (arg.index > 0xFFFF) return err("C033", "Local variable index ${arg.index} is out of range")
                Value.Var(false, arg.index, arg.storage)
            }
            is NameArg -> {
                val key = arg.name.lowercase()
                when {
                    key == "true" -> Value.IntConst(1)
                    key == "false" -> Value.IntConst(0)
                    key == "timera" -> Value.Var(false, 32, VarStorage.NUMBER)
                    key == "timerb" -> Value.Var(false, 33, VarStorage.NUMBER)
                    key in constants -> {
                        if (!resolving.add(key)) return err("C034", "Constant '${arg.name}' refers to itself")
                        try {
                            resolveInto(constants.getValue(key), out)
                        } finally {
                            resolving.remove(key)
                        }
                    }
                    key in namedLocals -> Value.Var(false, namedLocals.getValue(key), VarStorage.NUMBER)
                    else -> enumValue(arg.name)?.let { Value.IntConst(it) }
                        ?: err("C035", "Unknown name '${arg.name}'", "declare it with const, int or float")
                }
            }
            is ArrayArg -> {
                val base = resolveInto(arg.base, out) as? Value.Var
                    ?: return err("C036", "Array base must be a variable")
                if (base.array != null) return err("C036", "Array base must be a plain variable")
                val index = resolveInto(arg.index, out) as? Value.Var
                    ?: return err("C037", "Array index must be a variable")
                if (index.array != null || index.storage != VarStorage.NUMBER) return err("C037", "Array index must be a plain numeric variable")
                if (index.index > 0xFFFF) return err("C037", "Array index variable out of range")
                val storage = when (arg.elementType) {
                    ArrayElementType.STRING8 -> VarStorage.STRING8
                    ArrayElementType.STRING16 -> VarStorage.STRING16
                    else -> VarStorage.NUMBER
                }
                Value.Var(base.global, base.index, storage, ArrayInfo(index.global, index.index, arg.size, arg.elementType))
            }
        }
    }

    private fun resolveVar(arg: Arg, silent: Boolean = false): Value.Var? =
        (if (silent) resolveSilently(arg) else resolve(arg)) as? Value.Var

    private fun typeOf(v: Value): ValueType? = when (v) {
        is Value.IntConst -> ValueType.INT
        is Value.FloatConst -> ValueType.FLOAT
        is Value.Var -> when {
            v.array != null -> when (v.array.elementType) {
                ArrayElementType.INT -> ValueType.INT
                ArrayElementType.FLOAT -> ValueType.FLOAT
                else -> null
            }
            v.storage != VarStorage.NUMBER -> null
            !v.global && (v.index == 32 || v.index == 33) -> ValueType.INT
            else -> declaredTypes[v.key] ?: inferredTypes[v.key]
        }
        else -> null
    }

    // ------------------------------------------------------------------ code generation

    private fun generateBlock(statements: List<Stmt>) {
        statements.forEach(::generate)
    }

    private fun generate(stmt: Stmt) {
        when (stmt) {
            is LabelStmt -> placeLabel(stmt.name, stmt.loc, user = true)
            is CommandStmt -> emitCommandStmt(stmt, inCondition = false)
            is AssignStmt -> emitAssign(stmt.target, stmt.operator, stmt.value, stmt.loc)
            is HexStmt -> {
                val start = writer.size
                writer.bytes(stmt.bytes)
                dataRegions += start until writer.size
            }
            is IfStmt -> emitIf(stmt)
            is WhileStmt -> emitWhile(stmt)
            is RepeatStmt -> emitRepeat(stmt)
            is ForStmt -> emitFor(stmt)
            is BreakStmt -> loops.lastOrNull()?.let { emitJump(Opcodes.GOTO, it.breakLabel, stmt.loc) }
                ?: error(stmt.loc, "C040", "'break' outside a loop")
            is ContinueStmt -> loops.lastOrNull()?.let { emitJump(Opcodes.GOTO, it.continueLabel, stmt.loc) }
                ?: error(stmt.loc, "C041", "'continue' outside a loop")
            is DeclStmt -> emitDeclInitializers(stmt)
            is ForwardingDecls -> stmt.decls.forEach(::emitDeclInitializers)
            is ConstStmt, is DirectiveStmt -> Unit
        }
    }

    private fun emitDeclInitializers(stmt: DeclStmt) {
        for ((target, init) in stmt.entries) {
            if (init != null) emitAssign(target, "=", init, stmt.loc)
        }
    }

    private fun newLabel(kind: String): String = "__rw_${kind}_${generatedLabelCounter++}"

    private fun placeLabel(name: String, loc: SourceLoc, user: Boolean) {
        val key = name.lowercase()
        if (labels.containsKey(key)) {
            error(loc, "C042", "Label '$name' is defined more than once")
            return
        }
        labels[key] = writer.size
        if (user) userLabels[name] = writer.size
    }

    private fun emitIf(stmt: IfStmt) {
        val n = stmt.conditions.size
        if (n == 0) return
        if (n > 8) {
            error(stmt.loc, "C043", "A condition block can have at most 8 conditions (found $n)")
            return
        }
        val andOr = when {
            n == 1 -> 0
            stmt.mode == ConditionMode.AND -> n - 1
            stmt.mode == ConditionMode.OR -> 20 + n - 1
            else -> {
                error(stmt.loc, "C044", "Several conditions need 'if and' or 'if or'")
                return
            }
        }
        emitRaw(Opcodes.ANDOR, false, listOf(IntOperand.minimal(andOr)), stmt.loc)
        stmt.conditions.forEach(::emitCondition)
        if (stmt.jumpIfFalse != null) {
            emitJump(Opcodes.GOTO_IF_FALSE, stmt.jumpIfFalse.name, stmt.jumpIfFalse.loc)
            return
        }
        val endLabel = newLabel("endif")
        val elseLabel = if (stmt.elseBody != null) newLabel("else") else endLabel
        emitJump(Opcodes.GOTO_IF_FALSE, elseLabel, stmt.loc)
        generateBlock(stmt.thenBody.orEmpty())
        if (stmt.elseBody != null) {
            emitJump(Opcodes.GOTO, endLabel, stmt.loc)
            placeLabel(elseLabel, stmt.loc, user = false)
            generateBlock(stmt.elseBody)
        }
        placeLabel(endLabel, stmt.loc, user = false)
    }

    private fun emitWhile(stmt: WhileStmt) {
        val start = newLabel("while")
        val end = newLabel("wend")
        placeLabel(start, stmt.loc, user = false)
        if (stmt.condition != null) {
            emitRaw(Opcodes.ANDOR, false, listOf(IntOperand.minimal(0)), stmt.loc)
            emitCondition(stmt.condition)
            emitJump(Opcodes.GOTO_IF_FALSE, end, stmt.loc)
        }
        loops.addLast(LoopLabels(end, start))
        generateBlock(stmt.body)
        loops.removeLast()
        emitJump(Opcodes.GOTO, start, stmt.loc)
        placeLabel(end, stmt.loc, user = false)
    }

    private fun emitRepeat(stmt: RepeatStmt) {
        val start = newLabel("repeat")
        val cont = newLabel("until")
        val end = newLabel("rend")
        placeLabel(start, stmt.loc, user = false)
        loops.addLast(LoopLabels(end, cont))
        generateBlock(stmt.body)
        loops.removeLast()
        placeLabel(cont, stmt.loc, user = false)
        emitRaw(Opcodes.ANDOR, false, listOf(IntOperand.minimal(0)), stmt.loc)
        emitCondition(stmt.until)
        emitJump(Opcodes.GOTO_IF_FALSE, start, stmt.loc)
        placeLabel(end, stmt.loc, user = false)
    }

    private fun emitFor(stmt: ForStmt) {
        val variable = resolveVar(stmt.variable) ?: return
        val varType = typeOf(variable) ?: resolveSilently(stmt.from)?.let(::typeOf) ?: ValueType.INT
        // The loop defines the variable's type for the comparison and the step below.
        if (typeOf(variable) == null) declaredTypes[variable.key] = varType
        emitAssign(stmt.variable, "=", stmt.from, stmt.loc)
        val start = newLabel("for")
        val cont = newLabel("next")
        val end = newLabel("fend")
        placeLabel(start, stmt.loc, user = false)
        emitRaw(Opcodes.ANDOR, false, listOf(IntOperand.minimal(0)), stmt.loc)
        // Leave the loop once the variable passes the end value.
        emitCompare(stmt.variable, if (stmt.downTo) "<" else ">", stmt.to, negated = true, loc = stmt.loc)
        emitJump(Opcodes.GOTO_IF_FALSE, end, stmt.loc)
        loops.addLast(LoopLabels(end, cont))
        generateBlock(stmt.body)
        loops.removeLast()
        placeLabel(cont, stmt.loc, user = false)
        val step = stmt.step ?: if (varType == ValueType.FLOAT) FloatArg(1f, stmt.loc) else IntArg(1, stmt.loc)
        emitAssign(stmt.variable, if (stmt.downTo) "-=" else "+=", step, stmt.loc)
        emitJump(Opcodes.GOTO, start, stmt.loc)
        placeLabel(end, stmt.loc, user = false)
    }

    private fun emitCondition(cond: Condition) {
        when (cond) {
            is CommandCondition -> emitCommandStmt(cond.command, inCondition = true)
            is CompareCondition -> emitCompare(cond.left, cond.operator, cond.right, cond.negated, cond.loc)
        }
    }

    private fun emitJump(opcode: Int, label: String, loc: SourceLoc) {
        val def = db[opcode] ?: run {
            error(loc, "C045", "Opcode ${hex(opcode)} is missing from the opcode database")
            return
        }
        emitResolved(def, negated = false, values = listOf(Value.Label(label) to loc), loc = loc)
    }

    /** Emits an instruction whose operands are already encoded (no labels). */
    private fun emitRaw(opcode: Int, negated: Boolean, operands: List<Operand>, loc: SourceLoc) {
        if (db[opcode] == null) {
            error(loc, "C045", "Opcode ${hex(opcode)} is missing from the opcode database")
            return
        }
        val start = writer.size
        writer.instruction(opcode, negated, operands)
        emitted += Emitted(start, opcode, negated, operands.toMutableList(), loc).also { it.length = writer.size - start }
    }

    private fun lookupCommand(stmt: CommandStmt, report: Boolean, argCount: Int? = null): OpcodeDefinition? {
        fun err(code: String, msg: String, hint: String? = null): OpcodeDefinition? {
            if (report) sink.error(code, msg, stmt.loc.line, stmt.loc.column, stmt.loc.length, hint, stmt.loc.file)
            return null
        }
        if (stmt.opcode != null) {
            return db[stmt.opcode] ?: err(
                "C050", "Unknown opcode ${hex(stmt.opcode)}",
                if (stmt.opcode in 0x0A8C..0x0AFF && db[stmt.opcode] == null) "PC CLEO opcodes (0A8C+) do not exist in CLEO Android" else "import the full Sanny Builder Library or check the number",
            )
        }
        val keyword = stmt.keyword!!.lowercase()
        ScriptCompiler.PC_ONLY_KEYWORDS[keyword]?.let { return err("C051", "'${stmt.keyword}' is a PC CLEO command that CLEO Android does not have", it) }
        ScriptCompiler.KEYWORD_ALIASES[keyword]?.let { id -> return db[id] ?: err("C050", "Opcode ${hex(id)} is missing from the opcode database") }
        val candidates = db.findByName(keyword)
        if (candidates.isEmpty()) {
            val suggestion = db.search(keyword, limit = 1).firstOrNull()?.keyword
            return err("C052", "Unknown command '${stmt.keyword}'", suggestion?.let { "did you mean '$it'?" })
        }
        if (candidates.size == 1 || argCount == null) return candidates.first()
        val matching = candidates.filter { def ->
            if (def.isVariadic) argCount >= def.fixedParamCount else argCount == def.params.size
        }
        return when (matching.size) {
            1 -> matching.first()
            0 -> candidates.first()
            else -> err(
                "C053", "'${stmt.keyword}' is ambiguous (${matching.joinToString { it.hexId }})",
                "write the opcode explicitly, e.g. ${matching.first().hexId}: ${matching.first().keyword}",
            )
        }
    }

    private fun emitCommandStmt(stmt: CommandStmt, inCondition: Boolean) {
        val values = ArrayList<Pair<Value, SourceLoc>>()
        var ok = true
        for (arg in stmt.args) {
            if (arg is NameArg && arg.maybeDecorative && !isKnownName(arg.name)) continue
            val v = resolve(arg)
            if (v == null) ok = false else values += v to arg.loc
        }
        val def = lookupCommand(stmt, report = true, argCount = values.size) ?: return
        if (!ok) return
        if (inCondition && !def.isCondition && def.operator == null) {
            warning(stmt.loc, "C054", "${def.hexId}: ${def.keyword} is not a condition command; the condition result will not change")
        }
        if (!inCondition && stmt.negated && !def.isCondition) {
            warning(stmt.loc, "C055", "Negation has no effect on ${def.hexId}: ${def.keyword}, which is not a condition")
        }
        emitResolved(def, stmt.negated, values, stmt.loc)
    }

    /** Encodes and emits [def] with already resolved values. */
    private fun emitResolved(def: OpcodeDefinition, negated: Boolean, values: List<Pair<Value, SourceLoc>>, loc: SourceLoc) {
        val variadicIndex = def.params.indexOfFirst { it.type == ParamType.ARGUMENTS }
        val fixed = def.fixedParamCount
        val countOk = if (variadicIndex >= 0) values.size >= fixed else values.size == def.params.size
        if (!countOk) {
            val expected = if (variadicIndex >= 0) "at least $fixed" else "${def.params.size}"
            sink.error(
                "C060", "${def.hexId}: expecting $expected parameter(s), found ${values.size}",
                loc.line, loc.column, loc.length, def.signature, loc.file,
            )
            return
        }
        val operands = ArrayList<Operand>()
        val labelRefs = ArrayList<Pair<Int, Pair<String, SourceLoc>>>()
        var vi = 0
        var failed = false
        for ((pi, param) in def.params.withIndex()) {
            if (param.type == ParamType.ARGUMENTS) {
                val after = def.params.size - pi - 1
                val count = values.size - vi - after
                repeat(count) {
                    val (v, l) = values[vi++]
                    if (v is Value.Label) {
                        labelRefs += operands.size to (v.name to l)
                        operands += IntOperand(0, DataType.INT32)
                    } else {
                        encode(v, null, l)?.let { operands += it } ?: run { failed = true }
                    }
                }
                operands += EndOfArgs
                continue
            }
            val (v, l) = values[vi++]
            if (param.type == ParamType.LABEL && v is Value.Label) {
                labelRefs += operands.size to (v.name to l)
                operands += IntOperand(0, DataType.INT32)
                continue
            }
            encode(v, param, l)?.let { operands += it } ?: run { failed = true }
        }
        if (failed) return
        val start = writer.size
        writer.opcode(def.id, negated)
        val record = Emitted(start, def.id, negated, operands, loc)
        val index = emitted.size
        operands.forEachIndexed { oi, op ->
            val labelRef = labelRefs.firstOrNull { it.first == oi }
            if (labelRef != null) {
                writer.u8(DataType.INT32.code)
                fixups += Fixup(index, oi, writer.size, labelRef.second.first, labelRef.second.second)
                writer.s32(0)
            } else {
                writer.operand(op)
            }
        }
        record.length = writer.size - start
        emitted += record
    }

    /** Converts a value to an operand for [param] (null = untyped variadic argument). */
    private fun encode(v: Value, param: ParamDefinition?, loc: SourceLoc): Operand? {
        fun err(code: String, msg: String, hint: String? = null): Operand? {
            sink.error(code, msg, loc.line, loc.column, loc.length, hint, loc.file)
            return null
        }
        val pname = param?.let { "'${it.displayName}'" } ?: "argument"
        if (param != null) {
            if (param.isOutput && v !is Value.Var) return err("C061", "Output parameter $pname must be a variable")
            when (param.source) {
                ParamSource.LITERAL -> if (v is Value.Var) return err("C062", "Parameter $pname must be a literal value, not a variable")
                ParamSource.VAR_GLOBAL -> if (v !is Value.Var || !v.global) return err("C063", "Parameter $pname must be a global variable")
                ParamSource.VAR_LOCAL -> if (v !is Value.Var || v.global) return err("C064", "Parameter $pname must be a local variable")
                ParamSource.VAR_ANY -> if (v !is Value.Var) return err("C065", "Parameter $pname must be a variable")
                ParamSource.ANY -> Unit
            }
        }
        val type = param?.type ?: ParamType.ANY
        return when (v) {
            is Value.Label -> err("C066", "A label (@${v.name}) is not valid for $pname")
            is Value.IntConst -> when {
                type == ParamType.LABEL -> IntOperand(v.value, DataType.INT32)
                type == ParamType.FLOAT -> FloatOperand(v.value.toFloat())
                type.isStringLike -> err("C067", "Parameter $pname expects text, found a number")
                else -> IntOperand.minimal(v.value)
            }
            is Value.FloatConst -> when {
                type == ParamType.FLOAT || type == ParamType.ANY -> FloatOperand(v.value)
                type.isStringLike -> err("C067", "Parameter $pname expects text, found a number")
                else -> err("C068", "Parameter $pname expects an integer, found ${v.value}")
            }
            is Value.Str -> when {
                type == ParamType.ANY || type.isStringLike -> encodeString(v, loc)
                else -> err("C069", "Parameter $pname expects a number, found a string")
            }
            is Value.Var -> {
                val stringVar = v.storage != VarStorage.NUMBER
                if (type.isStringLike && !stringVar) {
                    return err("C070", "Parameter $pname expects text; use a string variable such as 0@s or s\$12")
                }
                if (type.isNumeric && stringVar) return err("C071", "Parameter $pname expects a number, found a string variable")
                if (!v.global && v.index > 0xFFFF) return err("C033", "Local variable index out of range")
                val arr = v.array
                if (arr == null) {
                    VarOperand(DataType.variable(v.global, v.storage), v.index)
                } else {
                    ArrayOperand(DataType.array(v.global, v.storage), v.index, arr.indexVar, arr.size, arr.elementType.code, arr.indexGlobal)
                }
            }
        }
    }

    /** 'short' text becomes an 8- or 16-byte string, "double quoted" text a variable-length string. */
    private fun encodeString(v: Value.Str, loc: SourceLoc): Operand? {
        val ok = v.text.all { it.code in 0x20..0xFF }
        if (!ok) {
            sink.error("C072", "Strings may only contain Latin-1 printable characters", loc.line, loc.column, loc.length, file = loc.file)
            return null
        }
        val length = v.text.length
        return when {
            v.doubleQuoted -> {
                if (length > 255) {
                    sink.error("C073", "String is longer than 255 characters", loc.line, loc.column, loc.length, file = loc.file)
                    null
                } else {
                    StringOperand.of(DataType.STRING_VARLEN, v.text)
                }
            }
            length <= 7 -> StringOperand.of(DataType.STRING8, v.text)
            length <= 15 -> StringOperand.of(DataType.STRING16, v.text)
            else -> {
                sink.error("C074", "Single-quoted strings hold at most 15 characters; use \"double quotes\" for longer text", loc.line, loc.column, loc.length, file = loc.file)
                null
            }
        }
    }

    // ------------------------------------------------------------------ operators

    private fun emitAssign(targetArg: Arg, op: String, valueArg: Arg?, loc: SourceLoc) {
        val target = resolveVar(targetArg) ?: run {
            if (resolve(targetArg) != null) error(targetArg.loc, "C080", "Only variables can be assigned")
            return
        }
        var value: Value = when {
            valueArg != null -> resolve(valueArg) ?: return
            else -> if (typeOf(target) == ValueType.FLOAT) Value.FloatConst(1f) else Value.IntConst(1)
        }
        val libOp = when (op) {
            "=" -> "="
            "+=", "++" -> "+"
            "-=", "--" -> "-"
            "*=" -> "*"
            "/=" -> "/"
            "+=@" -> "+=@"
            "-=@" -> "-=@"
            "=#" -> "=#"
            else -> {
                error(loc, "C081", "Unsupported operator '$op'")
                return
            }
        }
        if (value is Value.Label) {
            error(loc, "C082", "Labels cannot be assigned; use 0DD0: store_label_pointer to get a label's address")
            return
        }
        // String assignment: s$x = 'TEXT'
        if (target.storage != VarStorage.NUMBER || value is Value.Str) {
            emitStringOp(target, libOp, value, negated = false, loc = loc)
            return
        }
        var targetType = typeOf(target)
        var valueType = typeOf(value)
        if (libOp == "=#") {
            when {
                targetType == null && valueType != null -> targetType = other(valueType)
                valueType == null && targetType != null -> valueType = other(targetType)
            }
        } else {
            when {
                targetType == null && valueType != null -> targetType = valueType
                valueType == null && targetType != null && value is Value.Var -> valueType = targetType
            }
        }
        if (targetType == null || valueType == null) {
            error(loc, "C083", "Cannot tell whether ${describe(targetArg)} is an integer or a float", "declare it first, e.g. 'int ${describe(targetArg)}' or 'float ${describe(targetArg)}'")
            return
        }
        if (libOp != "=#" && targetType != valueType) {
            if (targetType == ValueType.FLOAT && value is Value.IntConst) {
                value = Value.FloatConst(value.value.toFloat())
                valueType = ValueType.FLOAT
            } else {
                error(loc, "C084", "Type mismatch: ${describe(targetArg)} is ${targetType.name.lowercase()} but the value is ${valueType.name.lowercase()}", "use =# to convert between integer and float")
                return
            }
        }
        if (libOp == "=#" && targetType == valueType) {
            error(loc, "C085", "'=#' converts between integer and float; both sides are ${targetType.name.lowercase()}")
            return
        }
        val def = findOperatorOpcode(libOp, target, targetType, value, valueType)
        if (def == null) {
            error(loc, "C086", "No opcode performs ${describe(targetArg)} $op ${valueArg?.let(::describe) ?: ""} with these operand kinds".replace("  ", " "))
            return
        }
        emitResolved(def, false, listOf(target to targetArg.loc, value to (valueArg?.loc ?: loc)), loc)
    }

    private fun emitCompare(leftArg: Arg, rawOp: String, rightArg: Arg, negated: Boolean, loc: SourceLoc) {
        var left = resolve(leftArg) ?: return
        var right = resolve(rightArg) ?: return
        var op = rawOp
        var neg = negated
        var swapped = false
        when (op) {
            "<" -> { op = ">"; swapped = true }
            "<=" -> { op = ">="; swapped = true }
            "!=", "<>" -> { op = "=="; neg = !neg }
        }
        if (swapped) {
            val t = left; left = right; right = t
        }
        if (left is Value.Str || right is Value.Str || (left is Value.Var && left.storage != VarStorage.NUMBER) || (right is Value.Var && right.storage != VarStorage.NUMBER)) {
            if (op != "==") {
                error(loc, "C087", "Text can only be compared with == or <>")
                return
            }
            val (variable, other) = if (left is Value.Var) left to right else if (right is Value.Var) right to left else {
                error(loc, "C088", "Comparing two constants is not possible")
                return
            }
            emitStringOp(variable, "==", other, neg, loc)
            return
        }
        if (left !is Value.Var && right !is Value.Var) {
            error(loc, "C088", "Comparing two constants is not possible")
            return
        }
        var lt = typeOf(left)
        var rt = typeOf(right)
        if (lt == null && rt != null) lt = rt
        if (rt == null && lt != null) rt = lt
        if (lt == null || rt == null) {
            error(loc, "C083", "Cannot tell whether the compared values are integers or floats", "declare the variable with 'int' or 'float'")
            return
        }
        if (lt != rt) {
            when {
                lt == ValueType.FLOAT && right is Value.IntConst -> { right = Value.FloatConst(right.value.toFloat()); rt = lt }
                rt == ValueType.FLOAT && left is Value.IntConst -> { left = Value.FloatConst(left.value.toFloat()); lt = rt }
                else -> {
                    error(loc, "C084", "Cannot compare an integer with a float")
                    return
                }
            }
        }
        var def = findOperatorOpcode(op, left, lt, right, rt)
        if (def == null && op == "==") {
            def = findOperatorOpcode(op, right, rt, left, lt)
            if (def != null) {
                val t = left; left = right; right = t
            }
        }
        if (def == null) {
            error(loc, "C086", "No opcode compares these operand kinds with '$rawOp'")
            return
        }
        emitResolved(def, neg, listOf(left to loc, right to loc), loc)
    }

    private fun emitStringOp(variable: Value.Var, op: String, value: Value, negated: Boolean, loc: SourceLoc) {
        if (variable.storage == VarStorage.NUMBER) {
            error(loc, "C089", "Text values need a string variable (0@s, 0@v, s\$12, v\$12)")
            return
        }
        if (op != "=" && op != "==") {
            error(loc, "C090", "Only = and == work with text")
            return
        }
        val long = variable.storage == VarStorage.STRING16
        val def = db.withOperator(op).firstOrNull { d ->
            val p0 = d.params.getOrNull(0) ?: return@firstOrNull false
            p0.typeName == "string" && (p0.source == ParamSource.VAR_GLOBAL) == variable.global &&
                d.name.contains("16") == long
        }
        if (def == null) {
            error(loc, "C091", "No opcode handles this text operation in the opcode database")
            return
        }
        emitResolved(def, negated, listOf(variable to loc, value to loc), loc)
    }

    private fun findOperatorOpcode(op: String, a: Value, aType: ValueType, b: Value, bType: ValueType): OpcodeDefinition? =
        db.withOperator(op).firstOrNull { def ->
            def.params.size == 2 && matchesSide(def.params[0], a, aType) && matchesSide(def.params[1], b, bType)
        }

    private fun matchesSide(p: ParamDefinition, v: Value, type: ValueType): Boolean {
        val typeName = if (type == ValueType.INT) "int" else "float"
        if (p.typeName != typeName) return false
        return when (p.source) {
            ParamSource.VAR_GLOBAL -> v is Value.Var && v.global
            ParamSource.VAR_LOCAL -> v is Value.Var && !v.global
            ParamSource.LITERAL -> v is Value.IntConst || v is Value.FloatConst
            ParamSource.VAR_ANY -> v is Value.Var
            ParamSource.ANY -> true
        }
    }

    private fun other(t: ValueType) = if (t == ValueType.INT) ValueType.FLOAT else ValueType.INT

    private fun describe(arg: Arg): String = when (arg) {
        is LocalVarArg -> "${arg.index}@" + when (arg.storage) { VarStorage.STRING8 -> "s"; VarStorage.STRING16 -> "v"; else -> "" }
        is GlobalVarArg -> (if (arg.storage == VarStorage.STRING8) "s" else if (arg.storage == VarStorage.STRING16) "v" else "") +
            (if (arg.rawOffset) "&" else "$") + (arg.name ?: arg.index.toString())
        is NameArg -> arg.name
        is IntArg -> arg.value.toString()
        is FloatArg -> arg.value.toString()
        is StringArg -> if (arg.doubleQuoted) "\"${arg.text}\"" else "'${arg.text}'"
        is LabelArg -> "@${arg.name}"
        is ModelArg -> "#${arg.name}"
        is ArrayArg -> describe(arg.base) + "(" + describe(arg.index) + "," + arg.size + arg.elementType.suffix + ")"
    }

    // ------------------------------------------------------------------ labels and validation

    private fun resolveFixups() {
        for (f in fixups) {
            val target = labels[f.label.lowercase()]
            if (target == null) {
                error(f.loc, "C092", "Label '${f.label}' is not defined")
                continue
            }
            val encoded = if (format.isHeaderless) {
                if (target == 0) {
                    error(
                        f.loc, "C093", "Label '${f.label}' is at the very start of the script; in a CLEO script a jump to offset 0 would land in main.scm",
                        "put an instruction such as '0000: nop' before the label",
                    )
                    continue
                }
                -target
            } else {
                target
            }
            writer.patchS32(f.position, encoded)
            emitted[f.emittedIndex].operands[f.operandIndex] = IntOperand(encoded, DataType.INT32)
        }
    }

    /** Re-decodes the output and compares it with what was emitted. */
    private fun validate(output: ByteArray): Boolean {
        var ok = true
        val starts = HashSet<Int>()
        for (e in emitted) {
            starts += e.offset
            when (val r = decoder.decode(output, e.offset)) {
                is DecodeResult.Error -> {
                    error(e.loc, "V001", "Output validation failed at offset ${e.offset}: ${r.message} (this is a compiler bug)")
                    ok = false
                }
                is DecodeResult.Ok -> {
                    val ins = r.instruction
                    if (ins.opcode != e.opcode || ins.negated != e.negated || ins.length != e.length || ins.operands != e.operands) {
                        error(e.loc, "V002", "Output validation failed at offset ${e.offset}: decoded instruction differs from the emitted one (this is a compiler bug)")
                        ok = false
                    }
                }
            }
        }
        // Every byte must belong to an instruction or a hex block.
        val covered = BooleanArray(output.size)
        emitted.forEach { e -> for (i in e.offset until e.offset + e.length) covered[i] = true }
        dataRegions.forEach { r -> for (i in r) covered[i] = true }
        val gap = covered.indexOfFirst { !it }
        if (gap >= 0) {
            sink.error("V003", "Output validation failed: byte $gap is not part of any instruction (this is a compiler bug)")
            ok = false
        }
        // Jump targets must be instruction or data-block boundaries.
        val validTargets = starts + dataRegions.map { it.first } + setOf(output.size)
        for (f in fixups) {
            val target = labels[f.label.lowercase()] ?: continue
            if (target !in validTargets) {
                error(f.loc, "V004", "Label '${f.label}' does not point to the start of an instruction")
                ok = false
            }
        }
        return ok
    }

    private fun lint(output: ByteArray) {
        // Condition blocks: ANDOR n must be followed by the right number of conditions.
        for ((i, e) in emitted.withIndex()) {
            if (e.opcode != Opcodes.ANDOR) continue
            val n = (e.operands.firstOrNull() as? IntOperand)?.value ?: continue
            val count = Opcodes.conditionCount(n)
            if (count == null) {
                warning(e.loc, "L001", "00D6: if $n is not a valid condition count (use 0, 1-7 for AND, 21-27 for OR)")
                continue
            }
            val following = emitted.drop(i + 1).take(count)
            val notConditions = following.filter { f -> db[f.opcode]?.let { !it.isCondition } ?: true }
            if (following.size < count || notConditions.isNotEmpty()) {
                warning(e.loc, "L002", "00D6: if $n expects $count condition(s) to follow")
            }
        }
        // Labels placed at the very end of the script.
        userLabels.forEach { (name, off) ->
            if (off == output.size && fixups.any { it.label.equals(name, ignoreCase = true) }) {
                sink.warning("L003", "Label '$name' is at the end of the script; jumping there runs past the last instruction")
            }
        }
        // Execution falling off the end.
        val last = emitted.maxByOrNull { it.offset }
        if (last != null && last.offset + last.length == output.size && last.opcode !in Opcodes.TERMINATORS) {
            warning(last.loc, "L004", "The script can run past its last instruction", "end it with 004E: terminate_this_script or a jump")
        }
        // Backward jumps whose loop body never waits freeze the game.
        for (f in fixups) {
            val e = emitted[f.emittedIndex]
            if (e.opcode != Opcodes.GOTO) continue
            val target = labels[f.label.lowercase()] ?: continue
            if (target > e.offset) continue
            val bodyWaits = emitted.any { it.offset in target..e.offset && it.opcode == Opcodes.WAIT }
            val bodyCalls = emitted.any { it.offset in target..e.offset && (it.opcode == Opcodes.GOSUB) }
            if (!bodyWaits && !bodyCalls) {
                warning(e.loc, "L005", "This loop never calls 0001: wait; the game will freeze while it runs", "add 'wait 0' inside the loop")
            }
        }
        // CLEO local variable range, unsupported commands.
        val reportedLocals = HashSet<Int>()
        for (e in emitted) {
            val def = db[e.opcode]
            if (def != null && def.isUnsupported) {
                warning(e.loc, "L006", "${def.hexId}: ${def.keyword} is marked as unsupported on this game in the opcode library")
            }
            if (!format.isHeaderless) continue
            for (op in e.operands) {
                val top = when {
                    op is VarOperand && op.type.isLocal -> op.index + op.type.storage.slots - 1
                    op is ArrayOperand && op.type.isLocal -> op.base + op.size * op.type.storage.slots - 1
                    else -> continue
                }
                if (top > 33 && reportedLocals.add(top)) {
                    warning(e.loc, "L007", "Local variable slot $top is beyond 0@-31@ and the timers (32@, 33@) available to CLEO scripts")
                }
            }
        }
    }

    // ------------------------------------------------------------------ traversal helpers

    private fun forEachStmt(statements: List<Stmt>, action: (Stmt) -> Unit) {
        for (s in statements) {
            action(s)
            when (s) {
                is IfStmt -> {
                    s.thenBody?.let { forEachStmt(it, action) }
                    s.elseBody?.let { forEachStmt(it, action) }
                }
                is WhileStmt -> forEachStmt(s.body, action)
                is RepeatStmt -> forEachStmt(s.body, action)
                is ForStmt -> forEachStmt(s.body, action)
                else -> Unit
            }
        }
    }

    private fun conditionsOf(stmt: Stmt): List<Condition> = when (stmt) {
        is IfStmt -> stmt.conditions
        is WhileStmt -> listOfNotNull(stmt.condition)
        is RepeatStmt -> listOf(stmt.until)
        else -> emptyList()
    }

    private fun forEachArg(statements: List<Stmt>, action: (Arg) -> Unit) {
        fun visit(a: Arg?) {
            if (a == null) return
            action(a)
            if (a is ArrayArg) {
                visit(a.base)
                visit(a.index)
            }
        }
        fun visitCond(c: Condition) {
            when (c) {
                is CommandCondition -> c.command.args.forEach(::visit)
                is CompareCondition -> { visit(c.left); visit(c.right) }
            }
        }
        forEachStmt(statements) { s ->
            when (s) {
                is CommandStmt -> s.args.forEach(::visit)
                is AssignStmt -> { visit(s.target); visit(s.value) }
                is ForStmt -> { visit(s.variable); visit(s.from); visit(s.to); visit(s.step) }
                is DeclStmt -> s.entries.forEach { (t, v) -> visit(t); visit(v) }
                is ForwardingDecls -> s.decls.forEach { d -> d.entries.forEach { (t, v) -> visit(t); visit(v) } }
                is ConstStmt -> s.entries.forEach { visit(it.second) }
                else -> Unit
            }
            conditionsOf(s).forEach(::visitCond)
        }
    }

    private fun error(loc: SourceLoc, code: String, message: String, hint: String? = null) =
        sink.error(code, message, loc.line, loc.column, loc.length, hint, loc.file)

    private fun warning(loc: SourceLoc, code: String, message: String, hint: String? = null) =
        sink.warning(code, message, loc.line, loc.column, loc.length, hint, loc.file)

    private fun hex(id: Int) = id.toString(16).uppercase().padStart(4, '0')

    companion object {
        val RESERVED = setOf(
            "if", "then", "else", "end", "while", "repeat", "until", "for", "to", "downto", "step", "break", "continue",
            "not", "and", "or", "const", "var", "int", "float", "hex", "true", "false", "timera", "timerb",
        )
    }
}
