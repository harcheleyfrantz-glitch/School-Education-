package com.rodwave.engine.opcode

/**
 * Built-in core opcode set for GTA San Andreas Mobile (CLEO Android targets).
 *
 * This is a curated subset: control flow, variable math, frequently used game commands, the
 * mobile-only widget/touch commands and the CLEO Android extension. Opcode numbers and parameter
 * signatures are factual properties of the game's bytecode; they were verified against Sanny
 * Builder Library v0.517 (`sa_mobile`) — see `CoreOpcodesVerificationTest`. Descriptions are
 * Rodwave's own. Import the full library for complete coverage (2,700+ commands).
 *
 * Signature notation: `[?][!]XXXX NAME param... [-> output...]`, where `?` marks a condition,
 * `!` a branch, and a parameter is `name:type[@g|@l|@v|@c]` (global var, local var, any var, literal).
 */
object CoreOpcodes {
    const val VERSION = "1.0"

    val database: OpcodeDatabase by lazy {
        val defs = buildList {
            addAll(control())
            addAll(math())
            addAll(game())
            addAll(mobile())
            addAll(cleoAndroid())
        }
        OpcodeDatabase(
            DatabaseInfo(
                name = "Rodwave core set (SA Mobile)",
                version = VERSION,
                origin = DatabaseOrigin.BUILT_IN,
                game = "sa_mobile",
            ),
            defs,
            enums(),
        )
    }

    private fun control() = listOf(
        def("0000 NOP", "Does nothing. Useful as padding, e.g. so a CLEO script does not start with a label."),
        def("0001 WAIT time:int", "Pauses this script for the given number of milliseconds. Loops must wait to let the game run."),
        def("!0002 GOTO label", "Jumps unconditionally to a label.", segment = true),
        def("!004D GOTO_IF_FALSE label", "Jumps to a label when the result of the preceding condition block is false."),
        def("!004E TERMINATE_THIS_SCRIPT", "Ends the current script. CLEO Android scripts end with this command."),
        def("004F START_NEW_SCRIPT label arguments", "Starts a new script thread at a label, optionally passing values into its first local variables."),
        def("0050 GOSUB label", "Calls a subroutine at a label; it returns with 0051."),
        def("0051 RETURN", "Returns from a subroutine entered with 0050."),
        def("00D6 IF int", "Starts a condition block: 0 = one condition, 1..7 = AND of 2..8 conditions, 21..27 = OR of 2..8 conditions."),
        def("03A4 SCRIPT_NAME name:string", "Gives the current script a name (up to 7 characters)."),
        def("0417 LOAD_AND_LAUNCH_MISSION_INTERNAL index:int", "Starts a mission listed in the main.scm header by its index."),
        def("0459 TERMINATE_ALL_SCRIPTS_WITH_THIS_NAME name:string", "Ends every running script with the given name."),
        def("00D8 MISSION_HAS_FINISHED", "Tells the game that the current mission has ended."),
    )

