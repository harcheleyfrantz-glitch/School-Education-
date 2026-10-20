package com.rodwave.studio.core

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.rodwave.engine.analysis.ScriptAnalyzer
import com.rodwave.engine.analysis.ScriptReport
import com.rodwave.engine.archive.ArchiveFile
import com.rodwave.engine.archive.SafeZip
import com.rodwave.engine.compat.CompatibilityEvaluator
import com.rodwave.engine.compat.CompatibilityReport
import com.rodwave.engine.compat.ComponentState
import com.rodwave.engine.compat.ComponentStatus
import com.rodwave.engine.compat.GameDirectoryScanner
import com.rodwave.engine.compat.InstalledGame
import com.rodwave.engine.compat.ScanResult
import com.rodwave.engine.compiler.CompileOptions
import com.rodwave.engine.compiler.CompileResult
import com.rodwave.engine.compiler.ScriptCompiler
import com.rodwave.engine.decompiler.DecompileOptions
import com.rodwave.engine.decompiler.DecompileResult
import com.rodwave.engine.decompiler.MainScmDecompileResult
import com.rodwave.engine.decompiler.ScriptDecompiler
import com.rodwave.engine.fs.VirtualFile
import com.rodwave.engine.fs.ensureDirectory
import com.rodwave.engine.fs.readText
import com.rodwave.engine.fs.resolve
import com.rodwave.engine.fs.writeFile
import com.rodwave.engine.mods.DestinationKind
import com.rodwave.engine.mods.ImportResult
import com.rodwave.engine.mods.InstallPlan
import com.rodwave.engine.mods.InstallPlanner
import com.rodwave.engine.mods.ManagedMod
import com.rodwave.engine.mods.ModImporter
import com.rodwave.engine.mods.ModInstaller
import com.rodwave.engine.mods.ModStore
import com.rodwave.engine.mods.OperationRecord
import com.rodwave.engine.mods.OperationResult
import com.rodwave.engine.mods.PlanContext
import com.rodwave.engine.opcode.OpcodeDatabase
import com.rodwave.engine.opcode.SannyLibraryImporter
import com.rodwave.engine.project.Project
import com.rodwave.engine.project.ProjectManager
import com.rodwave.engine.project.ProjectTemplate
import com.rodwave.engine.project.RestorePlan
import com.rodwave.engine.project.WorkspaceArchiver
import com.rodwave.engine.scm.MainScmParser
import com.rodwave.engine.scm.ScriptFormat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

enum class Screen(val title: String) {
    HOME("Home"),
    PROJECTS("Projects"),
    EDITOR("Editor"),
    BUILD("Compiler & Decompiler"),
    COMPAT("Compatibility Center"),
    GAME_DIR("Game Directory"),
    MODS("Mod Manager"),
    OPCODES("Opcode Explorer"),
    TOOLS("Tools"),
    DOCS("Documentation"),
    CONSOLE("Console"),
    SETTINGS("Settings"),
}

data class UserMessage(val id: Long, val text: String, val isError: Boolean = false)

/** Result of opening a binary script in the Compiler & Decompiler screen. */
class InspectedFile(
    val name: String,
    val bytes: ByteArray,
    val report: ScriptReport,
    val decompiled: DecompileResult?,
    val mainScm: MainScmDecompileResult?,
) {
    val size: Int get() = bytes.size
}

/** One file of a batch compile or project validation run. */
data class BatchEntry(
    val file: String,
    /** Name of the written binary, or null when nothing was written. */
    val output: String?,
    val result: CompileResult,
    /** Static analysis of the compiled bytes. */
    val report: ScriptReport?,
    /** Paths named by {$INCLUDE} directives, with whether the project contains them. */
    val includes: List<Pair<String, Boolean>> = emptyList(),
)

private val INCLUDE_DIRECTIVE = Regex("\\{\\$(?:INCLUDE|I)\\s+([^}]+)}", RegexOption.IGNORE_CASE)

/**
 * Application state and actions shared by every screen. Created once per process by the platform
 * entry point with a main-thread [scope].
 */
