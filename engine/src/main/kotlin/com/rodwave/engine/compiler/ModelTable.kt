package com.rodwave.engine.compiler

/**
 * Maps model names used as `#NAME` in scripts to model ids.
 *
 * The built-in table covers the standard San Andreas vehicle (400–611) and weapon models from the
 * game's `vehicles.ide` / `default.ide`. Import the IDE files from your own game data with
 * [IdeParser] for exact matching (including peds and objects).
 */
class ModelTable(entries: Map<String, Int>) {
    private val byName: Map<String, Int> = entries.mapKeys { it.key.uppercase() }
    private val byId: Map<Int, String> = byName.entries.groupBy({ it.value }, { it.key }).mapValues { it.value.first() }

    val size: Int get() = byName.size

    fun idOf(name: String): Int? = byName[name.uppercase()]
    fun nameOf(id: Int): String? = byId[id]

    fun mergedWith(other: ModelTable): ModelTable = ModelTable(byName + other.byName)

    companion object {
        val EMPTY = ModelTable(emptyMap())

        private val VEHICLES = """
            LANDSTAL BRAVURA BUFFALO LINERUN PEREN SENTINEL DUMPER FIRETRUK TRASH STRETCH MANANA INFERNUS VOODOO PONY MULE
            CHEETAH AMBULAN LEVIATHN MOONBEAM ESPERANT TAXI WASHING BOBCAT MRWHOOP BFINJECT HUNTER PREMIER ENFORCER SECURICA
            BANSHEE PREDATOR BUS RHINO BARRACKS HOTKNIFE ARTICT1 PREVION COACH CABBIE STALLION RUMPO RCBANDIT ROMERO PACKER
            MONSTER ADMIRAL SQUALO SEASPAR PIZZABOY TRAM ARTICT2 TURISMO SPEEDER REEFER TROPIC FLATBED YANKEE CADDY SOLAIR
            TOPFUN SKIMMER PCJ600 FAGGIO FREEWAY RCBARON RCRAIDER GLENDALE OCEANIC SANCHEZ SPARROW PATRIOT QUAD COASTG DINGHY
            HERMES SABRE RUSTLER ZR350 WALTON REGINA COMET BMX BURRITO CAMPER MARQUIS BAGGAGE DOZER MAVERICK VCNMAV RANCHER
            FBIRANCH VIRGO GREENWOO JETMAX HOTRING SANDKING BLISTAC POLMAV BOXVILLE BENSON MESA RCGOBLIN HOTRINA HOTRINB
            BLOODRA RNCHLURE SUPERGT ELEGANT JOURNEY BIKE MTBIKE BEAGLE CROPDUST STUNT PETRO RDTRAIN NEBULA MAJESTIC BUCCANEE
            SHAMAL HYDRA FCR900 NRG500 COPBIKE CEMENT TOWTRUCK FORTUNE CADRONA FBITRUCK WILLARD FORKLIFT TRACTOR COMBINE
            FELTZER REMINGTN SLAMVAN BLADE FREIGHT STREAK VORTEX VINCENT BULLET CLOVER SADLER FIRELA HUSTLER INTRUDER PRIMO
            CARGOBOB TAMPA SUNRISE MERIT UTILITY NEVADA YOSEMITE WINDSOR MONSTERA MONSTERB URANUS JESTER SULTAN STRATUM ELEGY
            RAINDANC RCTIGER FLASH TAHOMA SAVANNA BANDITO FREIFLAT STREAKC KART MOWER DUNERIDE SWEEPER BROADWAY TORNADO AT400
            DFT30 HUNTLEY STAFFORD BF400 NEWSVAN TUG PETROTR EMPEROR WAYFARER EUROS HOTDOG CLUB FREIBOX ARTICT3 ANDROM DODO
            RCCAM LAUNCH COPCARLA COPCARSF COPCARVG COPCARRU PICADOR SWATVAN ALPHA PHOENIX GLENSHIT SADLSHIT BAGBOXA BAGBOXB
            TUGSTAIR BOXBURG FARMTR1 UTILTR1
        """.trimIndent().split(Regex("\\s+")).filter { it.isNotBlank() }

        private val WEAPONS = mapOf(
            "GUN_DILDO1" to 321, "GUN_DILDO2" to 322, "GUN_VIBE1" to 323, "GUN_VIBE2" to 324, "FLOWERA" to 325,
            "GUN_CANE" to 326, "CELLPHONE" to 330, "BRASSKNUCKLE" to 331, "GOLFCLUB" to 333, "NITESTICK" to 334,
            "KNIFECUR" to 335, "BAT" to 336, "SHOVEL" to 337, "POOLCUE" to 338, "KATANA" to 339, "CHNSAW" to 341,
            "GRENADE" to 342, "TEARGAS" to 343, "MOLOTOV" to 344, "MISSILE" to 345, "COLT45" to 346, "SILENCED" to 347,
            "DESERT_EAGLE" to 348, "CHROMEGUN" to 349, "SAWNOFF" to 350, "SHOTGSPA" to 351, "MICRO_UZI" to 352,
            "MP5LNG" to 353, "FLARE" to 354, "AK47" to 355, "M4" to 356, "CUNTGUN" to 357, "SNIPER" to 358,
            "ROCKETLA" to 359, "HEATSEEK" to 360, "FLAME" to 361, "MINIGUN" to 362, "SATCHEL" to 363, "BOMB" to 364,
            "SPRAYCAN" to 365, "FIRE_EX" to 366, "CAMERA" to 367, "NVGOGGLES" to 368, "IRGOGGLES" to 369,
            "JETPACK" to 370, "GUN_PARA" to 371, "TEC9" to 372,
        )

        /** Standard San Andreas vehicle and weapon model names. */
        val SAN_ANDREAS: ModelTable by lazy {
            check(VEHICLES.size == 212) { "Vehicle table must list ids 400..611" }
            ModelTable(VEHICLES.mapIndexed { i, name -> name to 400 + i }.toMap() + WEAPONS)
        }
    }
}

/** Reads model definitions from GTA item definition (`.ide`) files. */
object IdeParser {
    private val MODEL_SECTIONS = setOf("objs", "tobj", "anim", "weap", "cars", "peds", "hier")

    fun parse(text: String): Map<String, Int> {
        val result = LinkedHashMap<String, Int>()
        var section: String? = null
        for (raw in text.lineSequence()) {
            val line = raw.substringBefore('#').trim()
            if (line.isEmpty()) continue
            val lower = line.lowercase()
            when {
                section == null && lower in MODEL_SECTIONS + setOf("path", "2dfx", "txdp", "inst") -> section = lower
                section != null && lower == "end" -> section = null
                section in MODEL_SECTIONS -> {
                    val fields = line.split(',').map { it.trim() }
                    val id = fields.getOrNull(0)?.toIntOrNull()
                    val name = fields.getOrNull(1)
                    if (id != null && !name.isNullOrBlank() && name.all { it.isLetterOrDigit() || it == '_' }) {
                        result.putIfAbsent(name.uppercase(), id)
                    }
                }
            }
        }
        return result
    }
}