    private fun math(): List<OpcodeDefinition> {
        val rows = listOf(
            "0004 SET_VAR_INT var:int@g value:int@c" to "=",
            "0005 SET_VAR_FLOAT var:float@g value:float@c" to "=",
            "0006 SET_LVAR_INT var:int@l value:int@c" to "=",
            "0007 SET_LVAR_FLOAT var:float@l value:float@c" to "=",
            "0008 ADD_VAL_TO_INT_VAR var:int@g value:int@c" to "+",
            "0009 ADD_VAL_TO_FLOAT_VAR var:float@g value:float@c" to "+",
            "000A ADD_VAL_TO_INT_LVAR var:int@l value:int@c" to "+",
            "000B ADD_VAL_TO_FLOAT_LVAR var:float@l value:float@c" to "+",
            "000C SUB_VAL_FROM_INT_VAR var:int@g value:int@c" to "-",
            "000D SUB_VAL_FROM_FLOAT_VAR var:float@g value:float@c" to "-",
            "000E SUB_VAL_FROM_INT_LVAR var:int@l value:int@c" to "-",
            "000F SUB_VAL_FROM_FLOAT_LVAR var:float@l value:float@c" to "-",
            "0010 MULT_INT_VAR_BY_VAL var:int@g value:int@c" to "*",
            "0011 MULT_FLOAT_VAR_BY_VAL var:float@g value:float@c" to "*",
            "0012 MULT_INT_LVAR_BY_VAL var:int@l value:int@c" to "*",
            "0013 MULT_FLOAT_LVAR_BY_VAL var:float@l value:float@c" to "*",
            "0014 DIV_INT_VAR_BY_VAL var:int@g value:int@c" to "/",
            "0015 DIV_FLOAT_VAR_BY_VAL var:float@g value:float@c" to "/",
            "0016 DIV_INT_LVAR_BY_VAL var:int@l value:int@c" to "/",
            "0017 DIV_FLOAT_LVAR_BY_VAL var:float@l value:float@c" to "/",
            "?0018 IS_INT_VAR_GREATER_THAN_NUMBER var:int@g value:int@c" to ">",
            "?0019 IS_INT_LVAR_GREATER_THAN_NUMBER var:int@l value:int@c" to ">",
            "?001A IS_NUMBER_GREATER_THAN_INT_VAR value:int@c var:int@g" to ">",
            "?001B IS_NUMBER_GREATER_THAN_INT_LVAR value:int@c var:int@l" to ">",
            "?001C IS_INT_VAR_GREATER_THAN_INT_VAR a:int@g b:int@g" to ">",
            "?001D IS_INT_LVAR_GREATER_THAN_INT_LVAR a:int@l b:int@l" to ">",
            "?001E IS_INT_VAR_GREATER_THAN_INT_LVAR a:int@g b:int@l" to ">",
            "?001F IS_INT_LVAR_GREATER_THAN_INT_VAR a:int@l b:int@g" to ">",
            "?0020 IS_FLOAT_VAR_GREATER_THAN_NUMBER var:float@g value:float@c" to ">",
            "?0021 IS_FLOAT_LVAR_GREATER_THAN_NUMBER var:float@l value:float@c" to ">",
            "?0022 IS_NUMBER_GREATER_THAN_FLOAT_VAR value:float@c var:float@g" to ">",
            "?0023 IS_NUMBER_GREATER_THAN_FLOAT_LVAR value:float@c var:float@l" to ">",
            "?0024 IS_FLOAT_VAR_GREATER_THAN_FLOAT_VAR a:float@g b:float@g" to ">",
            "?0025 IS_FLOAT_LVAR_GREATER_THAN_FLOAT_LVAR a:float@l b:float@l" to ">",
            "?0026 IS_FLOAT_VAR_GREATER_THAN_FLOAT_LVAR a:float@g b:float@l" to ">",
            "?0027 IS_FLOAT_LVAR_GREATER_THAN_FLOAT_VAR a:float@l b:float@g" to ">",
            "?0028 IS_INT_VAR_GREATER_OR_EQUAL_TO_NUMBER var:int@g value:int@c" to ">=",
            "?0029 IS_INT_LVAR_GREATER_OR_EQUAL_TO_NUMBER var:int@l value:int@c" to ">=",
            "?002A IS_NUMBER_GREATER_OR_EQUAL_TO_INT_VAR value:int@c var:int@g" to ">=",
            "?002B IS_NUMBER_GREATER_OR_EQUAL_TO_INT_LVAR value:int@c var:int@l" to ">=",
            "?002C IS_INT_VAR_GREATER_OR_EQUAL_TO_INT_VAR a:int@g b:int@g" to ">=",
            "?002D IS_INT_LVAR_GREATER_OR_EQUAL_TO_INT_LVAR a:int@l b:int@l" to ">=",
            "?002E IS_INT_VAR_GREATER_OR_EQUAL_TO_INT_LVAR a:int@g b:int@l" to ">=",
            "?002F IS_INT_LVAR_GREATER_OR_EQUAL_TO_INT_VAR a:int@l b:int@g" to ">=",
            "?0030 IS_FLOAT_VAR_GREATER_OR_EQUAL_TO_NUMBER var:float@g value:float@c" to ">=",
            "?0031 IS_FLOAT_LVAR_GREATER_OR_EQUAL_TO_NUMBER var:float@l value:float@c" to ">=",
            "?0032 IS_NUMBER_GREATER_OR_EQUAL_TO_FLOAT_VAR value:float@c var:float@g" to ">=",
            "?0033 IS_NUMBER_GREATER_OR_EQUAL_TO_FLOAT_LVAR value:float@c var:float@l" to ">=",
            "?0034 IS_FLOAT_VAR_GREATER_OR_EQUAL_TO_FLOAT_VAR a:float@g b:float@g" to ">=",
            "?0035 IS_FLOAT_LVAR_GREATER_OR_EQUAL_TO_FLOAT_LVAR a:float@l b:float@l" to ">=",
            "?0036 IS_FLOAT_VAR_GREATER_OR_EQUAL_TO_FLOAT_LVAR a:float@g b:float@l" to ">=",
            "?0037 IS_FLOAT_LVAR_GREATER_OR_EQUAL_TO_FLOAT_VAR a:float@l b:float@g" to ">=",
            "?0038 IS_INT_VAR_EQUAL_TO_NUMBER var:int@g value:int@c" to "==",
            "?0039 IS_INT_LVAR_EQUAL_TO_NUMBER var:int@l value:int@c" to "==",
            "?003A IS_INT_VAR_EQUAL_TO_INT_VAR a:int@g b:int@g" to "==",
            "?003B IS_INT_LVAR_EQUAL_TO_INT_LVAR a:int@l b:int@l" to "==",
            "?003C IS_INT_VAR_EQUAL_TO_INT_LVAR a:int@g b:int@l" to "==",
            "?0042 IS_FLOAT_VAR_EQUAL_TO_NUMBER var:float@g value:float@c" to "==",
            "?0043 IS_FLOAT_LVAR_EQUAL_TO_NUMBER var:float@l value:float@c" to "==",
            "?0044 IS_FLOAT_VAR_EQUAL_TO_FLOAT_VAR a:float@g b:float@g" to "==",
            "?0045 IS_FLOAT_LVAR_EQUAL_TO_FLOAT_LVAR a:float@l b:float@l" to "==",
            "?0046 IS_FLOAT_VAR_EQUAL_TO_FLOAT_LVAR a:float@g b:float@l" to "==",
            "0058 ADD_INT_VAR_TO_INT_VAR var:int@g value:int@g" to "+",
            "0059 ADD_FLOAT_VAR_TO_FLOAT_VAR var:float@g value:float@g" to "+",
            "005A ADD_INT_LVAR_TO_INT_LVAR var:int@l value:int@l" to "+",
            "005B ADD_FLOAT_LVAR_TO_FLOAT_LVAR var:float@l value:float@l" to "+",
            "005C ADD_INT_VAR_TO_INT_LVAR var:int@l value:int@g" to "+",
            "005D ADD_FLOAT_VAR_TO_FLOAT_LVAR var:float@l value:float@g" to "+",
            "005E ADD_INT_LVAR_TO_INT_VAR var:int@g value:int@l" to "+",
            "005F ADD_FLOAT_LVAR_TO_FLOAT_VAR var:float@g value:float@l" to "+",
            "0060 SUB_INT_VAR_FROM_INT_VAR var:int@g value:int@g" to "-",
            "0061 SUB_FLOAT_VAR_FROM_FLOAT_VAR var:float@g value:float@g" to "-",
            "0062 SUB_INT_LVAR_FROM_INT_LVAR var:int@l value:int@l" to "-",
            "0063 SUB_FLOAT_LVAR_FROM_FLOAT_LVAR var:float@l value:float@l" to "-",
            "0064 SUB_INT_VAR_FROM_INT_LVAR var:int@l value:int@g" to "-",
            "0065 SUB_FLOAT_VAR_FROM_FLOAT_LVAR var:float@l value:float@g" to "-",
            "0066 SUB_INT_LVAR_FROM_INT_VAR var:int@g value:int@l" to "-",
            "0067 SUB_FLOAT_LVAR_FROM_FLOAT_VAR var:float@g value:float@l" to "-",
            "0068 MULT_INT_VAR_BY_INT_VAR var:int@g value:int@g" to "*",
            "0069 MULT_FLOAT_VAR_BY_FLOAT_VAR var:float@g value:float@g" to "*",
            "006A MULT_INT_LVAR_BY_INT_LVAR var:int@l value:int@l" to "*",
            "006B MULT_FLOAT_LVAR_BY_FLOAT_LVAR var:float@l value:float@l" to "*",
            "006C MULT_INT_VAR_BY_INT_LVAR var:int@g value:int@l" to "*",
            "006D MULT_FLOAT_VAR_BY_FLOAT_LVAR var:float@g value:float@l" to "*",
            "006E MULT_INT_LVAR_BY_INT_VAR var:int@l value:int@g" to "*",
            "006F MULT_FLOAT_LVAR_BY_FLOAT_VAR var:float@l value:float@g" to "*",
            "0070 DIV_INT_VAR_BY_INT_VAR var:int@g value:int@g" to "/",
            "0071 DIV_FLOAT_VAR_BY_FLOAT_VAR var:float@g value:float@g" to "/",
            "0072 DIV_INT_LVAR_BY_INT_LVAR var:int@l value:int@l" to "/",
            "0073 DIV_FLOAT_LVAR_BY_FLOAT_LVAR var:float@l value:float@l" to "/",
            "0074 DIV_INT_VAR_BY_INT_LVAR var:int@g value:int@l" to "/",
            "0075 DIV_FLOAT_VAR_BY_FLOAT_LVAR var:float@g value:float@l" to "/",
            "0076 DIV_INT_LVAR_BY_INT_VAR var:int@l value:int@g" to "/",
            "0077 DIV_FLOAT_LVAR_BY_FLOAT_VAR var:float@l value:float@g" to "/",
            "0078 ADD_TIMED_VAL_TO_FLOAT_VAR var:float@g value:float@c" to "+=@",
            "0079 ADD_TIMED_VAL_TO_FLOAT_LVAR var:float@l value:float@c" to "+=@",
            "007A ADD_TIMED_FLOAT_VAR_TO_FLOAT_VAR var:float@g value:float@g" to "+=@",
            "007B ADD_TIMED_FLOAT_LVAR_TO_FLOAT_LVAR var:float@l value:float@l" to "+=@",
            "007C ADD_TIMED_FLOAT_VAR_TO_FLOAT_LVAR var:float@l value:float@g" to "+=@",
            "007D ADD_TIMED_FLOAT_LVAR_TO_FLOAT_VAR var:float@g value:float@l" to "+=@",
            "007E SUB_TIMED_VAL_FROM_FLOAT_VAR var:float@g value:float@c" to "-=@",
            "007F SUB_TIMED_VAL_FROM_FLOAT_LVAR var:float@l value:float@c" to "-=@",
            "0080 SUB_TIMED_FLOAT_VAR_FROM_FLOAT_VAR var:float@g value:float@g" to "-=@",
            "0081 SUB_TIMED_FLOAT_LVAR_FROM_FLOAT_LVAR var:float@l value:float@l" to "-=@",
            "0082 SUB_TIMED_FLOAT_VAR_FROM_FLOAT_LVAR var:float@l value:float@g" to "-=@",
            "0083 SUB_TIMED_FLOAT_LVAR_FROM_FLOAT_VAR var:float@g value:float@l" to "-=@",
            "0084 SET_VAR_INT_TO_VAR_INT var:int@g value:int@g" to "=",
            "0085 SET_LVAR_INT_TO_LVAR_INT var:int@l value:int@l" to "=",
            "0086 SET_VAR_FLOAT_TO_VAR_FLOAT var:float@g value:float@g" to "=",
            "0087 SET_LVAR_FLOAT_TO_LVAR_FLOAT var:float@l value:float@l" to "=",
            "0088 SET_VAR_FLOAT_TO_LVAR_FLOAT var:float@g value:float@l" to "=",
            "0089 SET_LVAR_FLOAT_TO_VAR_FLOAT var:float@l value:float@g" to "=",
            "008A SET_VAR_INT_TO_LVAR_INT var:int@g value:int@l" to "=",
            "008B SET_LVAR_INT_TO_VAR_INT var:int@l value:int@g" to "=",
            "008C CSET_VAR_INT_TO_VAR_FLOAT var:int@g value:float@g" to "=#",
            "008D CSET_VAR_FLOAT_TO_VAR_INT var:float@g value:int@g" to "=#",
            "008E CSET_LVAR_INT_TO_VAR_FLOAT var:int@l value:float@g" to "=#",
            "008F CSET_LVAR_FLOAT_TO_VAR_INT var:float@l value:int@g" to "=#",
            "0090 CSET_VAR_INT_TO_LVAR_FLOAT var:int@g value:float@l" to "=#",
            "0091 CSET_VAR_FLOAT_TO_LVAR_INT var:float@g value:int@l" to "=#",
            "0092 CSET_LVAR_INT_TO_LVAR_FLOAT var:int@l value:float@l" to "=#",
            "0093 CSET_LVAR_FLOAT_TO_LVAR_INT var:float@l value:int@l" to "=#",
            "?04A3 IS_INT_VAR_EQUAL_TO_CONSTANT var:int@g value:int@c" to "==",
            "?04A4 IS_INT_LVAR_EQUAL_TO_CONSTANT var:int@l value:int@c" to "==",
            "04AE SET_VAR_INT_TO_CONSTANT var:int@g value:int@c" to "=",
            "04AF SET_LVAR_INT_TO_CONSTANT var:int@l value:int@c" to "=",
            "?04B0 IS_INT_VAR_GREATER_THAN_CONSTANT var:int@g value:int@c" to ">",
            "?04B1 IS_INT_LVAR_GREATER_THAN_CONSTANT var:int@l value:int@c" to ">",
            "?04B2 IS_CONSTANT_GREATER_THAN_INT_VAR value:int@c var:int@g" to ">",
            "?04B3 IS_CONSTANT_GREATER_THAN_INT_LVAR value:int@c var:int@l" to ">",
            "?04B4 IS_INT_VAR_GREATER_OR_EQUAL_TO_CONSTANT var:int@g value:int@c" to ">=",
            "?04B5 IS_INT_LVAR_GREATER_OR_EQUAL_TO_CONSTANT var:int@l value:int@c" to ">=",
            "?04B6 IS_CONSTANT_GREATER_OR_EQUAL_TO_INT_VAR value:int@c var:int@g" to ">=",
            "?04B7 IS_CONSTANT_GREATER_OR_EQUAL_TO_INT_LVAR value:int@c var:int@l" to ">=",
            "05A9 SET_VAR_TEXT_LABEL var:string@g value:string" to "=",
            "05AA SET_LVAR_TEXT_LABEL var:string@l value:string" to "=",
            "?05AD IS_VAR_TEXT_LABEL_EQUAL_TO_TEXT_LABEL var:string@g value:string" to "==",
            "?05AE IS_LVAR_TEXT_LABEL_EQUAL_TO_TEXT_LABEL var:string@l value:string" to "==",
            "06D1 SET_VAR_TEXT_LABEL16 var:string@g value:string" to "=",
            "06D2 SET_LVAR_TEXT_LABEL16 var:string@l value:string" to "=",
            "?07D6 IS_INT_LVAR_EQUAL_TO_INT_VAR a:int@l b:int@g" to "==",
            "?07D7 IS_FLOAT_LVAR_EQUAL_TO_FLOAT_VAR a:float@l b:float@g" to "==",
            "?08F9 IS_VAR_TEXT_LABEL16_EQUAL_TO_TEXT_LABEL var:string@g value:string" to "==",
            "?08FA IS_LVAR_TEXT_LABEL16_EQUAL_TO_TEXT_LABEL var:string@l value:string" to "==",
        )
        val math = rows.map { (sig, op) -> parse(sig).let { it.copy(operator = op, description = describeMath(it, op)) } }
        return math + listOf(
            def("0094 ABS_VAR_INT -> number:int@g", "Replaces an integer global variable with its absolute value."),
            def("0095 ABS_LVAR_INT -> number:int@l", "Replaces an integer local variable with its absolute value."),
            def("0096 ABS_VAR_FLOAT -> number:float@g", "Replaces a float global variable with its absolute value."),
            def("0097 ABS_LVAR_FLOAT -> number:float@l", "Replaces a float local variable with its absolute value."),
            def("0098 GENERATE_RANDOM_FLOAT -> result:float@v", "Stores a random float between 0.0 and 1.0."),
            def("0099 GENERATE_RANDOM_INT -> result:int@v", "Stores a random integer from the game's random generator."),
            def("0208 GENERATE_RANDOM_FLOAT_IN_RANGE min:float max:float -> result:float@v", "Stores a random float in [min, max)."),
            def("0209 GENERATE_RANDOM_INT_IN_RANGE min:int max:int -> result:int@v", "Stores a random integer in [min, max)."),
            def("01FB SQRT num:float -> result:float@v", "Stores the square root of a number."),
            def("02F6 SIN angle:float -> result:float@v", "Stores the sine of an angle given in degrees."),
            def("02F7 COS angle:float -> result:float@v", "Stores the cosine of an angle given in degrees."),
            def("0509 GET_DISTANCE_BETWEEN_COORDS_2D fromX:float fromY:float toX:float toY:float -> distance:float@v", "Stores the 2D distance between two points."),
            def("050A GET_DISTANCE_BETWEEN_COORDS_3D fromX:float fromY:float fromZ:float toX:float toY:float toZ:float -> distance:float@v", "Stores the 3D distance between two points."),
            def("0604 GET_HEADING_FROM_VECTOR_2D x:float y:float -> heading:float@v", "Converts a 2D direction vector into a heading in degrees."),
        )
    }