class Studio(val platform: PlatformServices, val scope: CoroutineScope) {
    val storage: VirtualFile = platform.appStorage
    private val settingsStore = SettingsStore(storage)

    var settings by mutableStateOf(settingsStore.load())
        private set

    val console = ConsoleLog(storage)
    private val library = OpcodeLibrary(storage)
    var libraryState by mutableStateOf(library.load(settings.useImportedLibrary))
        private set
    val database: OpcodeDatabase get() = libraryState.database

    val projects = ProjectManager(storage.ensureDirectory("projects"))
    var projectList by mutableStateOf<List<Project>>(emptyList())
        private set
    val editor = EditorWorkspace(this)

    var installedGame by mutableStateOf<InstalledGame?>(null)
        private set
    var scans by mutableStateOf<Map<FolderPurpose, ScanResult>>(emptyMap())
        private set
    var statuses by mutableStateOf<List<ComponentStatus>>(CompatibilityEvaluator.evaluate(null, null))
        private set
    var lastScanTime by mutableStateOf<Long?>(null)
        private set

    val modStore = ModStore(storage.ensureDirectory("mods"))
    var mods by mutableStateOf<List<ManagedMod>>(emptyList())
        private set
    var operations by mutableStateOf<List<OperationRecord>>(emptyList())
        private set

    var inspected by mutableStateOf<InspectedFile?>(null)

    /** Selected pane of the Compiler & Decompiler screen (0 = compile, 1 = decompile). */
    var buildTab by mutableStateOf(0)

    var screen by mutableStateOf(Screen.HOME)
    private val backStack = ArrayDeque<Screen>()

    /** True when [back] has somewhere to go; the system back gesture leaves the app otherwise. */
    var canGoBack by mutableStateOf(false)
        private set

    /** Label of a running background task, or null when idle. */
    var busy by mutableStateOf<String?>(null)
        private set
    private val runningTasks = mutableListOf<String>()
    var message by mutableStateOf<UserMessage?>(null)
        private set
    private var messageCounter = 0L

    init {
        refreshProjects()
        refreshMods()
        editor.scanRecovery()
        console.info("app", "Rodwave started on ${platform.platformName}; ${libraryState.message}")
    }

    // ------------------------------------------------------------------ navigation and messages

    fun navigate(target: Screen) {
        if (target == screen) return
        backStack.addLast(screen)
        if (backStack.size > 30) backStack.removeFirst()
        screen = target
        canGoBack = true
    }

    /** Returns false when there is nothing to go back to. */
    fun back(): Boolean {
        val previous = backStack.removeLastOrNull() ?: return false
        screen = previous
        canGoBack = backStack.isNotEmpty()
        return true
    }

    fun notify(text: String, isError: Boolean = false) {
        message = UserMessage(++messageCounter, text, isError)
    }

    fun consumeMessage(id: Long) {
        if (message?.id == id) message = null
    }

