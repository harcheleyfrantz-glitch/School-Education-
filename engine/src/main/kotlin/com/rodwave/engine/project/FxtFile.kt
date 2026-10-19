package com.rodwave.engine.project

import com.rodwave.engine.diagnostics.Diagnostic
import com.rodwave.engine.diagnostics.DiagnosticSink

data class FxtEntry(val key: String, val text: String, val line: Int)

/** CLEO text tables: one `KEY text` entry per line, `#` or `//` comments. */
object FxtFile {
    private val KEY = Regex("^[A-Za-z0-9_]{1,7}$")

    fun parse(source: String, fileName: String? = null): Pair<List<FxtEntry>, List<Diagnostic>> {
        val sink = DiagnosticSink(fileName)
        val entries = ArrayList<FxtEntry>()
        val seen = HashMap<String, Int>()
        source.lines().forEachIndexed { i, raw ->
            val lineNo = i + 1
            val line = raw.trim()
            if (line.isEmpty() || line.startsWith("#") || line.startsWith("//")) return@forEachIndexed
            val key = line.substringBefore(' ').substringBefore('\t')
            val text = line.substring(key.length).trim()
            when {
                !KEY.matches(key) -> sink.error("F001", "Key '$key' must be 1-7 letters, digits or underscores", lineNo, 1, key.length)
                text.isEmpty() -> sink.warning("F002", "Key '$key' has no text", lineNo, 1, key.length)
                else -> {
                    seen[key.uppercase()]?.let { first -> sink.warning("F003", "Key '$key' is already defined on line $first", lineNo, 1, key.length) }
                    seen.putIfAbsent(key.uppercase(), lineNo)
                    entries += FxtEntry(key, text, lineNo)
                }
            }
            if (raw.any { it.code > 0xFF }) sink.warning("F004", "Characters outside Latin-1 may not display in game", lineNo, 1, raw.length)
        }
        return entries to sink.diagnostics
    }
}