    private fun game() = listOf(
        // Player
        def("0053 CREATE_PLAYER playerIndex:int x:float y:float z:float -> handle:Player@v", "Creates the player at a position. Only used by the main script."),
        def("01F5 GET_PLAYER_CHAR self:Player -> handle:Char@v", "Stores the character (ped) handle controlled by a player."),
        def("?0256 IS_PLAYER_PLAYING self:Player", "True while the player is alive and not arrested."),
        def("01B4 SET_PLAYER_CONTROL self:Player state:bool", "Enables or disables player input."),
        def("0109 ADD_SCORE self:Player money:int", "Adds money to the player (negative values subtract)."),
        def("?010A IS_SCORE_GREATER self:Player money:int", "True if the player has more money than the given amount."),
        def("010B STORE_SCORE self:Player -> money:int@v", "Stores the player's current money."),
        def("010D ALTER_WANTED_LEVEL self:Player wantedLevel:int", "Sets the player's wanted level."),
        def("010E ALTER_WANTED_LEVEL_NO_DROP self:Player wantedLevel:int", "Raises the wanted level to at least the given value."),
        def("?010F IS_WANTED_LEVEL_GREATER self:Player wantedLevel:int", "True if the wanted level is above the given value."),
        def("0110 CLEAR_WANTED_LEVEL self:Player", "Removes the player's wanted level."),
        def("01F0 SET_MAX_WANTED_LEVEL wantedLevel:int", "Limits the maximum wanted level."),
        def("0330 SET_PLAYER_NEVER_GETS_TIRED self:Player state:bool", "Toggles infinite sprint for the player."),
        def("0331 SET_PLAYER_FAST_RELOAD self:Player state:bool", "Toggles fast weapon reloading for the player."),
        def("0373 SET_CAMERA_BEHIND_PLAYER", "Moves the camera directly behind the player."),
        // Characters
        def("009A CREATE_CHAR pedType:PedType modelId:model_char x:float y:float z:float -> handle:Char@v", "Creates a character. The model must be loaded first."),
        def("009B DELETE_CHAR self:Char", "Removes a character from the world."),
        def("00A0 GET_CHAR_COORDINATES self:Char -> x:float@v y:float@v z:float@v", "Stores a character's position."),
        def("00A1 SET_CHAR_COORDINATES self:Char x:float y:float z:float", "Moves a character to a position."),
        def("?00A3 IS_CHAR_IN_AREA_2D self:Char leftBottomX:float leftBottomY:float rightTopX:float rightTopY:float drawSphere:bool", "True if the character is inside a 2D rectangle."),
        def("?00A4 IS_CHAR_IN_AREA_3D self:Char leftBottomX:float leftBottomY:float leftBottomZ:float rightTopX:float rightTopY:float rightTopZ:float drawSphere:bool", "True if the character is inside a 3D box."),
        def("0172 GET_CHAR_HEADING self:Char -> heading:float@v", "Stores a character's heading in degrees."),
        def("0173 SET_CHAR_HEADING self:Char heading:float", "Sets a character's heading in degrees."),
        def("0223 SET_CHAR_HEALTH self:Char health:int", "Sets a character's health."),
        def("0226 GET_CHAR_HEALTH self:Char -> health:int@v", "Stores a character's health."),
        def("035F ADD_ARMOUR_TO_CHAR self:Char amount:int", "Adds armour to a character."),
        def("01B2 GIVE_WEAPON_TO_CHAR self:Char weaponType:WeaponType ammo:int", "Gives a weapon with ammo. The weapon model must be loaded."),
        def("0555 REMOVE_WEAPON_FROM_CHAR self:Char weaponType:WeaponType", "Removes one weapon from a character."),
        def("048F REMOVE_ALL_CHAR_WEAPONS self:Char", "Removes every weapon from a character."),
        def("01B9 SET_CURRENT_CHAR_WEAPON self:Char weaponType:WeaponType", "Makes a character hold the given weapon."),
        def("0470 GET_CURRENT_CHAR_WEAPON self:Char -> weaponType:WeaponType@v", "Stores the weapon a character is holding."),
        def("?02D8 IS_CURRENT_CHAR_WEAPON self:Char weaponType:WeaponType", "True if the character is holding the given weapon."),
        def("?0118 IS_CHAR_DEAD handle:any", "True if the character is dead or does not exist."),
        def("?056D DOES_CHAR_EXIST handle:any", "True if the handle refers to an existing character."),
        def("01C2 MARK_CHAR_AS_NO_LONGER_NEEDED self:Char", "Lets the game clean up a character created by the script."),
        def("?00DF IS_CHAR_IN_ANY_CAR self:Char", "True if the character is inside any vehicle."),
        def("?00DB IS_CHAR_IN_CAR self:Char vehicle:Car", "True if the character is inside a specific vehicle."),
        def("?00DD IS_CHAR_IN_MODEL self:Char modelId:model_vehicle", "True if the character is inside a vehicle of the given model."),
        def("00D9 STORE_CAR_CHAR_IS_IN self:Char -> handle:Car@v", "Stores the vehicle the character is in and marks it as used by the script."),
        def("03C0 STORE_CAR_CHAR_IS_IN_NO_SAVE self:Char -> handle:Car@v", "Stores the vehicle the character is in without taking ownership of it."),
        def("0129 CREATE_CHAR_INSIDE_CAR vehicle:Car pedType:PedType modelId:model_char -> handle:Char@v", "Creates a driver inside a vehicle."),
        def("01C8 CREATE_CHAR_AS_PASSENGER vehicle:Car pedType:PedType modelId:model_char seat:SeatId -> handle:Char@v", "Creates a passenger in a vehicle seat."),
        def("036A WARP_CHAR_INTO_CAR self:Char vehicle:Car", "Puts a character into the driver seat instantly."),
        def("0633 TASK_LEAVE_ANY_CAR handle:Char", "Makes a character leave the vehicle they are in."),
        def("05CB TASK_ENTER_CAR_AS_DRIVER char:Char vehicle:Car time:int", "Makes a character walk to and enter a vehicle as the driver."),
        def("0812 TASK_PLAY_ANIM_NON_INTERRUPTABLE handle:Char animationName:string animationFile:string blendSpeed:float loop:bool lockX:bool lockY:bool keepLastFrame:bool time:int", "Plays an animation that cannot be interrupted by other tasks."),
        def("0687 CLEAR_CHAR_TASKS self:Char", "Clears a character's tasks."),
        def("0792 CLEAR_CHAR_TASKS_IMMEDIATELY self:Char", "Clears a character's tasks without blending out."),
        def("04C4 GET_OFFSET_FROM_CHAR_IN_WORLD_COORDS self:Char xOffset:float yOffset:float zOffset:float -> x:float@v y:float@v z:float@v", "Converts an offset relative to a character into world coordinates."),
        def("?00EC LOCATE_CHAR_ANY_MEANS_2D self:Char x:float y:float xRadius:float yRadius:float drawSphere:bool", "True if the character is within a 2D radius of a point."),
        def("?00FE LOCATE_CHAR_ANY_MEANS_3D self:Char x:float y:float z:float xRadius:float yRadius:float zRadius:float drawSphere:bool", "True if the character is within a 3D radius of a point."),
        def("?02E0 IS_CHAR_SHOOTING self:Char", "True while the character is firing a weapon."),
        def("?031D HAS_CHAR_BEEN_DAMAGED_BY_WEAPON self:Char weaponType:WeaponType", "True if the character was damaged by the given weapon type."),
        def("0245 SET_ANIM_GROUP_FOR_CHAR self:Char animGroup:AnimGroup", "Changes a character's movement animation group."),
        def("0860 SET_CHAR_AREA_VISIBLE self:Char areaId:int", "Moves a character to an interior area."),
        def("04ED REQUEST_ANIMATION animationFile:string", "Starts loading an animation file (IFP)."),
        def("?04EE HAS_ANIMATION_LOADED animationFile:string", "True once a requested animation file is loaded."),
        def("04EF REMOVE_ANIMATION animationFile:string", "Releases a loaded animation file."),
        // Vehicles
        def("00A5 CREATE_CAR modelId:model_vehicle x:float y:float z:float -> handle:Car@v", "Creates a vehicle. The model must be loaded first."),
        def("00A6 DELETE_CAR self:Car", "Removes a vehicle from the world."),
        def("00AA GET_CAR_COORDINATES self:Car -> x:float@v y:float@v z:float@v", "Stores a vehicle's position."),
        def("00AB SET_CAR_COORDINATES self:Car x:float y:float z:float", "Moves a vehicle to a position."),
        def("0174 GET_CAR_HEADING self:Car -> heading:float@v", "Stores a vehicle's heading in degrees."),
        def("0175 SET_CAR_HEADING self:Car heading:float", "Sets a vehicle's heading in degrees."),
        def("?0119 IS_CAR_DEAD handle:any", "True if the vehicle is wrecked or does not exist."),
        def("?056E DOES_VEHICLE_EXIST handle:any", "True if the handle refers to an existing vehicle."),
        def("01C3 MARK_CAR_AS_NO_LONGER_NEEDED self:Car", "Lets the game clean up a vehicle created by the script."),
        def("0224 SET_CAR_HEALTH self:Car health:int", "Sets a vehicle's health (1000 = undamaged)."),
        def("0227 GET_CAR_HEALTH self:Car -> health:int@v", "Stores a vehicle's health."),
        def("0229 CHANGE_CAR_COLOUR self:Car color1:int color2:int", "Sets a vehicle's primary and secondary colours."),
        def("03F3 GET_CAR_COLOURS self:Car -> color1:int@v color2:int@v", "Stores a vehicle's colours."),
        def("020A LOCK_CAR_DOORS self:Car lockStatus:CarLock", "Sets a vehicle's door lock state."),
        def("00AD SET_CAR_CRUISE_SPEED self:Car maxSpeed:float", "Sets the maximum speed for an AI-driven vehicle."),
        def("00AE SET_CAR_DRIVING_STYLE self:Car drivingStyle:DrivingMode", "Sets how an AI driver behaves in traffic."),
        def("00A7 CAR_GOTO_COORDINATES self:Car x:float y:float z:float", "Makes an AI-driven vehicle drive to a point."),
        def("0407 GET_OFFSET_FROM_CAR_IN_WORLD_COORDS self:Car xOffset:float yOffset:float zOffset:float -> x:float@v y:float@v z:float@v", "Converts an offset relative to a vehicle into world coordinates."),
        def("02E3 GET_CAR_SPEED self:Car -> speed:float@v", "Stores a vehicle's speed."),
        def("04BA SET_CAR_FORWARD_SPEED self:Car forwardSpeed:float", "Pushes a vehicle forward at the given speed."),
        def("0441 GET_CAR_MODEL self:Car -> modelId:model_vehicle@v", "Stores a vehicle's model id."),
        def("?0137 IS_CAR_MODEL self:Car modelId:model_vehicle", "True if the vehicle has the given model."),
        def("02AC SET_CAR_PROOFS self:Car bulletProof:bool fireProof:bool explosionProof:bool collisionProof:bool meleeProof:bool", "Sets a vehicle's damage immunities."),
        def("0A30 FIX_CAR self:Car", "Repairs a vehicle completely."),
        // Objects
        def("0107 CREATE_OBJECT modelId:model_object x:float y:float z:float -> handle:Object@v", "Creates an object. The model must be loaded first."),
        def("0108 DELETE_OBJECT self:Object", "Removes an object from the world."),
        def("01C4 MARK_OBJECT_AS_NO_LONGER_NEEDED self:Object", "Lets the game clean up an object created by the script."),
        def("01BB GET_OBJECT_COORDINATES self:Object -> x:float@v y:float@v z:float@v", "Stores an object's position."),
        def("01BC SET_OBJECT_COORDINATES self:Object x:float y:float z:float", "Moves an object to a position."),
        def("0176 GET_OBJECT_HEADING self:Object -> heading:float@v", "Stores an object's heading in degrees."),
        def("0177 SET_OBJECT_HEADING self:Object heading:float", "Sets an object's heading in degrees."),
        def("0382 SET_OBJECT_COLLISION self:Object state:bool", "Enables or disables an object's collision."),
        def("?03CA DOES_OBJECT_EXIST handle:any", "True if the handle refers to an existing object."),
        // Streaming
        def("0247 REQUEST_MODEL modelId:model_any", "Starts loading a model."),
        def("?0248 HAS_MODEL_LOADED modelId:model_any", "True once a requested model is loaded."),
        def("0249 MARK_MODEL_AS_NO_LONGER_NEEDED modelId:model_any", "Releases a model requested by the script."),
        def("038B LOAD_ALL_MODELS_NOW", "Blocks until all requested models are loaded."),
        def("04E4 REQUEST_COLLISION x:float y:float", "Loads world collision around a point."),
        def("03CB LOAD_SCENE x:float y:float z:float", "Loads the map around a point."),
        // Text
        def("00BA PRINT_BIG key:gxt_key time:int style:TextStyle", "Shows a large styled text from the text tables."),
        def("00BB PRINT key:gxt_key time:int flag:int", "Queues a subtitle text from the text tables."),
        def("00BC PRINT_NOW key:gxt_key time:int flag:int", "Shows a subtitle text immediately."),
        def("00BE CLEAR_PRINTS", "Removes all subtitle texts."),
        def("03E5 PRINT_HELP key:gxt_key", "Shows a help box text."),
        def("03E6 CLEAR_HELP", "Removes the help box."),
        def("01E3 PRINT_WITH_NUMBER_BIG key:gxt_key num:int duration:int style:TextStyle", "Shows a large text with a number inserted."),
        def("01E4 PRINT_WITH_NUMBER key:gxt_key num:int duration:int flag:int", "Queues a subtitle with a number inserted."),
        def("01E5 PRINT_WITH_NUMBER_NOW key:gxt_key num:int duration:int flag:int", "Shows a subtitle with a number inserted, immediately."),
        def("033E DISPLAY_TEXT offsetLeft:float offsetTop:float key:gxt_key", "Draws a text this frame at screen coordinates (640x448 space)."),
        def("045A DISPLAY_TEXT_WITH_NUMBER offsetLeft:float offsetTop:float key:gxt_key num:int", "Draws a text with a number this frame."),
        def("033F SET_TEXT_SCALE widthScale:float heightScale:float", "Sets the scale for the next drawn text."),
        def("0340 SET_TEXT_COLOUR red:int green:int blue:int alpha:int", "Sets the colour for the next drawn text."),
        def("0341 SET_TEXT_JUSTIFY state:bool", "Toggles justification for the next drawn text."),
        def("0342 SET_TEXT_CENTRE state:bool", "Toggles centring for the next drawn text."),
        def("0343 SET_TEXT_WRAPX width:float", "Sets the wrap width for the next drawn text."),
        def("0345 SET_TEXT_BACKGROUND state:bool", "Toggles a background box for the next drawn text."),
        def("0348 SET_TEXT_PROPORTIONAL state:bool", "Toggles proportional spacing for the next drawn text."),
        def("0349 SET_TEXT_FONT font:Font", "Sets the font for the next drawn text."),
        def("03F0 USE_TEXT_COMMANDS state:bool", "Keeps script-drawn texts on screen between frames."),
        // Screen, camera, world
        def("016A DO_FADE time:int direction:Fade", "Fades the screen in or out over a duration."),
        def("?016B GET_FADING_STATUS", "True while a screen fade is in progress."),
        def("02A3 SWITCH_WIDESCREEN state:bool", "Toggles the cinematic widescreen bars."),
        def("0826 DISPLAY_HUD state:bool", "Shows or hides the HUD."),
        def("0581 DISPLAY_RADAR state:bool", "Shows or hides the radar."),
        def("0003 SHAKE_CAM intensity:int", "Shakes the camera."),
        def("015F SET_FIXED_CAMERA_POSITION x:float y:float z:float upVecOffsetX:float upVecOffsetY:float upVecOffsetZ:float", "Places the camera at a fixed position."),
        def("0160 POINT_CAMERA_AT_POINT x:float y:float z:float switchStyle:SwitchType", "Points the fixed camera at a position."),
        def("0158 POINT_CAMERA_AT_CAR vehicle:Car mode:CameraMode switchStyle:SwitchType", "Points the camera at a vehicle."),
        def("0159 POINT_CAMERA_AT_CHAR char:Char mode:CameraMode switchStyle:SwitchType", "Points the camera at a character."),
        def("015A RESTORE_CAMERA", "Returns the camera to normal with a transition."),
        def("02EB RESTORE_CAMERA_JUMPCUT", "Returns the camera to normal instantly."),
        def("04BB SET_AREA_VISIBLE areaId:Interior", "Switches which interior area is rendered."),
        def("00C0 SET_TIME_OF_DAY hours:int minutes:int", "Sets the in-game clock."),
        def("00BF GET_TIME_OF_DAY -> hours:int@v minutes:int@v", "Stores the in-game time."),
        def("01B5 FORCE_WEATHER type:WeatherType", "Changes the weather gradually."),
        def("01B6 FORCE_WEATHER_NOW type:WeatherType", "Changes the weather immediately."),
        def("01B7 RELEASE_WEATHER", "Returns weather control to the game."),
        def("01EB SET_CAR_DENSITY_MULTIPLIER multiplier:float", "Scales traffic density."),
        def("03DE SET_PED_DENSITY_MULTIPLIER multiplier:float", "Scales pedestrian density."),
        def("0395 CLEAR_AREA x:float y:float z:float radius:float clearParticles:bool", "Removes vehicles, peds and objects around a point."),
        def("020C ADD_EXPLOSION x:float y:float z:float type:ExplosionType", "Creates an explosion."),
        def("01BD GET_GAME_TIMER -> time:int@v", "Stores the game's running time in milliseconds."),
        // Markers and pickups
        def("018A ADD_BLIP_FOR_COORD x:float y:float z:float -> handle:Blip@v", "Adds a radar marker at a position."),
        def("0186 ADD_BLIP_FOR_CAR vehicle:Car -> handle:Blip@v", "Adds a radar marker on a vehicle."),
        def("0187 ADD_BLIP_FOR_CHAR char:Char -> handle:Blip@v", "Adds a radar marker on a character."),
        def("02A8 ADD_SPRITE_BLIP_FOR_COORD x:float y:float z:float sprite:RadarSprite -> handle:Blip@v", "Adds a radar icon at a position."),
        def("0164 REMOVE_BLIP self:Blip", "Removes a radar marker."),
        def("0165 CHANGE_BLIP_COLOUR self:Blip color:BlipColor", "Changes a radar marker's colour."),
        def("0168 CHANGE_BLIP_SCALE self:Blip size:int", "Changes a radar marker's size."),
        def("0213 CREATE_PICKUP modelId:model_object pickupType:PickupType x:float y:float z:float -> handle:Pickup@v", "Creates a pickup."),
        def("032B CREATE_PICKUP_WITH_AMMO modelId:model_object pickupType:PickupType ammo:int x:float y:float z:float -> handle:Pickup@v", "Creates a weapon pickup with ammo."),
        def("?0214 HAS_PICKUP_BEEN_COLLECTED self:Pickup", "True once the pickup was collected."),
        def("0215 REMOVE_PICKUP self:Pickup", "Removes a pickup."),
        // Input, timers, stats, audio, groups
        def("00E2 GET_PAD_STATE pad:PadId buttonId:Button -> state:int@v", "Stores the state of a controller button."),
        def("014E DISPLAY_ONSCREEN_TIMER timer:int@g direction:TimerDirection", "Shows an on-screen timer bound to a global variable."),
        def("014F CLEAR_ONSCREEN_TIMER timer:int@g", "Removes an on-screen timer."),
        def("03C3 DISPLAY_ONSCREEN_TIMER_WITH_STRING timer:int@g direction:TimerDirection text:gxt_key", "Shows an on-screen timer with a caption."),
        def("03C4 DISPLAY_ONSCREEN_COUNTER_WITH_STRING counter:int@g display:CounterDisplay text:gxt_key", "Shows an on-screen counter with a caption."),
        def("0151 CLEAR_ONSCREEN_COUNTER counter:int@g", "Removes an on-screen counter."),
        def("0629 SET_INT_STAT id:StatId value:int", "Sets an integer statistic."),
        def("0652 GET_INT_STAT id:StatId -> value:int@v", "Stores an integer statistic."),
        def("062A SET_FLOAT_STAT id:StatId value:float", "Sets a float statistic."),
        def("0653 GET_FLOAT_STAT id:StatId -> value:float@v", "Stores a float statistic."),
        def("018C ADD_ONE_OFF_SOUND x:float y:float z:float soundId:ScriptSound", "Plays a one-shot sound at a position."),
        def("03CF LOAD_MISSION_AUDIO slotId:MissionAudioSlot audioId:int", "Loads a mission audio line into a slot."),
        def("?03D0 HAS_MISSION_AUDIO_LOADED slotId:MissionAudioSlot", "True once mission audio is loaded."),
        def("03D1 PLAY_MISSION_AUDIO slotId:MissionAudioSlot", "Plays loaded mission audio."),
        def("0781 GET_WEAPONTYPE_MODEL weaponType:WeaponType -> modelId:model_object@v", "Stores the model id of a weapon type."),
        def("07AF GET_PLAYER_GROUP self:Player -> handle:Group@v", "Stores the player's group handle."),
        def("062F CREATE_GROUP defaultTaskAllocator:DefaultTaskAllocator -> handle:Group@v", "Creates a ped group."),
        def("0631 SET_GROUP_MEMBER self:Group handle:Char", "Adds a character to a group."),
    )

