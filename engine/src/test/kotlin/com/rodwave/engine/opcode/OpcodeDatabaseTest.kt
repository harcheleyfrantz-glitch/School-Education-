package com.rodwave.engine.opcode

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class OpcodeDatabaseTest {

    private val sample = """
        {
          "meta": { "version": "9.9", "url": "https://library.sannybuilder.com/#/sa_mobile" },
          "extensions": [
            { "name": "default", "commands": [
              { "id": "0001", "name": "WAIT", "num_params": 1, "input": [{ "name": "time", "type": "int" }], "short_desc": "Waits" },
              { "id": "0256", "name": "IS_PLAYER_PLAYING", "num_params": 1, "input": [{ "name": "self", "type": "Player" }],
                "attrs": { "is_condition": true }, "class": "Player", "member": "IsPlaying" },
              { "id": "0006", "name": "SET_LVAR_INT", "num_params": 2, "operator": "=",
                "input": [{ "name": "", "type": "int", "source": "var_local" }, { "name": "", "type": "int", "source": "literal" }] },
              { "id": "00A0", "name": "GET_CHAR_COORDINATES", "num_params": 4, "input": [{ "name": "self", "type": "Char" }],
                "output": [{ "name": "x", "type": "float", "source": "var_any" }, { "name": "y", "type": "float", "source": "var_any" }, { "name": "z", "type": "float", "source": "var_any" }] },
              { "id": "0F00", "name": "BROKEN", "num_params": 3, "input": [{ "name": "a", "type": "int" }] },
              { "id": "ZZZZ", "name": "BAD_ID", "num_params": 0 },
              { "id": "0A00", "name": "NO_PARAM_INFO", "num_params": 2 },
              { "id": "00E1", "name": "IS_BUTTON_PRESSED", "num_params": 2, "input": [{ "name": "pad", "type": "PadId" }, { "name": "button", "type": "Button" }] }
            ]},
            { "name": "CLEO", "commands": [
              { "id": "00E1", "name": "IS_BUTTON_PRESSED", "num_params": 2, "input": [{ "name": "touch", "type": "PadId" }, { "name": "touchPoints", "type": "TouchPoints" }] },
              { "id": "0DD5", "name": "GET_PLATFORM", "num_params": 1, "output": [{ "name": "platform", "type": "Platform", "source": "var_any" }] }
            ]}
          ],
          "classes": []
        }
    """.trimIndent()

    @Test
    fun importsLibraryFormat() {
        val enums = """{ "Platform": { "None": null, "Android": null, "PSP": null }, "Odd": { "A": "x" }, "Fade": { "Out": 0, "In": 1 } }"""
        val db = SannyLibraryImporter.parse(sample, enums)
        assertEquals("sa_mobile", db.info.game)
        assertEquals("9.9", db.info.version)
        assertEquals(DatabaseOrigin.SANNY_BUILDER_LIBRARY, db.info.origin)
        val wait = assertNotNull(db[0x0001])
        assertEquals("Waits", wait.description)
        assertEquals(ParamType.INT, wait.params.single().type)
        val coords = assertNotNull(db[0x00A0])
        assertEquals(listOf(false, true, true, true), coords.params.map { it.isOutput })
        assertTrue(db[0x0256]!!.isCondition)
        assertEquals("=", db[0x0006]!!.operator)
        assertEquals(ParamSource.VAR_LOCAL, db[0x0006]!!.params[0].source)
        // Malformed entries are skipped with warnings, unknown params become "any".
        assertEquals(null, db[0x0F00])
        assertEquals(2, db[0x0A00]!!.params.size)
        assertTrue(db.info.importWarnings.any { it.contains("BROKEN") })
        assertTrue(db.info.importWarnings.any { it.contains("ZZZZ") })
        // The CLEO extension redefines 00E1.
        assertEquals("CLEO", db[0x00E1]!!.extension)
        assertTrue(db.info.importWarnings.any { it.contains("00E1") })
        // Enums: nulls count up from 0; string enums are skipped.
        assertEquals(1, db.enumValue("Platform", "Android"))
        assertEquals(1, db.enumValue("fade", "in"))
        assertEquals(null, db.enum("Odd"))
        // Lookups
        assertEquals(listOf(0x0256), db.findByMember("Player", "IsPlaying").map { it.id })
        assertEquals(0x0001, db.search("wait").first().id)
        assertEquals(0x0256, db.search("0256").first().id)
    }

    @Test
    fun rejectsFilesThatAreNotLibraries() {
        assertFailsWith<LibraryImportException> { SannyLibraryImporter.parse("not json") }
        assertFailsWith<LibraryImportException> { SannyLibraryImporter.parse("{\"foo\": 1}") }
        assertFailsWith<LibraryImportException> { SannyLibraryImporter.parse("{\"extensions\": []}") }
        assertFailsWith<LibraryImportException> { SannyLibraryImporter.parse("[1,2,3]") }
    }

    @Test
    fun mergeKeepsBuiltInDescriptions() {
        val imported = SannyLibraryImporter.parse(sample.replace("\"short_desc\": \"Waits\"", "\"short_desc\": \"\""))
        val merged = CoreOpcodes.database.mergedWith(imported)
        assertEquals(DatabaseOrigin.MERGED, merged.info.origin)
        assertEquals(CoreOpcodes.database[0x0001]!!.description, merged[0x0001]!!.description)
        assertTrue(merged.size >= CoreOpcodes.database.size)
    }

    @Test
    fun coreSetIsConsistent() {
        val db = CoreOpcodes.database
        assertTrue(db.size > 300, "core set has ${db.size} opcodes")
        // Every math operator command has exactly two parameters and a description.
        db.all.filter { it.operator != null }.forEach {
            assertEquals(2, it.params.size, it.hexId)
            assertTrue(it.description.isNotBlank(), it.hexId)
        }
        db.all.forEach { assertTrue(it.description.isNotBlank(), "missing description for ${it.hexId}") }
        assertEquals(5, db.enumValue("TouchPoints", "Center"))
        assertEquals(17, db.enumValue("GameVerInternal", "VER_GTASA_2_00_OR_HIGHER"))
        assertEquals("0001: wait {time: int}", db[1]!!.signature)
    }

    /**
     * Maintainer check: verifies the built-in core set against a Sanny Builder Library file.
     * Run with RODWAVE_SBL_JSON=/path/to/sa_mobile.json; skipped otherwise.
     */
    @Test
    fun coreSetMatchesSannyBuilderLibrary() {
        val path = System.getenv("RODWAVE_SBL_JSON") ?: return
        val library = SannyLibraryImporter.parse(File(path).readText())
        val mismatches = mutableListOf<String>()
        for (core in CoreOpcodes.database.all) {
            val lib = library[core.id]
            if (lib == null) {
                mismatches += "${core.hexId} missing from library"
                continue
            }
            if (lib.name != core.name) mismatches += "${core.hexId} name ${core.name} != ${lib.name}"
            if (lib.params.size != core.params.size) {
                mismatches += "${core.hexId} param count ${core.params.size} != ${lib.params.size}"
                continue
            }
            core.params.zip(lib.params).forEachIndexed { i, (c, l) ->
                if (c.typeName != l.typeName) mismatches += "${core.hexId} param $i type ${c.typeName} != ${l.typeName}"
                if (c.isOutput != l.isOutput) mismatches += "${core.hexId} param $i output ${c.isOutput} != ${l.isOutput}"
                // The library marks the LVAR variant of 04B5 as var_global; Rodwave uses var_local.
                if (c.source != l.source && core.id != 0x04B5) mismatches += "${core.hexId} param $i source ${c.source} != ${l.source}"
            }
            if (lib.isCondition != core.isCondition) mismatches += "${core.hexId} condition ${core.isCondition} != ${lib.isCondition}"
            if ((lib.operator ?: "") != (core.operator ?: "")) mismatches += "${core.hexId} operator ${core.operator} != ${lib.operator}"
        }
        assertTrue(mismatches.isEmpty(), "Core set differs from ${library.info.name} ${library.info.version}:\n" + mismatches.joinToString("\n"))
        println("Verified ${CoreOpcodes.database.size} core opcodes against ${library.info.name} ${library.info.version}")
    }
}
