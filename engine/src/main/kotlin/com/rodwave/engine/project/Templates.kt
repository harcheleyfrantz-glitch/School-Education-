package com.rodwave.engine.project

import com.rodwave.engine.scm.ScriptFormat

/** Starter content for new projects. All templates are original and compile with the core opcode set. */
data class ProjectTemplate(
    val id: String,
    val title: String,
    val description: String,
    val format: ScriptFormat,
    val source: (scriptName: String) -> String,
)

data class Snippet(val id: String, val title: String, val description: String, val body: String)

object Templates {
    private fun shortName(name: String): String =
        name.uppercase().filter { it.isLetterOrDigit() || it == '_' }.take(7).ifEmpty { "SCRIPT" }

    val EMPTY = ProjectTemplate(
        "empty-csa", "Empty auto-start script",
        "A loop that runs while the game is loaded (.csa).", ScriptFormat.CLEO_ANDROID_AUTO,
    ) { name ->
        """
        {${'$'}CLEO .csa}
        // ${name} — CLEO Android script, starts automatically
        0000: nop
        03A4: script_name '${shortName(name)}'

        while true
            wait 250
            // Your code here. Keep a wait inside every loop.
        end
        """.trimIndent() + "\n"
    }

    val TOUCH_TOGGLE = ProjectTemplate(
        "touch-toggle", "Touch-activated toggle",
        "Hold the top-right corner for one second to toggle endless sprint (.csa).", ScriptFormat.CLEO_ANDROID_AUTO,
    ) { name ->
        """
        {${'$'}CLEO .csa}
        // ${name}: hold the top-right corner of the screen for 1 second to toggle endless sprint.
        0000: nop
        03A4: script_name '${shortName(name)}'
        int enabled = 0
        int touched = 0

        while true
            wait 100
            if
                0256: is_player_playing ${'$'}PLAYER_CHAR
            then
                0DE0: get_touch_point_state TouchPoints.RightTop mintime 1000 store_to touched
                if
                    touched == 1
                then
                    if
                        enabled == 0
                    then
                        enabled = 1
                        0330: set_player_never_gets_tired ${'$'}PLAYER_CHAR true
                    else
                        enabled = 0
                        0330: set_player_never_gets_tired ${'$'}PLAYER_CHAR false
                    end
                    wait 1000
                end
            end
        end
        """.trimIndent() + "\n"
    }

    val HEAL = ProjectTemplate(
        "heal-csi", "Menu script: heal the player",
        "Restores health and armour when started from the CLEO menu (.csi).", ScriptFormat.CLEO_ANDROID_INVOKED,
    ) { name ->
        """
        {${'$'}CLEO .csi}
        // ${name}: start it from the CLEO menu to restore health and armour.
        0000: nop
        03A4: script_name '${shortName(name)}'
        if
            0256: is_player_playing ${'$'}PLAYER_CHAR
        then
            01F5: get_player_char ${'$'}PLAYER_CHAR store_to 0@
            0223: set_char_health 0@ health 100
            035F: add_armour_to_char 0@ amount 100
        end
        004E: terminate_this_script
        """.trimIndent() + "\n"
    }

    val SPAWN_CAR = ProjectTemplate(
        "spawn-car", "Menu script: spawn a vehicle",
        "Loads a model and creates a vehicle in front of the player (.csi).", ScriptFormat.CLEO_ANDROID_INVOKED,
    ) { name ->
        """
        {${'$'}CLEO .csi}
        // ${name}: spawns a vehicle five metres in front of the player.
        0000: nop
        03A4: script_name '${shortName(name)}'
        const CAR_MODEL = #CHEETAH

        0247: request_model CAR_MODEL
        while not 0248: has_model_loaded CAR_MODEL
            wait 0
        end
        01F5: get_player_char ${'$'}PLAYER_CHAR store_to 0@
        04C4: get_offset_from_char_in_world_coords 0@ offset 0.0 5.0 0.0 store_to 1@ 2@ 3@
        00A5: create_car CAR_MODEL at 1@ 2@ 3@ store_to 4@
        0175: set_car_heading 4@ to 0.0
        0249: mark_model_as_no_longer_needed CAR_MODEL
        01C3: mark_car_as_no_longer_needed 4@
        004E: terminate_this_script
        """.trimIndent() + "\n"
    }

    val VERSION_CHECK = ProjectTemplate(
        "version-check", "Game version check",
        "Reads CLEO Android's platform and game version before doing anything else (.csa).", ScriptFormat.CLEO_ANDROID_AUTO,
    ) { name ->
        """
        {${'$'}CLEO .csa}
        // ${name}: only runs on GTA SA 2.00 or newer, as reported by CLEO Android.
        0000: nop
        03A4: script_name '${shortName(name)}'
        0DD5: get_platform store_to 0@
        0DD6: get_game_version store_to 1@
        if or
            0@ <> Platform.Android
            1@ <> GameVerInternal.VER_GTASA_2_00_OR_HIGHER
        then
            004E: terminate_this_script
        end

        while true
            wait 500
            // Version-specific code goes here.
        end
        """.trimIndent() + "\n"
    }

    val ALL = listOf(EMPTY, TOUCH_TOGGLE, HEAL, SPAWN_CAR, VERSION_CHECK)

    val SNIPPETS = listOf(
        Snippet("loop", "Main loop", "Endless loop with a wait", "while true\n    wait 0\n    \nend"),
        Snippet("if-playing", "If the player is playing", "Condition block on the player state", "if\n    0256: is_player_playing \$PLAYER_CHAR\nthen\n    \nend"),
        Snippet("load-model", "Load a model", "Request a model and wait for it", "0247: request_model #CHEETAH\nwhile not 0248: has_model_loaded #CHEETAH\n    wait 0\nend"),
        Snippet("touch", "Touch zone check", "Store 1 when a screen zone is held", "0DE0: get_touch_point_state TouchPoints.Center mintime 500 store_to 0@"),
        Snippet("for", "Counting loop", "Repeat a block a fixed number of times", "for 0@ = 1 to 10\n    wait 0\nend"),
        Snippet("player-char", "Get player character", "Store the player's character handle", "01F5: get_player_char \$PLAYER_CHAR store_to 0@"),
        Snippet("coords", "Player position", "Store the player's coordinates", "01F5: get_player_char \$PLAYER_CHAR store_to 0@\n00A0: get_char_coordinates 0@ store_to 1@ 2@ 3@"),
        Snippet("end", "End script", "Terminate this script", "004E: terminate_this_script"),
    )

    fun byId(id: String): ProjectTemplate? = ALL.firstOrNull { it.id == id }
}