    /** Commands that only exist in the mobile ports (touch widgets, logging, mobile save system). */
    private fun mobile() = listOf(
        def("0A4F FINISHED_WITH_XBOX_PLAYER2", "Mobile build leftover; ends the second-player session."),
        def("0A50 DO_DEBUG_STUFF", "Mobile build leftover used for debugging."),
        def("?0A51 IS_WIDGET_PRESSED widgetId:WidgetId", "Mobile: true while an on-screen touch widget is pressed."),
        def("?0A52 IS_WIDGET_RELEASED widgetId:WidgetId", "Mobile: true when an on-screen touch widget is released."),
        def("?0A53 IS_WIDGET_DOUBLETAPPED widgetId:WidgetId", "Mobile: true when a touch widget is double-tapped."),
        def("?0A54 IS_WIDGET_SWIPED widgetId:WidgetId", "Mobile: true when a touch widget is swiped."),
        def("?0A55 IS_WIDGET_SWIPED_LEFT widgetId:WidgetId", "Mobile: true when a touch widget is swiped left."),
        def("?0A56 IS_WIDGET_SWIPED_RIGHT widgetId:WidgetId", "Mobile: true when a touch widget is swiped right."),
        def("?0A57 DO_MISSION_SKIP -> missionPage:int@v missionNum:int@v", "Mobile: mission-skip helper; stores the selected page and mission."),
        def("?0A58 GET_MISSION_NUM -> missionNum:int@v", "Mobile: stores the selected mission number."),
        def("?0A59 GET_MISSION_PAGE -> missionPage:int@v", "Mobile: stores the selected mission page."),
        def("0A5A GET_WIDGET_VALUE widgetId:WidgetId -> value:float@v", "Mobile: stores a widget's value."),
        def("0A5B GET_WIDGET_VALUE2 widgetId:WidgetId -> x:float@v y:float@v", "Mobile: stores a widget's two-axis value."),
        def("0A5C DISPLAY_TEXT_WIDGET offsetLeft:float offsetTop:float key:gxt_key", "Mobile: draws a text inside the widget layer."),
        def("0A5D GET_WIDGET_POSITION widgetId:WidgetId -> screenX:float@v screenY:float@v scaleX:float@v scaleY:float@v", "Mobile: stores a widget's screen position and scale."),
        def("0A5E SET_WIDGET_VALUE widgetId:WidgetId value:float", "Mobile: sets a widget's value."),
        def("0A5F SET_SLIDER_RANGE widgetId:WidgetId rangeX:float rangeY:float", "Mobile: sets a slider widget's range."),
        def("0A60 ADD_WIDGET_FLAG widgetId:WidgetId widgetFlag:WidgetFlag", "Mobile: sets a widget flag."),
        def("0A61 REMOVE_WIDGET_FLAG widgetId:WidgetId widgetFlag:WidgetFlag", "Mobile: clears a widget flag."),
        def("0A62 ADD_BUTTON_FLAG widgetId:WidgetId flag:int", "Mobile: sets a button flag."),
        def("0A63 REMOVE_BUTTON_FLAG widgetId:WidgetId flag:int", "Mobile: clears a button flag."),
        def("?0A64 IS_TOUCH_ENABLED", "Mobile: true when touch controls are active."),
        def("?0A65 IS_FINALBUILD", "Mobile: true in release builds of the game."),
        def("0A66 WRITE_LOG message:string128@c", "Mobile: writes a message to the game log."),
        def("0A67 WRITE_LOG_INT a:int b:int c:int message:string128@c", "Mobile: writes integers to the game log."),
        def("0A68 WRITE_LOG_FLOAT a:float b:float c:float message:string128@c", "Mobile: writes floats to the game log."),
        def("0A69 CREATE_SHOP_WIDGET menuName:gxt_key", "Mobile: creates a shop menu widget."),
        def("0A6A ADD_SHOP_ITEM itemName:gxt_key price:int", "Mobile: adds an item to the shop widget."),
        def("0A6B DELETE_WIDGET widgetId:WidgetId", "Mobile: removes a widget."),
        def("0A6C SET_EQUIPPED_ITEM widgetId:WidgetId item:int", "Mobile: marks an item as equipped in a widget."),
        def("0A6D PRINT_HELP_FOREVER_CONDITIONAL key:gxt_key type:int", "Mobile: shows a persistent help text for an input scheme."),
        def("0A6E SET_WIDGET_TEXTURE widgetId:WidgetId textureName:string128@c", "Mobile: changes a widget's texture."),
        def("0A6F CHECKPOINT_SAVE value:int", "Mobile: mission checkpoint save."),
        def("0A70 DISPLAY_TEXT_CLAMPED offsetLeft:float offsetTop:float key:gxt_key scale:float", "Mobile: draws a text clamped to the screen."),
        def("0A71 DISPLAY_TEXT_WITH_NUMBER_CLAMPED offsetLeft:float offsetTop:float key:gxt_key number:int scale:float", "Mobile: draws a text with a number, clamped to the screen."),
        def("0A72 AUTO_SAVE", "Mobile: triggers the automatic save."),
        def("0A73 SET_WIDGET_VALUE3 widgetId:WidgetId x:float y:float z:float", "Mobile: sets a widget's three-component value."),
        def("?0A74 IS_CHECKPOINT_RESUMING value:bool", "Mobile: true when resuming from a mission checkpoint."),
        def("?0A75 SET_ACTIVE_MENU_ITEM_CAR_MODS self:MenuGrid carcolor:int", "Mobile: selects a car-colour item in a menu grid."),
        def("?0A76 HID_IMPLEMENTS hidId:int", "Mobile: true if the connected controller implements an input."),
        def("0A77 CHECKPOINT_SAVE_ODDJOB value:int", "Mobile: odd-job checkpoint save."),
        def("0A78 PRINT_HELP_FOREVER_CONDITIONAL_TOUCH key:gxt_key type:int", "Mobile: persistent help text for touch controls."),
        def("0A79 PRINT_HELP_FOREVER_CONDITIONAL_HID key:gxt_key type:int", "Mobile: persistent help text for controllers."),
        def("0A7A PRINT_HELP_FOREVER_CONDITIONAL_TOUCH_CLASSIC key:gxt_key type:int", "Mobile: persistent help text for classic touch layout."),
        def("0A7B PRINT_HELP_FOREVER_CONDITIONAL_TOUCH_ADAPTED key:gxt_key type:int", "Mobile: persistent help text for adapted touch layout."),
        def("0A7C PRINT_HELP_FOREVER_CONDITIONAL_HID_JOYPAD key:gxt_key type:int", "Mobile: persistent help text for joypads."),
        def("0A7D PRINT_HELP_FOREVER_CONDITIONAL_HID_KEYBOARD key:gxt_key type:int", "Mobile: persistent help text for keyboards."),
        def("0A7E PRINT_HELP_FOREVER_CONDITIONAL_TOUCH_ANALOG key:gxt_key type:int", "Mobile: persistent help text for analog touch steering."),
        def("0A7F PRINT_HELP_FOREVER_CONDITIONAL_TOUCH_DIGITAL key:gxt_key type:int", "Mobile: persistent help text for digital touch steering."),
        def("0A80 PRINT_HELP_FOREVER_CONDITIONAL_TOUCH_FLICK key:gxt_key type:int", "Mobile: persistent help text for flick controls."),
        def("0A81 PRINT_HELP_CONDITIONAL key:gxt_key type:int", "Mobile: help text for an input scheme."),
        def("0A82 PRINT_HELP_CONDITIONAL_TOUCH key:gxt_key type:int", "Mobile: help text for touch controls."),
        def("0A83 PRINT_HELP_CONDITIONAL_HID key:gxt_key type:int", "Mobile: help text for controllers."),
        def("0A84 PRINT_HELP_CONDITIONAL_TOUCH_CLASSIC key:gxt_key type:int", "Mobile: help text for classic touch layout."),
        def("0A85 PRINT_HELP_CONDITIONAL_TOUCH_ADAPTED key:gxt_key type:int", "Mobile: help text for adapted touch layout."),
        def("0A86 PRINT_HELP_CONDITIONAL_HID_JOYPAD key:gxt_key type:int", "Mobile: help text for joypads."),
        def("0A87 PRINT_HELP_CONDITIONAL_HID_KEYBOARD key:gxt_key type:int", "Mobile: help text for keyboards."),
        def("0A88 PRINT_HELP_CONDITIONAL_TOUCH_ANALOG key:gxt_key type:int", "Mobile: help text for analog touch steering."),
        def("0A89 SET_WIDGET_VALUE2 widgetId:WidgetId x:float y:float", "Mobile: sets a widget's two-component value."),
        def("0A8A SET_WIDGET_INFO widgetId:WidgetId bTitle:bool bPercentage:bool bTime:bool bNumber:bool color:int value:float key:gxt_key", "Mobile: configures a widget's info display."),
        def("0A8B SET_WIDGET_INFO2 widgetId:WidgetId a:int b:int c:int d:int e:int key:gxt_key", "Mobile: configures a widget's extended info display."),
        def("0A8C LOAD_ALL_STREAMING_MODELS", "Mobile: loads all requested models at once. (On PC this number is CLEO's WRITE_MEMORY.)"),
        def("?0A8D IS_HID_RELEASED hidId:int", "Mobile: true when a controller input is released. (On PC this number is CLEO's READ_MEMORY.)"),
        def("0A8E UNLOCK_ACHIEVEMENT id:int", "Mobile: unlocks a platform achievement."),
        def("0A8F RELEASE_WEAPON_LOCK", "Mobile: releases the touch weapon lock-on."),
        def("?0A90 IS_HID_PRESSED hidId:int", "Mobile: true while a controller input is pressed."),
    )

