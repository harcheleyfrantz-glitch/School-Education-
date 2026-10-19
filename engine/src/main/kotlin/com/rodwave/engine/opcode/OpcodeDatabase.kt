package com.rodwave.engine.opcode

/** Where an opcode database came from. */
enum class DatabaseOrigin(val label: String) {
    BUILT_IN("Built-in core set"),
    SANNY_BUILDER_LIBRARY("Sanny Builder Library"),
    MERGED("Built-in + imported library"),
}

data class DatabaseInfo(
    val name: String,
    val version: String,
    val origin: DatabaseOrigin,
    /** Game identifier from the library (e.g. `sa_mobile`). */
    val game: String,
    val sourceUrl: String? = null,
    /** Non-fatal problems found while importing. */
    val importWarnings: List<String> = emptyList(),
)

/** Named integer constants, e.g. `WeaponType.Pistol = 22`. */
data class EnumDefinition(val name: String, val members: Map<String, Int>)

/**
 * Opcode definitions for one game target.
 *
 * Lookups by name are case-insensitive. Several opcodes may share a name (overloads); callers that
 * need a unique instruction must then use the numeric opcode form.
 */
class OpcodeDatabase(
    val info: DatabaseInfo,
    definitions: Collection<OpcodeDefinition>,
    enums: Collection<EnumDefinition> = emptyList(),
) {
    private val byId: Map<Int, OpcodeDefinition> = definitions.associateBy { it.id }
    private val byName: Map<String, List<OpcodeDefinition>> =
        byId.values.groupBy { it.name.lowercase() }.mapValues { (_, list) -> list.sortedBy { it.id } }
    private val byMember: Map<String, List<OpcodeDefinition>> =
        byId.values.filter { it.className != null && it.member != null }
            .groupBy { "${it.className}.${it.member}".lowercase() }
    private val enumsByName: Map<String, EnumDefinition> = enums.associateBy { it.name.lowercase() }

    val size: Int get() = byId.size
    val all: List<OpcodeDefinition> get() = byId.values.sortedBy { it.id }
    val enums: List<EnumDefinition> get() = enumsByName.values.sortedBy { it.name }
    val extensions: List<String> get() = byId.values.map { it.extension }.distinct().sorted()
    val classes: List<String> get() = byId.values.mapNotNull { it.className }.distinct().sorted()

    operator fun get(id: Int): OpcodeDefinition? = byId[id]
    operator fun contains(id: Int): Boolean = id in byId

    fun findByName(name: String): List<OpcodeDefinition> = byName[name.lowercase()].orEmpty()

    /** `Char.SetHealth` style lookup. */
    fun findByMember(className: String, member: String): List<OpcodeDefinition> =
        byMember["$className.$member".lowercase()].orEmpty()

    fun enum(name: String): EnumDefinition? = enumsByName[name.lowercase()]

    /** Resolves `Enum.Member` to its integer value. */
    fun enumValue(enumName: String, member: String): Int? =
        enum(enumName)?.members?.entries?.firstOrNull { it.key.equals(member, ignoreCase = true) }?.value

    /** Math/comparison commands with the given operator symbol. */
    fun withOperator(operator: String): List<OpcodeDefinition> =
        byId.values.filter { it.operator == operator && !it.isUnsupported }.sortedBy { it.id }

    /**
     * Ranked search over hex id, keyword, class/member and description.
     * Exact id and name matches come first, then prefix matches, then substring matches.
     */
    fun search(
        query: String,
        limit: Int = Int.MAX_VALUE,
        extension: String? = null,
        className: String? = null,
        includeUnsupported: Boolean = true,
        conditionsOnly: Boolean = false,
    ): List<OpcodeDefinition> {
        val q = query.trim().lowercase()
        val candidates = byId.values.asSequence()
            .filter { extension == null || it.extension.equals(extension, ignoreCase = true) }
            .filter { className == null || it.className.equals(className, ignoreCase = true) }
            .filter { includeUnsupported || !it.isUnsupported }
            .filter { !conditionsOnly || it.isCondition }
        if (q.isEmpty()) return candidates.sortedBy { it.id }.take(limit).toList()
        val hexQuery = q.removePrefix("0x").removeSuffix(":")
        return candidates
            .mapNotNull { def -> score(def, q, hexQuery)?.let { def to it } }
            .sortedWith(compareBy({ -it.second }, { it.first.id }))
            .take(limit)
            .map { it.first }
            .toList()
    }

    private fun score(def: OpcodeDefinition, q: String, hexQuery: String): Int? {
        val hex = def.hexId.lowercase()
        val name = def.name.lowercase()
        val member = listOfNotNull(def.className, def.member).joinToString(".").lowercase()
        return when {
            hex == hexQuery.padStart(4, '0') && hexQuery.all { it.isDigit() || it in 'a'..'f' } -> 1000
            name == q || name == q.replace(' ', '_') -> 900
            member == q -> 850
            hex.startsWith(hexQuery) && hexQuery.length >= 2 && hexQuery.all { it.isDigit() || it in 'a'..'f' } -> 700
            name.startsWith(q.replace(' ', '_')) -> 600
            member.isNotEmpty() && member.contains(q) -> 450
            name.contains(q.replace(' ', '_')) -> 400
            q.split(' ', '_').filter { it.isNotEmpty() }.let { parts -> parts.size > 1 && parts.all { name.contains(it) } } -> 300
            def.description.lowercase().contains(q) -> 100
            else -> null
        }
    }

    /** Returns a database where [other]'s definitions replace or extend these. */
    fun mergedWith(other: OpcodeDatabase): OpcodeDatabase {
        val merged = LinkedHashMap<Int, OpcodeDefinition>()
        all.forEach { merged[it.id] = it }
        other.all.forEach { incoming ->
            val existing = merged[incoming.id]
            // Keep our hand-written description when the import has none.
            merged[incoming.id] = if (existing != null && incoming.description.isBlank()) {
                incoming.copy(description = existing.description)
            } else {
                incoming
            }
        }
        val enumMap = LinkedHashMap<String, EnumDefinition>()
        enums.forEach { enumMap[it.name.lowercase()] = it }
        other.enums.forEach { enumMap[it.name.lowercase()] = it }
        return OpcodeDatabase(
            DatabaseInfo(
                name = "${info.name} + ${other.info.name}",
                version = other.info.version,
                origin = DatabaseOrigin.MERGED,
                game = other.info.game,
                sourceUrl = other.info.sourceUrl,
                importWarnings = other.info.importWarnings,
            ),
            merged.values,
            enumMap.values,
        )
    }
}
