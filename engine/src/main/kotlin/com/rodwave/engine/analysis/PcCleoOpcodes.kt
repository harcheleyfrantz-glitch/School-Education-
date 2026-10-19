package com.rodwave.engine.analysis

import com.rodwave.engine.opcode.CoreOpcodes
import com.rodwave.engine.opcode.DatabaseInfo
import com.rodwave.engine.opcode.DatabaseOrigin
import com.rodwave.engine.opcode.OpcodeDatabase
import com.rodwave.engine.opcode.OpcodeDefinition

/**
 * Windows CLEO 4 commands (0A8C–0AEF), used only to recognise PC scripts that need porting.
 * Signatures verified against the Sanny Builder Library `sa` table (CLEO extension, v0.517).
 */
object PcCleoOpcodes {
    private val SIGNATURES = listOf(
        "0A8C WRITE_MEMORY address:int size:int value:any vp:bool",
        "0A8D READ_MEMORY address:int size:int vp:bool -> result:any@v",
        "0A8E INT_ADD a:int b:int -> result:int@v",
        "0A8F INT_SUB a:int b:int -> result:int@v",
        "0A90 INT_MUL a:int b:int -> result:int@v",
        "0A91 INT_DIV a:int b:int -> result:int@v",
        "0A92 STREAM_CUSTOM_SCRIPT scriptFileName:string args:arguments",
        "!0A93 TERMINATE_THIS_CUSTOM_SCRIPT",
        "0A94 LOAD_AND_LAUNCH_CUSTOM_MISSION scriptFileName:string args:arguments",
        "0A95 SAVE_THIS_CUSTOM_SCRIPT",
        "0A96 GET_PED_POINTER char:Char -> address:int@v",
        "0A97 GET_VEHICLE_POINTER handle:Car -> address:int@v",
        "0A98 GET_OBJECT_POINTER handle:Object -> address:int@v",
        "0A99 SET_CURRENT_DIRECTORY path:any",
        "?0A9A OPEN_FILE filePathName:string mode:FileMode -> handle:File@v",
        "0A9B CLOSE_FILE self:File",
        "0A9C GET_FILE_SIZE self:File -> size:int@v",
        "0A9D READ_FROM_FILE self:File size:int -> destination:int@v",
        "0A9E WRITE_TO_FILE self:File size:int source:int@v",
        "0A9F GET_THIS_SCRIPT_STRUCT -> address:int@v",
        "!0AA0 GOSUB_IF_FALSE label",
        "!0AA1 RETURN_IF_FALSE",
        "?0AA2 LOAD_DYNAMIC_LIBRARY fileName:string -> handle:DynamicLibrary@v",
        "0AA3 FREE_DYNAMIC_LIBRARY self:DynamicLibrary",
        "?0AA4 GET_DYNAMIC_LIBRARY_PROCEDURE procName:string self:DynamicLibrary -> address:int@v",
        "0AA5 CALL_FUNCTION address:int numArgs:int pop:int args:arguments",
        "0AA6 CALL_METHOD address:int struct:int numArgs:int pop:int args:arguments",
        "0AA7 CALL_FUNCTION_RETURN address:int numArgs:int pop:int args:arguments -> funcRet:any@v",
        "0AA8 CALL_METHOD_RETURN address:int struct:int numArgs:int pop:int args:arguments -> funcRet:any@v",
        "?0AA9 IS_GAME_VERSION_ORIGINAL",
        "0AAA GET_SCRIPT_STRUCT_NAMED scriptName:string -> address:int@v",
        "?0AAB DOES_FILE_EXIST path:string",
        "?0AB0 IS_KEY_PRESSED keyCode:KeyCode",
        "0AB1 CLEO_CALL label numArgs:int args:arguments",
        "0AB2 CLEO_RETURN numRet:int retParams:arguments",
        "0AB3 SET_CLEO_SHARED_VAR index:int value:any",
        "0AB4 GET_CLEO_SHARED_VAR index:int -> result:any@v",
        "0AB5 STORE_CLOSEST_ENTITIES self:Char -> carHandle:Car@v charHandle:Char@v",
        "?0AB6 GET_TARGET_BLIP_COORDS -> x:float@v y:float@v z:float@v",
        "0AB7 GET_CAR_NUMBER_OF_GEARS self:Car -> numGear:int@v",
        "0AB8 GET_CAR_CURRENT_GEAR self:Car -> gear:int@v",
        "0ABA TERMINATE_ALL_CUSTOM_SCRIPTS_WITH_THIS_NAME name:string",
        "?0ABD IS_CAR_SIREN_ON self:Car",
        "?0ABE IS_CAR_ENGINE_ON self:Car",
        "0ABF CLEO_SET_CAR_ENGINE_ON self:Car state:bool",
        "0AC6 GET_LABEL_POINTER label -> address:int@v",
        "0AC7 GET_VAR_POINTER var:any@v -> address:int@v",
        "?0AC8 ALLOCATE_MEMORY size:int -> address:int@v",
        "0AC9 FREE_MEMORY address:int",
        "0ACA PRINT_HELP_STRING text:string",
        "0ACB PRINT_BIG_STRING text:string time:int style:TextStyle",
        "0ACC PRINT_STRING text:string time:int",
        "0ACD PRINT_STRING_NOW text:string time:int",
        "0ACE PRINT_HELP_FORMATTED text:string args:arguments",
        "0ACF PRINT_BIG_FORMATTED format:string time:int style:TextStyle args:arguments",
        "0AD0 PRINT_FORMATTED format:string time:int args:arguments",
        "0AD1 PRINT_FORMATTED_NOW format:string time:int args:arguments",
        "?0AD2 GET_CHAR_PLAYER_IS_TARGETING self:Player -> handle:Char@v",
        "0AD3 STRING_FORMAT result:string format:string args:arguments",
        "?0AD4 SCAN_STRING string:string format:string -> nValues:int@v values:arguments@v",
        "?0AD5 FILE_SEEK self:File offset:int origin:SeekOrigin",
        "?0AD6 IS_END_OF_FILE_REACHED self:File",
        "?0AD7 READ_STRING_FROM_FILE self:File storeTo:string maxLength:int",
        "?0AD8 WRITE_STRING_TO_FILE self:File source:string",
        "0AD9 WRITE_FORMATTED_STRING_TO_FILE self:File format:string args:arguments",
        "?0ADA SCAN_FILE self:File format:string -> nValues:int@v values:arguments@v",
        "0ADB GET_NAME_OF_VEHICLE_MODEL modelId:model_vehicle -> carName:string@v",
        "?0ADC TEST_CHEAT input:string",
        "0ADD SPAWN_VEHICLE_BY_CHEATING modelId:model_vehicle",
        "0ADE GET_TEXT_LABEL_STRING key:gxt_key -> text:string@v",
        "0ADF ADD_TEXT_LABEL dynamicKey:gxt_key text:string",
        "0AE0 REMOVE_TEXT_LABEL key:gxt_key",
        "?0AE1 GET_RANDOM_CHAR_IN_SPHERE_NO_SAVE_RECURSIVE x:float y:float z:float radius:float findNext:bool filter:CharSearchFilter -> handle:Char@v",
        "?0AE2 GET_RANDOM_CAR_IN_SPHERE_NO_SAVE_RECURSIVE x:float y:float z:float radius:float findNext:bool skipWrecked:bool -> handle:Car@v",
        "?0AE3 GET_RANDOM_OBJECT_IN_SPHERE_NO_SAVE_RECURSIVE x:float y:float z:float radius:float findNext:bool -> handle:Object@v",
        "?0AE4 DOES_DIRECTORY_EXIST path:string",
        "?0AE5 CREATE_DIRECTORY path:string",
        "?0AE6 FIND_FIRST_FILE searchMask:string -> handle:FindFile@v fileName:string@v",
        "?0AE7 FIND_NEXT_FILE self:FindFile -> fileName:string@v",
        "0AE8 FIND_CLOSE self:FindFile",
        "0AE9 POP_FLOAT -> number:float@v",
        "0AEA GET_PED_REF address:int -> handle:Char@v",
        "0AEB GET_VEHICLE_REF address:int -> handle:Car@v",
        "0AEC GET_OBJECT_REF address:int -> handle:Object@v",
        "0AED STRING_FLOAT_FORMAT number:float format:string -> text:string@v",
        "0AEE POW number:float power:float -> result:float@v",
        "0AEF LOG number:float base:float -> result:float@v",
    )

    val definitions: List<OpcodeDefinition> by lazy {
        SIGNATURES.map { CoreOpcodes.parse(it).copy(description = "Windows CLEO 4 command (not available in CLEO Android)", extension = "PC CLEO") }
    }

    val ids: Set<Int> by lazy { definitions.map { it.id }.toSet() }

    fun name(id: Int): String? = definitions.firstOrNull { it.id == id }?.name

    /** Mobile ids that are native commands on mobile but PC CLEO commands on Windows. */
    val COLLIDING_IDS = 0x0A8C..0x0A90

    /**
     * An approximation of the PC game's table: the mobile definitions below the point where the
     * two games diverge (0A4E), plus the PC CLEO commands. Used to test whether a script decodes
     * better as a PC script.
     */
    fun pcView(mobile: OpcodeDatabase): OpcodeDatabase {
        val base = mobile.all.filter { it.id < 0x0A4E }
        return OpcodeDatabase(
            DatabaseInfo("PC view (SA + CLEO 4)", "1", DatabaseOrigin.BUILT_IN, "sa"),
            base + definitions,
            mobile.enums,
        )
    }
}