    /** Opcodes added by CLEO Android. */
    private fun cleoAndroid() = listOf(
        def("?00E1 IS_BUTTON_PRESSED touch:PadId touchPoints:TouchPoints", "CLEO Android: true if a screen touch zone (1-9 on a 3x3 grid) is pressed. See 0DE0 and 0DE1.", extension = CLEO),
        def("0DD0 STORE_LABEL_POINTER address:int@v label", "CLEO Android: stores the absolute address of a label (e.g. a data block).", extension = CLEO),
        def("0DD2 CALL_FUNCTION address:int", "CLEO Android: calls native code at an address using registers set with 0DD3.", extension = CLEO),
        def("0DD3 SET_REGISTER_VALUE regId:int value:any", "CLEO Android: sets a CPU register value for the next 0DD2 call.", extension = CLEO),
        def("0DD4 GET_REGISTER_VALUE regId:int -> value:any@v", "CLEO Android: reads a CPU register after a native call.", extension = CLEO),
        def("0DD5 GET_PLATFORM -> platform:Platform@v", "CLEO Android: stores the platform id (1 = Android).", extension = CLEO),
        def("0DD6 GET_GAME_VERSION -> versionId:GameVerInternal@v", "CLEO Android: stores the internal game version id (see GameVerInternal).", extension = CLEO),
        def("0DD7 GET_IMAGE_BASE -> address:int@v", "CLEO Android: stores the load address of the game library.", extension = CLEO),
        def("0DD8 READ_MEMORY address:int size:int ib:bool -> result:any@v", "CLEO Android: reads a value of the given size from game memory; with ib set the address is relative to the game library's image base. Addresses are version- and ABI-specific.", extension = CLEO),
        def("0DD9 WRITE_MEMORY address:int value:any size:int ib:bool vp:bool", "CLEO Android: writes a value to game memory (ib: relative to the image base, vp: virtual-protect flag). Addresses are version- and ABI-specific.", extension = CLEO),
        def("0DDA FIND_MEMORY_PATTERN pointer:int index:int -> address:int@v", "CLEO Android: searches the game library for a byte pattern; index picks among several matches.", extension = CLEO),
        def("0DDB GET_GAME_VERSION_EX -> nameHash:string@v verHash:string@v verCode:int@v", "CLEO Android: stores hashes of the package name and version string, and the Android version code.", extension = CLEO),
        def("0DDC SET_CLEO_SHARED_VAR varId:int value:any", "CLEO Android: writes a variable shared between CLEO scripts. Id 0 is reserved for the CLEO menu state.", extension = CLEO),
        def("0DDD GET_CLEO_SHARED_VAR varId:int -> result:any@v", "CLEO Android: reads a variable shared between CLEO scripts.", extension = CLEO),
        def("0DDE CALL_FUNCTION address:int ib:bool type:string value:any arguments", "CLEO Android: calls native code with arguments.", extension = CLEO),
        def("0DE0 GET_TOUCH_POINT_STATE touchPoints:TouchPoints mintime:int -> state:bool@v", "CLEO Android: 1 if a screen touch zone (1-9) was held for at least mintime ms.", extension = CLEO),
        def("0DE1 GET_TOUCH_SLIDE_STATE touchPointsStart:TouchPoints touchPointsEnd:TouchPoints mintime:int maxtime:int -> state:bool@v", "CLEO Android: 1 if a swipe went from one touch zone to another within the time window.", extension = CLEO),
        def("0DE2 GET_MENU_BUTTON_STATE -> state:bool@v", "CLEO Android: 1 while the Android hardware menu key is held. Most modern devices have no such key.", extension = CLEO),
        def("0DE3 GET_MENU_BUTTON_PRESSED mintime:int -> state:bool@v", "CLEO Android: 1 if the hardware menu key was held for at least mintime ms.", extension = CLEO),
        def("0DF2 CREATE_MENU pointer:int numItems:int", "CLEO Android: shows a touch menu described by a data block (address from 0DD0) with the given item count.", extension = CLEO),
        def("0DF3 DELETE_MENU", "CLEO Android: closes the native menu.", extension = CLEO),
    )

