package com.rodwave.engine.compat

/** Minimal INI reader: `[section]`, `key = value`, `;` and `#` comments. Keys are case-insensitive. */
class IniFile(private val sections: Map<String, Map<String, String>>) {
    fun get(key: String, section: String? = null): String? {
        if (section != null) return sections[section.lowercase()]?.get(key.lowercase())
        return sections.values.firstNotNullOfOrNull { it[key.lowercase()] }
    }

    val sectionNames: Set<String> get() = sections.keys

    companion object {
        fun parse(text: String): IniFile {
            val result = LinkedHashMap<String, LinkedHashMap<String, String>>()
            var current = ""
            for (raw in text.lineSequence()) {
                val line = raw.trim()
                if (line.isEmpty() || line.startsWith(";") || line.startsWith("#")) continue
                if (line.startsWith("[") && line.endsWith("]")) {
                    current = line.substring(1, line.length - 1).trim().lowercase()
                    continue
                }
                val eq = line.indexOf('=')
                if (eq <= 0) continue
                result.getOrPut(current) { LinkedHashMap() }[line.substring(0, eq).trim().lowercase()] = line.substring(eq + 1).trim()
            }
            return IniFile(result)
        }
    }
}