    /** Runs [block] off the main thread with a progress label; errors are logged and reported. */
    fun runTask(label: String, source: String, block: suspend () -> Unit) {
        scope.launch {
            synchronized(runningTasks) { runningTasks += label }
            busy = label
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                console.error(source, "$label failed: ${e.message ?: e.javaClass.simpleName}")
                notify("$label failed: ${e.message ?: e.javaClass.simpleName}", isError = true)
            } finally {
                // Several tasks can overlap (e.g. game detection and a folder scan at startup).
                busy = synchronized(runningTasks) {
                    runningTasks.remove(label)
                    runningTasks.lastOrNull()
                }
            }
        }
    }

    private suspend fun <T> io(block: () -> T): T = withContext(Dispatchers.IO) { block() }

    // ------------------------------------------------------------------ settings

    fun updateSettings(transform: (StudioSettings) -> StudioSettings) {
        settings = transform(settings)
        runCatching { settingsStore.save(settings) }.onFailure { console.error("settings", "Could not save settings: ${it.message}") }
    }

    // ------------------------------------------------------------------ opcode library

    fun reloadLibrary() {
        libraryState = library.load(settings.useImportedLibrary)
        console.info("library", libraryState.message)
    }

    fun setUseImportedLibrary(enabled: Boolean) {
        updateSettings { it.copy(useImportedLibrary = enabled) }
        reloadLibrary()
    }

    fun importLibraryFile(file: PickedFile) = runTask("Importing opcode library", "library") {
        val parsed = io { library.install(file.bytes.toString(Charsets.UTF_8), null) }
        reloadLibrary()
        console.success("library", "Imported ${parsed.info.name} ${parsed.info.version} (${parsed.size} commands, ${parsed.info.importWarnings.size} warnings)")
        notify("Opcode library imported: ${parsed.size} commands")
    }

    fun importEnumsFile(file: PickedFile) = runTask("Importing enums", "library") {
        val parsed = io { library.installEnums(file.bytes.toString(Charsets.UTF_8)) }
        reloadLibrary()
        console.success("library", "Imported ${parsed.enums.size} enums")
        notify("Imported ${parsed.enums.size} enums")
    }

    /** Downloads the library from the official Sanny Builder Library repository (user confirmed). */
    fun downloadLibrary() = runTask("Downloading opcode library", "library") {
        val commands = io { platform.downloadText(SannyLibraryImporter.SA_MOBILE_JSON_URL, SannyLibraryImporter.MAX_LIBRARY_BYTES) }
        val enums = io { runCatching { platform.downloadText(SannyLibraryImporter.SA_MOBILE_ENUMS_URL, 4 * 1024 * 1024) }.getOrNull() }
        val parsed = io { library.install(commands, enums) }
        reloadLibrary()
        console.success("library", "Downloaded ${parsed.info.name} ${parsed.info.version}: ${parsed.size} commands")
        notify("Downloaded ${parsed.size} commands")
    }

    fun removeLibrary() {
        library.remove()
        reloadLibrary()
        notify("Imported library removed; using the built-in core set")
    }

    // ------------------------------------------------------------------ projects

    fun refreshProjects() {
        projectList = runCatching { projects.list() }.getOrElse {
            console.error("projects", "Could not list projects: ${it.message}")
            emptyList()
        }
    }

    fun createProject(name: String, template: ProjectTemplate): Project? = try {
        val p = projects.create(name, template)
        refreshProjects()
        console.success("projects", "Created project '${p.name}' from template '${template.title}'")
        editor.openProjectFile(projectList.first { it.name == p.name }, p.manifest.mainFile)
        navigate(Screen.EDITOR)
        p
    } catch (e: Exception) {
        notify(e.message ?: "Could not create the project", isError = true)
        null
    }

    fun openProject(project: Project) {
        val main = project.sourceFiles().firstOrNull() ?: return notify("The project has no source files", isError = true)
        editor.openProjectFile(project, main.name)
        navigate(Screen.EDITOR)
    }

    fun deleteProject(project: Project) {
        editor.documents.filter { (it.source as? DocumentSource.ProjectFile)?.projectName == project.name }.forEach(editor::close)
        if (projects.delete(project)) console.info("projects", "Deleted project '${project.name}'")
        refreshProjects()
    }

    fun renameProject(project: Project, newName: String) {
        try {
            projects.rename(project, newName)
            refreshProjects()
        } catch (e: Exception) {
            notify(e.message ?: "Rename failed", isError = true)
        }
    }

    // ------------------------------------------------------------------ compile and decompile

    /** Compiles the document; on success the binary is written next to the source in its project. */
    fun compileDocument(doc: EditorDocument, onDone: (CompileResult) -> Unit = {}) = runTask("Compiling ${doc.title}", "compiler") {
        val result = io { editor.compile(doc) }
        val bytes = result.bytes
        if (bytes != null) {
            val outName = doc.title.substringBeforeLast('.') + "." + result.format.extension
            editor.projectOf(doc)?.let { project -> io { project.directory.writeFile(outName, bytes) } }
            console.success("compiler", "${doc.title}: ${bytes.size} bytes, ${result.instructionCount} instructions, ${result.warnings.size} warning(s) -> $outName")
        } else {
            console.error("compiler", "${doc.title}: ${result.errors.size} error(s); first: ${result.errors.firstOrNull()?.render()}")
        }
        onDone(result)
    }

    /**
     * Compiles every script of [project]: the main file plus any file with a {$CLEO} directive (other
     * files are treated as includes). With [write] the binaries are saved next to their sources.
     */
    fun batchCompile(project: Project, write: Boolean, onDone: (List<BatchEntry>) -> Unit) =
        runTask(if (write) "Compiling ${project.name}" else "Validating ${project.name}", "compiler") {
            editor.saveAll()
            val entries = io {
                val compiler = ScriptCompiler(database)
                project.sourceFiles()
                    .filter { it.name.substringAfterLast('.').lowercase() in setOf("txt", "sb") }
                    .mapNotNull { f ->
                        val text = f.readText()
                        if (f.name != project.manifest.mainFile && !text.contains("{\$CLEO", ignoreCase = true)) return@mapNotNull null
                        val result = compiler.compile(text, CompileOptions(format = project.format, fileName = f.name, includeResolver = projectIncludeResolver(project)))
                        val bytes = result.bytes
                        val outName = f.name.substringBeforeLast('.') + "." + result.format.extension
                        if (write && bytes != null) project.directory.writeFile(outName, bytes)
                        BatchEntry(
                            file = f.name,
                            output = if (write && bytes != null) outName else null,
                            result = result,
                            report = bytes?.let { ScriptAnalyzer.analyze(it, outName, database) },
                            includes = INCLUDE_DIRECTIVE.findAll(text).map { m ->
                                val path = m.groupValues[1].trim().trim('"', '\'')
                                path to (project.directory.resolve(path)?.isFile == true)
                            }.toList(),
                        )
                    }
            }
            val failed = entries.count { !it.result.success }
            val verb = if (write) "compiled" else "validated"
            if (failed == 0) console.success("compiler", "${project.name}: ${entries.size} script(s) $verb") else console.error("compiler", "${project.name}: $failed of ${entries.size} script(s) failed")
            entries.filter { !it.result.success }.forEach { e -> e.result.errors.take(5).forEach { console.error("compiler", it.render()) } }
            onDone(entries)
        }

    fun exportBytes(name: String, bytes: ByteArray) {
        platform.saveDocument(name, "application/octet-stream", bytes) { ok, where ->
            if (ok) {
                console.success("export", "Saved $name${where?.let { " to $it" } ?: ""}")
                notify("Saved $name")
            } else {
                console.warning("export", "Export of $name was cancelled or failed")
            }
        }
    }

    /** Writes a compiled script into the configured export folder. */
    fun exportToFolder(name: String, bytes: ByteArray): Boolean {
        val folder = folder(FolderPurpose.EXPORT) ?: return false.also { notify("Choose an export folder in Game Directory first", isError = true) }
        return try {
            folder.writeFile(name, bytes)
            console.success("export", "Wrote $name to ${folder.name}")
            notify("Exported $name to ${folder.name}")
            true
        } catch (e: Exception) {
            console.error("export", "Writing $name failed: ${e.message}")
            notify("Export failed: ${e.message}", isError = true)
            false
        }
    }

    fun inspectFile(file: PickedFile) = runTask("Analysing ${file.name}", "decompiler") {
        buildTab = 1
        val result = io {
            val report = ScriptAnalyzer.analyze(file.bytes, file.name, database)
            val isMain = MainScmParser.looksLikeMainScm(file.bytes)
            val format = ScriptFormat.fromFileName(file.name)?.takeIf { it != ScriptFormat.MAIN_SCM } ?: ScriptFormat.CLEO_ANDROID_AUTO
            val decompiler = ScriptDecompiler(database)
            InspectedFile(
                name = file.name,
                bytes = file.bytes,
                report = report,
                decompiled = if (!isMain && report.verdict != com.rodwave.engine.analysis.ScriptVerdict.NOT_A_SCRIPT) {
                    decompiler.decompile(file.bytes, DecompileOptions(format = format, sourceName = file.name))
                } else {
                    null
                },
                mainScm = if (isMain) decompiler.decompileMainScm(file.bytes, file.name) else null,
            )
        }
        inspected = result
        console.info("decompiler", "${file.name}: ${result.report.verdict.label}; round trip ${result.decompiled?.roundTrip ?: "n/a"}")
    }

    fun openDecompiledInEditor(file: InspectedFile) {
        val text = file.decompiled?.text ?: file.mainScm?.text ?: return
        val readOnly = file.mainScm != null
        val format = ScriptFormat.fromFileName(file.name)?.takeIf { it != ScriptFormat.MAIN_SCM } ?: ScriptFormat.CLEO_ANDROID_AUTO
        editor.openText(file.name.substringBeforeLast('.') + if (readOnly) ".listing.txt" else ".txt", text, readOnly, format)
        navigate(Screen.EDITOR)
    }

    /** Copies a scratch document into a project as a new source file. */
    fun saveScratchToProject(doc: EditorDocument, project: Project, fileName: String) {
        try {
            projects.createFile(project, fileName, doc.text)
            refreshProjects()
            editor.close(doc)
            editor.openProjectFile(projectList.first { it.name == project.name }, fileName)
            notify("Saved as ${project.name}/$fileName")
        } catch (e: Exception) {
            notify(e.message ?: "Could not save", isError = true)
        }
    }

    // ------------------------------------------------------------------ game directory and compatibility

    fun folder(purpose: FolderPurpose): VirtualFile? = settings.folder(purpose)?.let { runCatching { platform.openFolder(it) }.getOrNull() }

    fun chooseFolder(purpose: FolderPurpose) {
        platform.pickFolder(purpose) { ref ->
            if (ref == null) return@pickFolder
            val previous = settings.folder(purpose)
            updateSettings { it.copy(folders = it.folders + (purpose.name to ref)) }
            if (previous != null && previous.uri != ref.uri) releaseIfUnused(previous)
            console.info("folders", "${purpose.title} set to ${ref.displayName}")
            scanFolders()
        }
    }

    fun forgetFolder(purpose: FolderPurpose) {
        val ref = settings.folder(purpose) ?: return
        updateSettings { it.copy(folders = it.folders - purpose.name) }
        releaseIfUnused(ref)
        scans = scans - purpose
        console.info("folders", "Forgot ${purpose.title} (${ref.displayName})")
        reevaluate()
    }

    /** Gives the access permission back, unless another purpose still uses the same folder. */
    private fun releaseIfUnused(ref: FolderRef) {
        if (settings.folders.values.none { it.uri == ref.uri }) runCatching { platform.releaseFolder(ref) }
    }

    fun destinations(): Map<DestinationKind, VirtualFile> = buildMap {
        folder(FolderPurpose.CLEO_SCRIPTS)?.let { put(DestinationKind.CLEO_SCRIPTS, it) }
        folder(FolderPurpose.AML_MODS)?.let { put(DestinationKind.AML_MODS, it) }
        folder(FolderPurpose.EXPORT)?.let { put(DestinationKind.EXPORT, it) }
        folder(FolderPurpose.GAME_DATA)?.child("configs")?.takeIf { it.isDirectory }?.let { put(DestinationKind.AML_CONFIGS, it) }
    }

    fun detectGame() = runTask("Checking the installed game", "compat") {
        installedGame = io { platform.installedGame() }
        val g = installedGame
        if (g == null) {
            console.info("compat", "GTA SA package is not installed or not visible")
        } else {
            console.info("compat", "Found ${g.packageName} ${g.versionName} (${g.abis.joinToString { it.androidName }}), APK readable: ${g.apkReadable}")
        }
        reevaluate()
    }

    /** Scans every configured folder and re-evaluates compatibility. */
    fun scanFolders() = runTask("Scanning folders", "compat") {
        if (installedGame == null) installedGame = io { platform.installedGame() }
        val result = io {
            FolderPurpose.entries.mapNotNull { purpose ->
                val dir = folder(purpose) ?: return@mapNotNull null
                purpose to GameDirectoryScanner(database).scan(dir)
            }.toMap()
        }
        scans = result
        lastScanTime = System.currentTimeMillis()
        result.forEach { (p, s) -> console.info("compat", "${p.title}: ${s.filesScanned} files, ${s.scripts.size} scripts, ${s.nativeMods.size} native libraries — ${s.location.label}") }
        reevaluate()
        notify("Scan finished")
    }

    private fun reevaluate() {
        statuses = CompatibilityEvaluator.evaluate(mergedScan(), installedGame)
    }

    fun mergedScan(): ScanResult? = mergeScans(scans.values.toList())

    fun reportText(): String = CompatibilityReport.render(
        statuses, mergedScan(), installedGame, platform.deviceInfo,
        SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(Date()),
    )

    fun status(id: String): ComponentStatus? = statuses.firstOrNull { it.profile.id == id }

    private fun detected(id: String) = status(id)?.state in setOf(ComponentState.COMPATIBLE, ComponentState.PARTIALLY_COMPATIBLE, ComponentState.INSTALLED_UNVERIFIED)

    // ------------------------------------------------------------------ mods

    fun refreshMods() {
        mods = runCatching { modStore.mods() }.getOrDefault(emptyList())
        operations = runCatching { modStore.operations() }.getOrDefault(emptyList())
    }

    fun importMod(file: PickedFile, onDone: (ImportResult) -> Unit = {}) = runTask("Importing ${file.name}", "mods") {
        val result = io { ModImporter(modStore, database).import(file.name, file.bytes) }
        refreshMods()
        result.messages.forEach { console.info("mods", it) }
        val mod = result.mod
        if (mod != null) notify("Imported ${mod.name}") else notify(result.messages.firstOrNull() ?: "Import failed", isError = true)
        onDone(result)
    }

    /** Imports compiled bytes (e.g. from the editor) as a managed mod. */
    fun importCompiled(name: String, bytes: ByteArray, onDone: (ImportResult) -> Unit) =
        importMod(PickedFile(name, bytes), onDone)

    fun planContext() = PlanContext(
        game = installedGame,
        amlDetected = detected("aml"),
        cleoLoaderDetected = detected("cleo-aml") || detected("cleo-android"),
    )

    suspend fun planInstall(mod: ManagedMod): InstallPlan = io { InstallPlanner(modStore).planInstall(mod, destinations(), planContext()) }

    suspend fun planUninstall(mod: ManagedMod): InstallPlan = io { InstallPlanner(modStore).planUninstall(mod, destinations()) }

    fun applyPlan(plan: InstallPlan, confirmed: Boolean, onDone: (OperationResult) -> Unit = {}) = runTask("Applying changes", "mods") {
        val result = io { ModInstaller(modStore).apply(plan, destinations(), confirmed) }
        result.record?.steps?.forEach { console.info("mods", it) }
        if (result.success) console.success("mods", result.message) else console.error("mods", result.message)
        notify(result.message, isError = !result.success)
        refreshMods()
        onDone(result)
    }

    fun restoreOperation(id: String) = runTask("Restoring backups", "mods") {
        val result = io { ModInstaller(modStore).restoreOperation(id, destinations()) }
        if (result.success) console.success("mods", result.message) else console.error("mods", result.message)
        notify(result.message, isError = !result.success)
        refreshMods()
    }

    fun updateMod(mod: ManagedMod) {
        runCatching { modStore.saveMod(mod) }.onFailure { notify("Could not save '${mod.name}': ${it.message}", isError = true) }
        refreshMods()
    }

    /** Saves a copy of the mod's files: the file itself for single-file mods, otherwise a ZIP. */
    fun exportMod(mod: ManagedMod) = runTask("Exporting ${mod.name}", "mods") {
        val files = io { mod.files.map { ArchiveFile(it.targetPath, modStore.readLibraryFile(mod, it)) } }
        if (files.size == 1) {
            val f = files.first()
            platform.saveDocument(f.path.substringAfterLast('/'), "application/octet-stream", f.data) { ok, _ -> if (ok) console.success("mods", "Exported ${f.path}") }
        } else {
            val zip = io { java.io.ByteArrayOutputStream().also { SafeZip.write(it, files) }.toByteArray() }
            val name = mod.name.filter { it.isLetterOrDigit() || it in " _.-" }.ifBlank { "mod" } + ".zip"
            platform.saveDocument(name, "application/zip", zip) { ok, _ -> if (ok) console.success("mods", "Exported ${mod.name} as $name (${files.size} files)") }
        }
    }

    fun removeMod(mod: ManagedMod) {
        if (mod.enabled) return notify("Disable '${mod.name}' before removing it", isError = true)
        modStore.deleteMod(mod.id)
        console.info("mods", "Removed '${mod.name}' from the library")
        refreshMods()
    }

    // ------------------------------------------------------------------ backups

    fun exportWorkspace() = runTask("Creating workspace backup", "backup") {
        val zip = io { WorkspaceArchiver.export(storage.ensureDirectory("projects")) }
        val name = "rodwave-workspace-" + SimpleDateFormat("yyyyMMdd-HHmm", Locale.US).format(Date()) + ".zip"
        platform.saveDocument(name, "application/zip", zip) { ok, _ ->
            if (ok) console.success("backup", "Workspace backup saved as $name (${zip.size} bytes)")
        }
    }

    /** Dry run of a workspace restore: which files are new and which already exist. */
    fun planWorkspaceRestore(file: PickedFile, onPlan: (RestorePlan) -> Unit) = runTask("Reading ${file.name}", "backup") {
        val plan = io { WorkspaceArchiver.planRestore(file.bytes, storage.ensureDirectory("projects")) }
        if (plan.files.isEmpty()) {
            notify("${file.name} contains no Rodwave projects", isError = true)
        } else {
            onPlan(plan)
        }
    }

    fun restoreWorkspace(plan: RestorePlan, overwrite: Boolean) = runTask("Restoring workspace", "backup") {
        val root = storage.ensureDirectory("projects")
        val written = io { WorkspaceArchiver.restore(plan, root, overwrite) }
        plan.rejected.forEach { console.warning("backup", "Rejected $it") }
        console.success("backup", "Restored $written file(s); ${plan.conflicts.size} existing file(s) ${if (overwrite) "replaced" else "kept"}")
        refreshProjects()
        notify("Restored $written file(s)")
    }

    // ------------------------------------------------------------------ lifecycle

    fun onBackground() {
        editor.writeRecovery()
        console.flush()
    }

    fun readSource(project: Project, name: String): String? = project.directory.child(name)?.readText()
}

/** Combines scans of several folders into one evidence set. */
fun mergeScans(scans: List<ScanResult>): ScanResult? {
    if (scans.isEmpty()) return null
    if (scans.size == 1) return scans.first()
    val primary = scans.firstOrNull { it.location == com.rodwave.engine.compat.LocationKind.GAME_DATA_FOLDER } ?: scans.first()
    return primary.copy(
        locationEvidence = scans.flatMap { it.locationEvidence },
        saveFiles = scans.flatMap { it.saveFiles },
        scripts = scans.flatMap { it.scripts },
        fxtFiles = scans.flatMap { it.fxtFiles },
        pcScripts = scans.flatMap { it.pcScripts },
        mainScmFiles = scans.flatMap { it.mainScmFiles },
        nativeMods = scans.flatMap { it.nativeMods }.distinctBy { it.path to it.info.size },
        configFiles = scans.flatMap { it.configFiles }.distinct(),
        amlCore = scans.firstNotNullOfOrNull { it.amlCore },
        notableFiles = scans.flatMap { it.notableFiles },
        filesScanned = scans.sumOf { it.filesScanned },
        truncated = scans.any { it.truncated },
        errors = scans.flatMap { it.errors },
    )
}