    /** Small enum set needed by the core commands above. Values follow CLEO Android's definitions. */
    private fun enums() = listOf(
        EnumDefinition(
            "TouchPoints",
            linkedMapOf(
                "LeftTop" to 1, "LeftCenter" to 2, "LeftBottom" to 3,
                "CenterTop" to 4, "Center" to 5, "CenterBottom" to 6,
                "RightTop" to 7, "RightCenter" to 8, "RightBottom" to 9,
            ),
        ),
        EnumDefinition(
            "Platform",
            linkedMapOf(
                "None" to 0, "Android" to 1, "PSP" to 2, "IOS" to 3, "FOS" to 4,
                "XBox" to 5, "PS2" to 6, "PS3" to 7, "Mac" to 8, "Windows" to 9,
            ),
        ),
        EnumDefinition(
            "GameVerInternal",
            linkedMapOf(
                "VER_NONE" to 0, "VER_GTA3_1_4" to 1, "VER_GTAVC_1_03" to 2,
                "VER_GTASA_1_00" to 3, "VER_GTASA_1_01" to 4, "VER_GTASA_1_02" to 5, "VER_GTASA_1_03" to 6,
                "VER_GTASA_1_05" to 7, "VER_GTASA_1_06" to 8, "VER_GTASA_1_05_GER" to 9, "VER_GTASA_1_07" to 10,
                "VER_GTA3_1_6" to 11, "VER_GTAVC_1_06" to 12, "VER_GTASA_1_08" to 13, "VER_GTALCS_2_2" to 14,
                "VER_GTA3_1_8_OR_HIGHER" to 15, "VER_GTAVC_1_09_OR_HIGHER" to 16, "VER_GTASA_2_00_OR_HIGHER" to 17,
                "VER_GTALCS_2_4_OR_HIGHER" to 18, "VER_GTALCS_PSP_1_05_OR_HIGHER" to 19, "VER_GTAVCS_PSP_1_02_OR_HIGHER" to 20,
            ),
        ),
        EnumDefinition("Fade", linkedMapOf("Out" to 0, "In" to 1)),
    )

