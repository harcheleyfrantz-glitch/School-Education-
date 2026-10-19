package com.rodwave.engine.editor

/** Editor state captured for undo/redo. */
data class EditorSnapshot(val text: String, val selectionStart: Int, val selectionEnd: Int = selectionStart)

/**
 * Undo/redo stacks of whole-text snapshots.
 *
 * Consecutive single-character typing (or deleting) within [coalesceMillis] is merged into one
 * undo step, like desktop editors. Memory is bounded by [maxEntries] and [maxTotalChars].
 */
class UndoHistory(
    private val maxEntries: Int = 300,
    private val maxTotalChars: Long = 16_000_000,
    private val coalesceMillis: Long = 1_000,
) {
    private enum class Kind { INSERT_CHAR, DELETE_CHAR, OTHER }

    private val undoStack = ArrayDeque<EditorSnapshot>()
    private val redoStack = ArrayDeque<EditorSnapshot>()
    private var lastKind: Kind? = null
    private var lastTime = 0L
    private var lastCaret = -1

    val canUndo: Boolean get() = undoStack.isNotEmpty()
    val canRedo: Boolean get() = redoStack.isNotEmpty()

    /** Call for every text change, with the state before and after it. */
    fun record(before: EditorSnapshot, after: EditorSnapshot, now: Long) {
        if (before.text == after.text) return
        val kind = classify(before.text, after.text)
        // Whitespace insertions are classified as OTHER, so each word becomes its own undo step.
        val coalesce = kind != Kind.OTHER && kind == lastKind && now - lastTime <= coalesceMillis && before.selectionStart == lastCaret
        if (!coalesce) {
            undoStack.addLast(before)
            trim()
        }
        redoStack.clear()
        lastKind = kind
        lastTime = now
        lastCaret = after.selectionStart
    }

    /** Forces the next change to start a new undo step (e.g. after moving the caret). */
    fun breakCoalescing() {
        lastKind = null
    }

    fun undo(current: EditorSnapshot): EditorSnapshot? {
        val previous = undoStack.removeLastOrNull() ?: return null
        redoStack.addLast(current)
        lastKind = null
        return previous
    }

    fun redo(current: EditorSnapshot): EditorSnapshot? {
        val next = redoStack.removeLastOrNull() ?: return null
        undoStack.addLast(current)
        lastKind = null
        return next
    }

    fun clear() {
        undoStack.clear()
        redoStack.clear()
        lastKind = null
    }

    private fun trim() {
        while (undoStack.size > maxEntries) undoStack.removeFirst()
        var total = undoStack.sumOf { it.text.length.toLong() }
        while (total > maxTotalChars && undoStack.size > 1) {
            total -= undoStack.removeFirst().text.length
        }
    }

    private fun classify(old: String, new: String): Kind {
        val delta = new.length - old.length
        if (delta != 1 && delta != -1) return Kind.OTHER
        var prefix = 0
        val min = minOf(old.length, new.length)
        while (prefix < min && old[prefix] == new[prefix]) prefix++
        val longer = if (delta > 0) new else old
        val shorter = if (delta > 0) old else new
        // Exactly one character inserted or removed at `prefix`.
        if (longer.regionMatches(prefix + 1, shorter, prefix, shorter.length - prefix)) {
            if (delta > 0 && new[prefix].isWhitespace()) return Kind.OTHER
            return if (delta > 0) Kind.INSERT_CHAR else Kind.DELETE_CHAR
        }
        return Kind.OTHER
    }
}
