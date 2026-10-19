package com.rodwave.engine.editor

enum class DiffOp { EQUAL, INSERT, DELETE }

data class DiffLine(val op: DiffOp, val oldLine: Int?, val newLine: Int?, val text: String)

/** Line diff using Myers' O(ND) algorithm, with a size guard for very different inputs. */
object TextDiff {
    private const val MAX_D = 2_000

    fun diff(oldText: String, newText: String): List<DiffLine> = diffLines(oldText.lines(), newText.lines())

    fun diffLines(a: List<String>, b: List<String>): List<DiffLine> {
        // Trim common prefix and suffix first; they are always equal.
        var prefix = 0
        while (prefix < a.size && prefix < b.size && a[prefix] == b[prefix]) prefix++
        var suffix = 0
        while (suffix < a.size - prefix && suffix < b.size - prefix && a[a.size - 1 - suffix] == b[b.size - 1 - suffix]) suffix++
        val result = ArrayList<DiffLine>()
        for (i in 0 until prefix) result += DiffLine(DiffOp.EQUAL, i, i, a[i])
        result += myers(a.subList(prefix, a.size - suffix), b.subList(prefix, b.size - suffix), prefix, prefix)
        for (k in suffix downTo 1) {
            val ai = a.size - k
            val bi = b.size - k
            result += DiffLine(DiffOp.EQUAL, ai, bi, a[ai])
        }
        return result
    }

    private fun myers(a: List<String>, b: List<String>, aOffset: Int, bOffset: Int): List<DiffLine> {
        val n = a.size
        val m = b.size
        if (n == 0) return b.mapIndexed { j, t -> DiffLine(DiffOp.INSERT, null, bOffset + j, t) }
        if (m == 0) return a.mapIndexed { i, t -> DiffLine(DiffOp.DELETE, aOffset + i, null, t) }
        val max = n + m
        val offset = max
        val v = IntArray(2 * max + 2)
        // trace[d] holds v[-d..d] as it was before step d (O(D^2) memory overall).
        val trace = ArrayList<IntArray>()
        var found = false
        var d = 0
        while (d <= max) {
            if (d > MAX_D) break
            trace += v.copyOfRange(offset - d, offset + d + 1)
            var k = -d
            while (k <= d) {
                var x = if (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])) v[offset + k + 1] else v[offset + k - 1] + 1
                var y = x - k
                while (x < n && y < m && a[x] == b[y]) {
                    x++
                    y++
                }
                v[offset + k] = x
                if (x >= n && y >= m) {
                    found = true
                    break
                }
                k += 2
            }
            if (found) break
            d++
        }
        if (!found) {
            // Too different to diff cheaply: report everything as replaced.
            return a.mapIndexed { i, t -> DiffLine(DiffOp.DELETE, aOffset + i, null, t) } +
                b.mapIndexed { j, t -> DiffLine(DiffOp.INSERT, null, bOffset + j, t) }
        }
        // Backtrack.
        val out = ArrayList<DiffLine>()
        var x = n
        var y = m
        for (step in trace.indices.reversed()) {
            val window = trace[step]
            val dd = step
            fun at(kk: Int) = window[kk + dd]
            val k = x - y
            val prevK = if (k == -dd || (k != dd && at(k - 1) < at(k + 1))) k + 1 else k - 1
            val prevX = if (dd == 0) 0 else at(prevK)
            val prevY = prevX - prevK
            while (x > prevX && y > prevY) {
                x--
                y--
                out += DiffLine(DiffOp.EQUAL, aOffset + x, bOffset + y, a[x])
            }
            if (dd > 0) {
                if (x == prevX) {
                    y--
                    out += DiffLine(DiffOp.INSERT, null, bOffset + y, b[y])
                } else {
                    x--
                    out += DiffLine(DiffOp.DELETE, aOffset + x, null, a[x])
                }
            }
        }
        return out.asReversed()
    }

    /** Unified-diff text with [context] lines around each change. */
    fun unified(oldText: String, newText: String, oldName: String = "a", newName: String = "b", context: Int = 3): String {
        val lines = diff(oldText, newText)
        if (lines.all { it.op == DiffOp.EQUAL }) return ""
        val changed = lines.indices.filter { lines[it].op != DiffOp.EQUAL }
        val keep = BooleanArray(lines.size)
        changed.forEach { c -> for (i in (c - context).coerceAtLeast(0)..(c + context).coerceAtMost(lines.lastIndex)) keep[i] = true }
        return buildString {
            appendLine("--- $oldName")
            appendLine("+++ $newName")
            var i = 0
            while (i < lines.size) {
                if (!keep[i]) { i++; continue }
                var j = i
                while (j < lines.size && keep[j]) j++
                val hunk = lines.subList(i, j)
                val oldStart = hunk.firstNotNullOfOrNull { it.oldLine } ?: 0
                val newStart = hunk.firstNotNullOfOrNull { it.newLine } ?: 0
                appendLine("@@ -${oldStart + 1},${hunk.count { it.op != DiffOp.INSERT }} +${newStart + 1},${hunk.count { it.op != DiffOp.DELETE }} @@")
                hunk.forEach { l -> append(when (l.op) { DiffOp.EQUAL -> " "; DiffOp.INSERT -> "+"; DiffOp.DELETE -> "-" }).appendLine(l.text) }
                i = j
            }
        }
    }
}