    private const val CLEO = OpcodeDefinition.EXTENSION_CLEO

    private fun def(signature: String, description: String, segment: Boolean = false, extension: String = OpcodeDefinition.EXTENSION_DEFAULT) =
        parse(signature).copy(description = description, isSegment = segment, extension = extension)

    /** Parses the compact signature notation documented on [CoreOpcodes]. */
    internal fun parse(signature: String): OpcodeDefinition {
        var text = signature.trim()
        var condition = false
        var branch = false
        while (text.isNotEmpty() && (text[0] == '?' || text[0] == '!')) {
            if (text[0] == '?') condition = true else branch = true
            text = text.substring(1)
        }
        val tokens = text.split(Regex("\\s+"))
        require(tokens.size >= 2) { "Bad signature: $signature" }
        val id = tokens[0].toInt(16)
        var output = false
        val params = mutableListOf<ParamDefinition>()
        for (token in tokens.drop(2)) {
            if (token == "->") {
                output = true
                continue
            }
            val name = if (':' in token) token.substringBefore(':') else ""
            val typeAndSource = token.substringAfter(':')
            val source = when (typeAndSource.substringAfter('@', "")) {
                "g" -> ParamSource.VAR_GLOBAL
                "l" -> ParamSource.VAR_LOCAL
                "v" -> ParamSource.VAR_ANY
                "c" -> ParamSource.LITERAL
                "" -> ParamSource.ANY
                else -> throw IllegalArgumentException("Bad source in $signature")
            }
            params += ParamDefinition(name, typeAndSource.substringBefore('@'), source, output)
        }
        return OpcodeDefinition(id = id, name = tokens[1], params = params, isCondition = condition, isBranch = branch)
    }

