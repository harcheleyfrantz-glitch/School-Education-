package com.rodwave.engine.opcode

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class LibraryImportException(message: String, cause: Throwable? = null) : Exception(message, cause)

/**
 * Reads opcode definitions published by the Sanny Builder Library
 * (https://github.com/sannybuilder/library), e.g. `sa_mobile/sa_mobile.json` and `sa_mobile/enums.json`.
 *
 * Rodwave does not redistribute these files: the user imports a copy or downloads it from the
 * official repository on request. Malformed entries are skipped and reported as warnings.
 */
object SannyLibraryImporter {
    const val MAX_LIBRARY_BYTES = 32 * 1024 * 1024

    /** Official location of the GTA SA Mobile definitions. */
    const val SA_MOBILE_JSON_URL = "https://raw.githubusercontent.com/sannybuilder/library/master/sa_mobile/sa_mobile.json"
    const val SA_MOBILE_ENUMS_URL = "https://raw.githubusercontent.com/sannybuilder/library/master/sa_mobile/enums.json"

    private val json = Json { ignoreUnknownKeys = true; isLenient = false }

    fun parse(commandsJson: String, enumsJson: String? = null): OpcodeDatabase {
        if (commandsJson.length > MAX_LIBRARY_BYTES) throw LibraryImportException("Library file is larger than 32 MB")
        val root = try {
            json.parseToJsonElement(commandsJson)
        } catch (e: Exception) {
            throw LibraryImportException("Not valid JSON: ${e.message}", e)
        }
        if (root !is JsonObject) throw LibraryImportException("Expected a JSON object at the top level")
        val extensions = root["extensions"] as? JsonArray
            ?: throw LibraryImportException("Missing \"extensions\" array: this is not a Sanny Builder Library commands file")

        val warnings = mutableListOf<String>()
        val definitions = LinkedHashMap<Int, OpcodeDefinition>()
        for (extElement in extensions) {
            val ext = extElement as? JsonObject ?: continue
            val extName = ext.string("name") ?: OpcodeDefinition.EXTENSION_DEFAULT
            val commands = ext["commands"] as? JsonArray ?: continue
            for (cmdElement in commands) {
                val cmd = cmdElement as? JsonObject ?: continue
                val def = try {
                    parseCommand(cmd, extName)
                } catch (e: Exception) {
                    warnings += "Skipped ${cmd.string("id") ?: "?"} ${cmd.string("name") ?: ""}: ${e.message}"
                    null
                } ?: continue
                definitions[def.id]?.let { previous ->
                    if (previous.extension != def.extension) {
                        warnings += "${def.hexId} ${previous.name} (${previous.extension}) is redefined by extension ${def.extension} as ${def.name}"
                    }
                }
                definitions[def.id] = def
            }
        }
        if (definitions.isEmpty()) throw LibraryImportException("The file contains no command definitions")

        val meta = root["meta"] as? JsonObject
        val url = meta?.string("url")
        val game = url?.substringAfterLast("#/", "")?.substringBefore('/')?.takeIf { it.isNotBlank() } ?: "unknown"
        val enums = enumsJson?.let { parseEnums(it, warnings) }.orEmpty()

        return OpcodeDatabase(
            DatabaseInfo(
                name = "Sanny Builder Library ($game)",
                version = meta?.string("version") ?: "unknown",
                origin = DatabaseOrigin.SANNY_BUILDER_LIBRARY,
                game = game,
                sourceUrl = url,
                importWarnings = warnings,
            ),
            definitions.values,
            enums,
        )
    }

    private fun parseCommand(cmd: JsonObject, extension: String): OpcodeDefinition {
        val idText = cmd.string("id") ?: throw IllegalArgumentException("missing id")
        val id = idText.toIntOrNull(16)?.takeIf { it in 0..0x7FFF } ?: throw IllegalArgumentException("invalid id '$idText'")
        val name = cmd.string("name")?.takeIf { it.isNotBlank() } ?: throw IllegalArgumentException("missing name")
        val numParams = cmd["num_params"]?.jsonPrimitive?.intOrNull ?: 0
        val inputs = (cmd["input"] as? JsonArray).orEmpty().map { parseParam(it, isOutput = false) }
        val outputs = (cmd["output"] as? JsonArray).orEmpty().map { parseParam(it, isOutput = true) }
        var params = inputs + outputs
        if (params.size != numParams) {
            if (params.isEmpty() && numParams in 1..64) {
                // Parameter details unknown: decode by type tag only.
                params = (1..numParams).map { ParamDefinition("p$it", "any") }
            } else {
                throw IllegalArgumentException("num_params is $numParams but ${params.size} parameters are listed")
            }
        }
        val attrs = cmd["attrs"] as? JsonObject
        fun attr(key: String) = attrs?.get(key)?.jsonPrimitive?.booleanOrNull == true
        return OpcodeDefinition(
            id = id,
            name = name,
            params = params,
            description = cmd.string("short_desc").orEmpty(),
            extension = extension,
            className = cmd.string("class"),
            member = cmd.string("member"),
            operator = cmd.string("operator"),
            isCondition = attr("is_condition"),
            isBranch = attr("is_branch"),
            isSegment = attr("is_segment"),
            isNop = attr("is_nop"),
            isUnsupported = attr("is_unsupported"),
            isConstructor = attr("is_constructor"),
            isDestructor = attr("is_destructor"),
            isStatic = attr("is_static"),
            isOverload = attr("is_overload"),
            platforms = (cmd["platforms"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.content },
        )
    }

    private fun parseParam(element: JsonElement, isOutput: Boolean): ParamDefinition {
        val obj = element as? JsonObject ?: throw IllegalArgumentException("parameter is not an object")
        val type = obj.string("type") ?: throw IllegalArgumentException("parameter without type")
        return ParamDefinition(
            name = obj.string("name").orEmpty(),
            typeName = type,
            source = ParamSource.fromLibrary(obj.string("source")),
            isOutput = isOutput,
        )
    }

    /**
     * Enum file format: `{ "WeaponType": { "Pistol": 22, ... } }`. A null value continues counting
     * from the previous member (starting at 0), like a C enum. String-valued enums are skipped.
     */
    fun parseEnums(enumsJson: String, warnings: MutableList<String> = mutableListOf()): List<EnumDefinition> {
        val root = try {
            json.parseToJsonElement(enumsJson).jsonObject
        } catch (e: Exception) {
            throw LibraryImportException("Enums file is not a JSON object: ${e.message}", e)
        }
        val result = mutableListOf<EnumDefinition>()
        var skipped = 0
        for ((enumName, value) in root) {
            val members = value as? JsonObject ?: continue
            val map = LinkedHashMap<String, Int>()
            var next = 0
            var valid = true
            for ((memberName, memberValue) in members) {
                when {
                    memberValue is JsonNull -> {
                        map[memberName] = next
                        next++
                    }
                    memberValue is JsonPrimitive && memberValue.intOrNull != null -> {
                        val v = memberValue.intOrNull!!
                        map[memberName] = v
                        next = v + 1
                    }
                    else -> valid = false
                }
            }
            if (valid) result += EnumDefinition(enumName, map) else skipped++
        }
        if (skipped > 0) warnings += "$skipped enum(s) with non-integer values were skipped"
        return result
    }

    private fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

    private fun JsonArray?.orEmpty(): List<JsonElement> = this ?: emptyList()
}
