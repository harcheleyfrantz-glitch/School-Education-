package com.rodwave.engine.diagnostics

enum class Severity { ERROR, WARNING, INFO }

/**
 * A message produced by the compiler, decompiler or an analyzer.
 *
 * Source diagnostics carry a 1-based [line]/[column]; binary diagnostics carry a byte [offset].
 * A value of 0 for [line] means the diagnostic is not tied to a source location.
 */
data class Diagnostic(
    val severity: Severity,
    val code: String,
    val message: String,
    val line: Int = 0,
    val column: Int = 0,
    val length: Int = 0,
    val file: String? = null,
    val offset: Int? = null,
    val hint: String? = null,
) {
    val isError: Boolean get() = severity == Severity.ERROR

    /** "file:line:column: error E1001: message" style rendering for logs and the console. */
    fun render(): String = buildString {
        if (file != null) append(file).append(':')
        if (line > 0) {
            append(line)
            if (column > 0) append(':').append(column)
            append(": ")
        } else if (file != null) {
            append(' ')
        }
        if (offset != null) append("@0x").append(offset.toString(16).uppercase().padStart(4, '0')).append(": ")
        append(severity.name.lowercase()).append(' ').append(code).append(": ").append(message)
        if (hint != null) append(" (hint: ").append(hint).append(')')
    }

    override fun toString(): String = render()
}

/** Collects diagnostics while a tool runs. */
class DiagnosticSink(private val file: String? = null) {
    private val items = mutableListOf<Diagnostic>()

    val diagnostics: List<Diagnostic> get() = items.toList()
    val hasErrors: Boolean get() = items.any { it.isError }
    val errorCount: Int get() = items.count { it.isError }
    val warningCount: Int get() = items.count { it.severity == Severity.WARNING }

    fun error(code: String, message: String, line: Int = 0, column: Int = 0, length: Int = 0, hint: String? = null, file: String? = this.file) =
        add(Diagnostic(Severity.ERROR, code, message, line, column, length, file, hint = hint))

    fun warning(code: String, message: String, line: Int = 0, column: Int = 0, length: Int = 0, hint: String? = null, file: String? = this.file) =
        add(Diagnostic(Severity.WARNING, code, message, line, column, length, file, hint = hint))

    fun info(code: String, message: String, line: Int = 0, column: Int = 0, length: Int = 0, hint: String? = null, file: String? = this.file) =
        add(Diagnostic(Severity.INFO, code, message, line, column, length, file, hint = hint))

    fun binaryError(code: String, message: String, offset: Int, hint: String? = null) =
        add(Diagnostic(Severity.ERROR, code, message, file = file, offset = offset, hint = hint))

    fun binaryWarning(code: String, message: String, offset: Int, hint: String? = null) =
        add(Diagnostic(Severity.WARNING, code, message, file = file, offset = offset, hint = hint))

    fun add(diagnostic: Diagnostic) {
        items += diagnostic
    }

    fun addAll(diagnostics: Collection<Diagnostic>) {
        items += diagnostics
    }
}
