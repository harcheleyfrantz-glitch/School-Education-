@file:OptIn(ExperimentalMaterial3Api::class)

package com.rodwave.studio.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.Build
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Extension
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.Handyman
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Menu
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material.icons.outlined.Widgets
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.rodwave.studio.core.Screen
import com.rodwave.studio.core.Studio
import com.rodwave.studio.ui.icon.RodwaveLogo
import com.rodwave.studio.ui.screens.BuildScreen
import com.rodwave.studio.ui.screens.CompatibilityScreen
import com.rodwave.studio.ui.screens.ConsoleScreen
import com.rodwave.studio.ui.screens.DocsScreen
import com.rodwave.studio.ui.screens.EditorScreen
import com.rodwave.studio.ui.screens.GameDirectoryScreen
import com.rodwave.studio.ui.screens.HomeScreen
import com.rodwave.studio.ui.screens.ModManagerScreen
import com.rodwave.studio.ui.screens.OpcodeExplorerScreen
import com.rodwave.studio.ui.screens.ProjectsScreen
import com.rodwave.studio.ui.screens.SettingsScreen
import com.rodwave.studio.ui.screens.ToolsScreen
import com.rodwave.studio.ui.theme.RodwaveTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

fun Screen.icon(): ImageVector = when (this) {
    Screen.HOME -> Icons.Outlined.Home
    Screen.PROJECTS -> Icons.Outlined.FolderOpen
    Screen.EDITOR -> Icons.Outlined.Code
    Screen.BUILD -> Icons.Outlined.Build
    Screen.COMPAT -> Icons.Outlined.VerifiedUser
    Screen.GAME_DIR -> Icons.Outlined.Widgets
    Screen.MODS -> Icons.Outlined.Extension
    Screen.OPCODES -> Icons.Outlined.Search
    Screen.TOOLS -> Icons.Outlined.Handyman
    Screen.DOCS -> Icons.AutoMirrored.Outlined.MenuBook
    Screen.CONSOLE -> Icons.Outlined.Terminal
    Screen.SETTINGS -> Icons.Outlined.Settings
}

private val BOTTOM_ITEMS = listOf(Screen.HOME, Screen.EDITOR, Screen.COMPAT, Screen.MODS)

/** True when the window is wide enough for a navigation rail. */
val LocalWideLayout = staticCompositionLocalOf { false }

/** Opens the navigation drawer on compact layouts. */
val LocalOpenDrawer = staticCompositionLocalOf<() -> Unit> { {} }

@Composable
fun RodwaveApp(studio: Studio) {
    RodwaveTheme(studio.settings.theme) {
        val snackbar = remember { SnackbarHostState() }
        val message = studio.message
        LaunchedEffect(message?.id) {
            if (message != null) {
                snackbar.showSnackbar(message.text, withDismissAction = true)
                studio.consumeMessage(message.id)
            }
        }
        LaunchedEffect(Unit) {
            studio.detectGame()
            if (studio.settings.folders.isNotEmpty()) studio.scanFolders()
        }
        // Autosave project files and keep recovery snapshots of everything else.
        LaunchedEffect(studio.settings.autosaveSeconds) {
            while (true) {
                delay(maxOf(5, studio.settings.autosaveSeconds).toLong() * 1000)
                if (studio.settings.autosaveSeconds > 0) {
                    val saved = studio.editor.saveAll()
                    if (saved > 0) studio.console.info("editor", "Autosaved $saved file(s)")
                }
                studio.editor.writeRecovery()
                studio.console.flush()
            }
        }

        BoxWithConstraints(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
            val wide = maxWidth >= 600.dp
            val drawerState = rememberDrawerState(DrawerValue.Closed)
            val scope = rememberCoroutineScope()
            val openDrawer: () -> Unit = { scope.launch { drawerState.open() } }
            CompositionLocalProvider(LocalWideLayout provides wide, LocalOpenDrawer provides openDrawer) {
                ModalNavigationDrawer(
                    drawerState = drawerState,
                    gesturesEnabled = !wide && drawerState.isOpen,
                    drawerContent = {
                        ModalDrawerSheet(drawerContainerColor = MaterialTheme.colorScheme.surfaceContainerLow) {
                            DrawerContent(studio) { target ->
                                scope.launch { drawerState.close() }
                                studio.navigate(target)
                            }
                        }
                    },
                ) {
                    Row(Modifier.fillMaxSize().safeDrawingPadding()) {
                        if (wide) Rail(studio)
                        Column(Modifier.weight(1f).fillMaxHeight()) {
                            if (studio.busy != null) {
                                LinearProgressIndicator(Modifier.fillMaxWidth())
                            }
                            Box(Modifier.weight(1f)) { ScreenContent(studio) }
                            // The editor needs every row on a phone; its top bar opens the drawer instead.
                            if (!wide && studio.screen != Screen.EDITOR) BottomBar(studio, openDrawer)
                        }
                    }
                }
            }
            SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter).safeDrawingPadding().padding(bottom = 80.dp)) { data ->
                Snackbar(data, containerColor = MaterialTheme.colorScheme.surfaceContainerHighest, contentColor = MaterialTheme.colorScheme.onSurface)
            }
            RecoveryPrompt(studio)
        }
    }
}