    private fun describeMath(def: OpcodeDefinition, op: String): String {
        val (a, b) = def.params
        fun side(p: ParamDefinition): String {
            val kind = when (p.typeName) {
                "int" -> "integer"
                "float" -> "float"
                else -> "text label"
            }
            return when (p.source) {
                ParamSource.VAR_GLOBAL -> "$kind global variable"
                ParamSource.VAR_LOCAL -> "$kind local variable"
                else -> if (p.typeName == "string") "text label" else "$kind number"
            }
        }
        return when (op) {
            "=" -> "Sets the ${side(a)} to the ${side(b)}."
            "+" -> "Adds the ${side(b)} to the ${side(a)}."
            "-" -> "Subtracts the ${side(b)} from the ${side(a)}."
            "*" -> "Multiplies the ${side(a)} by the ${side(b)}."
            "/" -> "Divides the ${side(a)} by the ${side(b)}."
            "+=@" -> "Adds the ${side(b)}, scaled by the frame time step, to the ${side(a)}."
            "-=@" -> "Subtracts the ${side(b)}, scaled by the frame time step, from the ${side(a)}."
            "=#" -> "Converts the ${side(b)} and stores it in the ${side(a)}."
            ">" -> "True if the ${side(a)} is greater than the ${side(b)}."
            ">=" -> "True if the ${side(a)} is greater than or equal to the ${side(b)}."
            "==" -> "True if the ${side(a)} equals the ${side(b)}."
            else -> ""
        }
    }
}
