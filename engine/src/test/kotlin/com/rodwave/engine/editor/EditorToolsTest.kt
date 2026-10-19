package com.rodwave.engine.editor

import com.rodwave.engine.compiler.ScriptCompiler
import com.rodwave.engine.opcode.CoreOpcodes
import com.rodwave.engine.project.Templates
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class EditorToolsTest {
    private val db = CoreOpcodes.database

    @Test
    fun highlighterClassifiesTokens() {
        val text = "{\$CLEO .csa}\n:LOOP\n0001: wait 0 // pause\nif 0@ > 5.0\nthen\n  get_char_coordinates \$PLAYER_CHAR 1@ 2@ 3@\nend\njump @LOOP"
        val spans = SyntaxHighlighter(db).highlight(text)
        fun styleOf(word: String) = spans.first { text.substring(it.start, it.end) == word }.style
        assertEquals(SyntaxStyle.DIRECTIVE, styleOf("{\$CLEO .csa}"))
        assertEquals(SyntaxStyle.LABEL, styleOf(":LOOP"))
        assertEquals(SyntaxStyle.OPCODE, styleOf("0001:"))
        assertEquals(SyntaxStyle.COMMAND, styleOf("wait"))
        assertEquals(SyntaxStyle.COMMENT, styleOf("// pause"))
        assertEquals(SyntaxStyle.KEYWORD, styleOf("if"))
        assertEquals(SyntaxStyle.LOCAL_VAR, styleOf("0@"))
        assertEquals(SyntaxStyle.NUMBER, styleOf("5.0"))
        assertEquals(SyntaxStyle.GLOBAL_VAR, styleOf("\$PLAYER_CHAR"))
        assertEquals(SyntaxStyle.COMMAND, styleOf("get_char_coordinates"))
        assertEquals(SyntaxStyle.COMMAND, styleOf("jump"))
    }

    @Test
    fun undoCoalescesTypingIntoWords() {
        val h = UndoHistory()
        var state = EditorSnapshot("", 0)
        var t = 0L
        fun type(c: Char) {
            val next = EditorSnapshot(state.text + c, state.selectionStart + 1)
            h.record(state, next, t)
            t += 100
            state = next
        }
        "wait 0".forEach(::type)
        // "wait", " ", "0" -> three undo steps
        state = h.undo(state)!!
        assertEquals("wait ", state.text)
        state = h.undo(state)!!
        assertEquals("wait", state.text)
        state = h.undo(state)!!
        assertEquals("", state.text)
        assertNull(h.undo(state))
        state = h.redo(state)!!
        assertEquals("wait", state.text)
        assertTrue(h.canRedo)
        // A new edit clears the redo stack.
        h.record(state, EditorSnapshot("waitX", 5), t + 5_000)
        assertFalse(h.canRedo)
    }

    @Test
    fun formatterOnlyChangesWhitespaceAndKeepsBytecode() {
        val messy = """
            {${'$'}CLEO .csa}
            0000: nop
                :MAIN
              while true
            wait 0
                   if and
            0@ > 1
                0@ < 10
                    then
            0@ += 1
                else
                        0@ = 0
                  end
            const
            A = 1
                end
            end
        """.trimIndent()
        val formatted = BlockStructure.format(messy)
        val expected = """
            {${'$'}CLEO .csa}
            0000: nop
            :MAIN
            while true
                wait 0
                if and
                    0@ > 1
                    0@ < 10
                then
                    0@ += 1
                else
                    0@ = 0
                end
                const
                    A = 1
                end
            end
        """.trimIndent()
        assertEquals(expected, formatted)
        assertEquals(formatted, BlockStructure.format(formatted), "formatting must be idempotent")
        val compiler = ScriptCompiler(db)
        assertContentEquals(compiler.compile(messy).bytes!!, compiler.compile(formatted).bytes!!)
        for (t in Templates.ALL) {
            val src = t.source("X")
            assertContentEquals(compiler.compile(src).bytes!!, compiler.compile(BlockStructure.format(src)).bytes!!, t.id)
        }
    }

    @Test
    fun autoIndentAndBlockMatching() {
        assertEquals("\n    ", AutoIndent.newlineInsertion("while true", 10))
        assertEquals("\n    ", AutoIndent.newlineInsertion("    wait 0", 10))
        assertEquals("\n        ", AutoIndent.newlineInsertion("    if 0@ > 1 then", 18))
        val text = "while true\n    wait 0\n    end"
        assertEquals("", AutoIndent.dedentFor(text, 2))
        assertNull(AutoIndent.dedentFor(text, 1))
        val ifText = "if\n    0@ > 1\nthen\n    wait 0\nelse\n    wait 1\nend"
        assertEquals(listOf(0, 2, 4, 6), BlockStructure.relatedLines(ifText, 4))
        assertEquals(listOf(0, 2, 4, 6), BlockStructure.relatedLines(ifText, 0))
    }

    @Test
    fun bracketsMatchOutsideStrings() {
        val text = "\$10(0@,10i) = '(' "
        assertEquals(3 to 10, BracketMatcher.match(text, 3))
        assertEquals(10 to 3, BracketMatcher.match(text, 11))
        assertNull(BracketMatcher.match(text, 15))
    }

    @Test
    fun searchAndReplace() {
        val text = "wait 0\nWAIT 10\nawaiting"
        assertEquals(3, SearchEngine.findAll(text, "wait").matches.size)
        assertEquals(2, SearchEngine.findAll(text, "wait", SearchOptions(wholeWord = true)).matches.size)
        assertEquals(1, SearchEngine.findAll(text, "wait", SearchOptions(caseSensitive = true, wholeWord = true)).matches.size)
        assertEquals(listOf(5..5, 12..13), SearchEngine.findAll(text, "\\d+", SearchOptions(regex = true)).matches)
        assertNotNull(SearchEngine.findAll(text, "(", SearchOptions(regex = true)).error)
        val (replaced, count) = SearchEngine.replaceAll(text, "wait", "pause", SearchOptions(wholeWord = true))
        assertEquals(2, count)
        assertEquals("pause 0\npause 10\nawaiting", replaced)
        assertEquals(1, SearchEngine.nextIndex(listOf(0..1, 10..11), 5))
        assertEquals(0, SearchEngine.nextIndex(listOf(0..1, 10..11), 50))
    }

    @Test
    fun completionUsesTheOpcodeDatabaseAndFile() {
        val engine = CompletionEngine(db)
        val text = ":START\nconst SPEED = 5\nint counter\nget_char_coo"
        val r = engine.complete(text, text.length)
        assertEquals("get_char_coo", r.prefix)
        val first = r.items.first()
        assertEquals(0x00A0, first.opcode)
        assertEquals("00A0: get_char_coordinates ", first.insertText)
        assertTrue(engine.complete(":START\njump @ST", 15).items.any { it.label == "@START" })
        assertTrue(engine.complete("0247: request_model #CHEE", 25).items.any { it.label == "#CHEETAH" })
        assertTrue(engine.complete("0@ = TouchPoints.Ri", 19).items.any { it.label == "TouchPoints.RightTop" })
        assertTrue(engine.complete("$text\nSPE", text.length + 4).items.any { it.label == "SPEED" })
        assertTrue(engine.complete("$text\ncou", text.length + 4).items.any { it.label == "counter" })
        assertEquals("0001: wait ", engine.complete("0001", 4).items.single().insertText)
    }

    @Test
    fun commandHelpReportsParameters() {
        val text = "00A0: get_char_coordinates \$PLAYER_ACTOR 1@ 2@"
        val help = assertNotNull(CommandHelpProvider.at(text, text.length, db))
        assertEquals(0x00A0, help.definition.id)
        assertEquals(3, help.writtenParams)
        assertTrue(help.statusText.startsWith("00A0: expecting 4 params | Stores a character's position"), help.statusText)
        assertEquals(2, help.paramIndex)
        val wait = assertNotNull(CommandHelpProvider.at("wait ", 5, db))
        assertEquals("0001: expecting 1 params | Pauses this script for the given number of milliseconds. Loops must wait to let the game run.", wait.statusText)
        assertEquals("time: int", wait.currentParamText)
        assertNull(CommandHelpProvider.at("// comment", 3, db))
    }

    @Test
    fun outlineAndLabels() {
        val text = "{\$CLEO .csi}\n:MAIN\nconst A = 1, B = 2\nint counter\n:END"
        val outline = Outline.of(text)
        assertEquals(listOf("{\$CLEO .csi}", "MAIN", "A", "B", "counter", "END"), outline.map { it.name })
        assertEquals(4, Outline.findLabel(text, "@end"))
        assertEquals(2, LineIndex(text).lineOf(text.indexOf("const")))
        assertEquals(0, LineIndex(text).columnOf(text.indexOf("const")))
    }

    @Test
    fun diffFindsMinimalChanges() {
        val a = "a\nb\nc\nd\ne"
        val b = "a\nc\nd\nX\ne\nf"
        val ops = TextDiff.diff(a, b).map { it.op.name.first() + it.text }
        assertEquals(listOf("Ea", "Db", "Ec", "Ed", "IX", "Ee", "If"), ops)
        val unified = TextDiff.unified(a, b, "old.txt", "new.txt", context = 1)
        assertTrue(unified.startsWith("--- old.txt\n+++ new.txt\n@@"), unified)
        assertTrue(unified.contains("-b") && unified.contains("+X") && unified.contains("+f"))
        assertEquals("", TextDiff.unified(a, a))
        // Reconstructing both sides from the diff must give the inputs back.
        val random = kotlin.random.Random(5)
        repeat(200) {
            val x = List(random.nextInt(0, 30)) { "l${random.nextInt(6)}" }
            val y = List(random.nextInt(0, 30)) { "l${random.nextInt(6)}" }
            val d = TextDiff.diffLines(x, y)
            assertEquals(x, d.filter { it.op != DiffOp.INSERT }.map { it.text })
            assertEquals(y, d.filter { it.op != DiffOp.DELETE }.map { it.text })
        }
    }
}