@Composable
private fun ScreenContent(studio: Studio) {
    when (studio.screen) {
        Screen.HOME -> HomeScreen(studio)
        Screen.PROJECTS -> ProjectsScreen(studio)
        Screen.EDITOR -> EditorScreen(studio)
        Screen.BUILD -> BuildScreen(studio)
        Screen.COMPAT -> CompatibilityScreen(studio)
        Screen.GAME_DIR -> GameDirectoryScreen(studio)
        Screen.MODS -> ModManagerScreen(studio)
        Screen.OPCODES -> OpcodeExplorerScreen(studio)
        Screen.TOOLS -> ToolsScreen(studio)
        Screen.DOCS -> DocsScreen(studio)
        Screen.CONSOLE -> ConsoleScreen(studio)
        Screen.SETTINGS -> SettingsScreen(studio)
    }
}

@Composable
private fun BottomBar(studio: Studio, openDrawer: () -> Unit) {
    NavigationBar(containerColor = MaterialTheme.colorScheme.surfaceContainerLow, tonalElevation = 0.dp) {
        BOTTOM_ITEMS.forEach { s ->
            NavigationBarItem(
                selected = studio.screen == s,
                onClick = { studio.navigate(s) },
                icon = { Icon(s.icon(), null) },
                label = { Text(if (s == Screen.COMPAT) "Compat" else s.title, maxLines = 1) },
            )
        }
        NavigationBarItem(
            selected = studio.screen !in BOTTOM_ITEMS,
            onClick = openDrawer,
            icon = { Icon(Icons.Outlined.Menu, null) },
            label = { Text("More") },
        )
    }
}

@Composable
private fun Rail(studio: Studio) {
    NavigationRail(
        containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        header = { RodwaveLogo(size = 40.dp, modifier = Modifier.padding(top = 8.dp)) },
    ) {
        Column(Modifier.verticalScroll(rememberScrollState())) {
            Screen.entries.forEach { s ->
                NavigationRailItem(
                    selected = studio.screen == s,
                    onClick = { studio.navigate(s) },
                    icon = { Icon(s.icon(), null) },
                    label = { Text(s.title.substringBefore(' '), maxLines = 1) },
                )
            }
        }
    }
}

@Composable
private fun ColumnScope.DrawerContent(studio: Studio, onSelect: (Screen) -> Unit) {
    Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
        RodwaveLogo(size = 44.dp)
        Spacer(Modifier.width(14.dp))
        Column {
            Text("Rodwave", style = MaterialTheme.typography.titleLarge)
            Text("Sanny Builder for mobile", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    HorizontalDivider()
    Column(Modifier.verticalScroll(rememberScrollState()).padding(12.dp)) {
        Screen.entries.forEach { s ->
            NavigationDrawerItem(
                label = { Text(s.title) },
                icon = { Icon(s.icon(), null) },
                selected = studio.screen == s,
                onClick = { onSelect(s) },
            )
        }
    }
}

@Composable
private fun RecoveryPrompt(studio: Studio) {
    val items = studio.editor.recoverable
    if (items.isEmpty()) return
    com.rodwave.studio.ui.components.ConfirmDialog(
        title = "Recover unsaved work?",
        message = "Rodwave was closed with unsaved changes in: ${items.joinToString { it.second }}.",
        confirmLabel = "Restore",
        onConfirm = {
            studio.editor.restoreRecovered()
            studio.navigate(Screen.EDITOR)
        },
        onDismiss = { studio.editor.discardRecovered() },
    )
}

/** Top bar used by every screen: menu (compact) or back, title and actions. */
@Composable
fun ScreenTopBar(
    studio: Studio,
    title: String,
    subtitle: String? = null,
    showBack: Boolean = false,
    actions: @Composable RowScope.() -> Unit = {},
) {
    val wide = LocalWideLayout.current
    val openDrawer = LocalOpenDrawer.current
    TopAppBar(
        title = {
            Column {
                Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleLarge)
                if (subtitle != null) {
                    Text(subtitle, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        },
        navigationIcon = {
            when {
                showBack -> IconButton(onClick = { studio.back() }) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "Back") }
                !wide -> IconButton(onClick = openDrawer) { Icon(Icons.Outlined.Menu, "Menu") }
            }
        },
        actions = actions,
        colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
    )
}

/** Standard screen frame: top bar plus content area. */
@Composable
fun ScreenFrame(
    studio: Studio,
    title: String,
    subtitle: String? = null,
    actions: @Composable RowScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        ScreenTopBar(studio, title, subtitle, actions = actions)
        content()
    }
}

@Composable
fun SmallTextButton(text: String, onClick: () -> Unit, enabled: Boolean = true) {
    TextButton(onClick = onClick, enabled = enabled) { Text(text) }
}

@Composable
fun VerticalSpace(h: Int) = Spacer(Modifier.height(h.dp))
