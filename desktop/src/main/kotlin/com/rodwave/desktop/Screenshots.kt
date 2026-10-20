package com.rodwave.desktop

import androidx.compose.ui.ImageComposeScene
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.unit.Density
import com.rodwave.engine.compiler.ScriptCompiler
import com.rodwave.engine.project.Templates
import com.rodwave.studio.core.FolderPurpose
import com.rodwave.studio.core.FolderRef
import com.rodwave.studio.core.PickedFile
import com.rodwave.studio.core.Screen
import com.rodwave.studio.core.Studio
import com.rodwave.studio.ui.RodwaveApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.jetbrains.skia.EncodedImageFormat
import java.io.File
import java.nio.file.Files

/**
 * Renders every screen headlessly with sample projects, for reviews and the README.
 *
 * The data is real output of the engine (projects from templates, compiled scripts, a folder scan of
 * those scripts); there is no game on desktop, so the game shows as "not detected".
 */
object Screenshots {
    private data class Shot(val name: String, val screen: Screen, val widthDp: Int = 412, val heightDp: Int = 900, val prepare: (Studio) -> Unit = {})

    fun renderAll(out: File) {
        out.mkdirs()
        val home = Files.createTempDirectory("rodwave-shots").toFile()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val studio = Studio(DesktopPlatform(File(home, "storage")), scope)
        seed(studio, File(home, "device"))

        val shots = listOf(
            Shot("01-home", Screen.HOME),
            Shot("02-editor", Screen.EDITOR),
            Shot("03-compile", Screen.BUILD) { it.buildTab = 0 },
            Shot("04-inspect", Screen.BUILD) { it.buildTab = 1 },
            Shot("05-compatibility", Screen.COMPAT),
            Shot("06-game-directory", Screen.GAME_DIR),
            Shot("07-mods", Screen.MODS),
            Shot("08-opcodes", Screen.OPCODES),
            Shot("09-tools", Screen.TOOLS),
            Shot("10-docs", Screen.DOCS),
            Shot("11-console", Screen.CONSOLE),
            Shot("12-settings", Screen.SETTINGS),
            Shot("13-projects", Screen.PROJECTS),
            Shot("20-tablet-editor", Screen.EDITOR, widthDp = 1280, heightDp = 800),
        )
        for (shot in shots) {
            shot.prepare(studio)
            studio.screen = shot.screen
            val file = File(out, "${shot.name}.png")
            file.writeBytes(render(studio, shot.widthDp, shot.heightDp))
            println("Rendered ${file.path}")
        }
        scope.cancel()
        home.deleteRecursively()
    }

    private fun render(studio: Studio, widthDp: Int, heightDp: Int, density: Float = 2f): ByteArray {
        val scene = ImageComposeScene(
            width = (widthDp * density).toInt(),
            height = (heightDp * density).toInt(),
            density = Density(density),
        ) { RodwaveApp(studio) }
        try {
            var time = 0L
            fun frame() {
                Snapshot.sendApplyNotifications()
                scene.render(time)
                time += 16_000_000L
            }
            // Startup effects (game detection, folder scan) run as background tasks; let them finish.
            repeat(5) { frame(); Thread.sleep(30) }
            waitIdle(studio)
            studio.message?.let { studio.consumeMessage(it.id) }
            repeat(40) { frame() }
            Snapshot.sendApplyNotifications()
            return scene.render(time).encodeToData(EncodedImageFormat.PNG)?.bytes ?: error("PNG encoding failed")
        } finally {
            scene.close()
        }
    }

    /** Sample workspace: four template projects, two compiled scripts in a scanned folder and an imported mod. */
    private fun seed(studio: Studio, device: File) {
        studio.createProject("TouchSprint", Templates.TOUCH_TOGGLE)
        studio.createProject("HealMenu", Templates.HEAL)
        studio.createProject("CarSpawner", Templates.SPAWN_CAR)
        studio.createProject("VersionGuard", Templates.VERSION_CHECK)
        studio.refreshProjects()

        val compiler = ScriptCompiler(studio.database)
        val heal = compiler.compile(Templates.HEAL.source("HealMenu")).bytes ?: error("template failed to compile")
        val sprint = compiler.compile(Templates.TOUCH_TOGGLE.source("TouchSprint")).bytes ?: error("template failed to compile")
        val cleo = File(device, "AMLMods/com.rockstargames.gtasa/cleo").apply { mkdirs() }
        File(cleo, "heal.csi").writeBytes(heal)
        File(cleo, "sprint.csa").writeBytes(sprint)
        val export = File(device, "Download/Rodwave").apply { mkdirs() }

        studio.updateSettings {
            it.copy(
                folders = mapOf(
                    FolderPurpose.CLEO_SCRIPTS.name to FolderRef(cleo.absolutePath, "AMLMods/com.rockstargames.gtasa/cleo"),
                    FolderPurpose.EXPORT.name to FolderRef(export.absolutePath, "Download/Rodwave"),
                ),
            )
        }
        studio.scanFolders()
        waitIdle(studio)
        studio.importMod(PickedFile("heal.csi", heal))
        waitIdle(studio)
        studio.inspectFile(PickedFile("sprint.csa", sprint))
        waitIdle(studio)

        // Open the touch toggle in the editor with diagnostics, the caret on a command.
        val project = studio.projectList.first { it.name == "TouchSprint" }
        val doc = studio.editor.openProjectFile(project, "main.txt")
        studio.editor.refreshDiagnostics(doc)
        val at = doc.text.indexOf("get_touch_point_state") + 4
        studio.editor.select(doc, at)
    }

    private fun waitIdle(studio: Studio) {
        val deadline = System.currentTimeMillis() + 20_000
        Thread.sleep(50)
        while (studio.busy != null && System.currentTimeMillis() < deadline) Thread.sleep(20)
    }
}
