package com.rodwave.desktop

import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import com.rodwave.studio.core.Studio
import com.rodwave.studio.ui.RodwaveApp
import java.io.File

fun main(args: Array<String>) {
    if (args.firstOrNull() == "screenshots") {
        Screenshots.renderAll(File(args.getOrNull(1) ?: "screenshots-out"))
        return
    }
    application {
        val scope = rememberCoroutineScope()
        val studio = remember { Studio(DesktopPlatform(File(System.getProperty("user.home"), ".rodwave-preview")), scope) }
        Window(
            onCloseRequest = {
                studio.onBackground()
                exitApplication()
            },
            title = "Rodwave — desktop preview",
            state = rememberWindowState(width = 430.dp, height = 900.dp),
        ) {
            RodwaveApp(studio)
        }
    }
}
