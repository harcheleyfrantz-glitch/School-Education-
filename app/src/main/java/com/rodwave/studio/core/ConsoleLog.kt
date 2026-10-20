package com.rodwave.studio.core

import androidx.compose.runtime.mutableStateListOf
import com.rodwave.engine.fs.VirtualFile
import com.rodwave.engine.fs.readText
import com.rodwave.engine.fs.resolve
import com.rodwave.engine.fs.writeFile
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

enum class LogLevel { INFO, SUCCESS, WARNING, ERROR }

data class LogEntry(val time: Long, val level: LogLevel, val source: String, val message: String) {
    fun render(): String = "${FORMAT.get()!!.format(Date(time))} ${level.name.padEnd(7)} [$source] $message"

    companion object {
        private val FORMAT = ThreadLocal.withInitial { SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US) }
    }
}

/**
 * The project console: a record of real operations (compiles, scans, installs). Entries are kept
 * in memory for the UI and appended to `logs/console.log` so they survive restarts.
 */
class ConsoleLog(private val storage: VirtualFile, private val clock: () -> Long = System::currentTimeMillis) {
    val entries = mutableStateListOf<LogEntry>()

    init {
        // Show the tail of the previous session's log.
        runCatching { storage.resolve(FILE)?.readText(512 * 1024) }.getOrNull()?.lines()?.takeLast(200)?.forEach { line ->
            if (line.isNotBlank()) entries += LogEntry(0, LogLevel.INFO, "history", line)
        }
    }

    private var dirty = false

    fun log(level: LogLevel, source: String, message: String) {
        val entry = LogEntry(clock(), level, source, message)
        entries += entry
        if (entries.size > MAX_ENTRIES) entries.removeRange(0, entries.size - MAX_ENTRIES)
        dirty = true
    }

    fun info(source: String, message: String) = log(LogLevel.INFO, source, message)
    fun success(source: String, message: String) = log(LogLevel.SUCCESS, source, message)
    fun warning(source: String, message: String) = log(LogLevel.WARNING, source, message)
    fun error(source: String, message: String) = log(LogLevel.ERROR, source, message)

    fun clear() {
        entries.clear()
        dirty = true
        flush()
    }

    fun export(): String = entries.joinToString("\n") { if (it.time == 0L) it.message else it.render() }

    /** Writes the log to disk if it changed; called periodically and when the app goes to the background. */
    fun flush() {
        if (!dirty) return
        dirty = false
        runCatching { storage.writeFile(FILE, export().toByteArray()) }
    }

    companion object {
        const val FILE = "logs/console.log"
        const val MAX_ENTRIES = 2_000
    }
}
