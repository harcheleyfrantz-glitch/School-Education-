package com.rodwave.engine.project

import com.rodwave.engine.fs.FsException
import com.rodwave.engine.fs.VirtualFile
import com.rodwave.engine.fs.readText
import com.rodwave.engine.fs.writeFile
import com.rodwave.engine.scm.ScriptFormat
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class ProjectManifest(
    val name: String,
    val createdAt: Long,
    val format: String = ScriptFormat.CLEO_ANDROID_AUTO.extension,
    val mainFile: String = "main.txt",
    val description: String = "",
    val template: String? = null,
)

data class Project(val manifest: ProjectManifest, val directory: VirtualFile) {
    val name: String get() = manifest.name
    val format: ScriptFormat get() = ScriptFormat.fromExtension(manifest.format) ?: ScriptFormat.CLEO_ANDROID_AUTO

    /** Source and text files, sorted with the main file first. */
    fun sourceFiles(): List<VirtualFile> = directory.list()
        .filter { it.isFile && it.name != MANIFEST && it.name.substringAfterLast('.').lowercase() in SOURCE_EXTENSIONS }
        .sortedWith(compareBy({ it.name != manifest.mainFile }, { it.name.lowercase() }))

    companion object {
        const val MANIFEST = "rodwave-project.json"
        val SOURCE_EXTENSIONS = setOf("txt", "sb", "fxt", "inc")
    }
}

/** Projects live in Rodwave's private storage; each is a folder with a manifest and sources. */
class ProjectManager(private val root: VirtualFile, private val clock: () -> Long = System::currentTimeMillis) {
    private val json = Json { prettyPrint = true; ignoreUnknownKeys = true; encodeDefaults = true }

    fun list(): List<Project> = root.list().filter { it.isDirectory }.mapNotNull(::load).sortedByDescending { lastModified(it) }

    fun load(dir: VirtualFile): Project? {
        val manifest = dir.child(Project.MANIFEST) ?: return null
        return runCatching { Project(json.decodeFromString(ProjectManifest.serializer(), manifest.readText()), dir) }.getOrNull()
    }

    fun lastModified(project: Project): Long =
        (project.sourceFiles().maxOfOrNull { it.lastModified } ?: 0L).coerceAtLeast(project.manifest.createdAt)

    fun create(name: String, template: ProjectTemplate): Project {
        val clean = validateName(name)
        if (root.child(clean) != null) throw FsException("A project named '$clean' already exists")
        val dir = root.createDirectory(clean)
        val manifest = ProjectManifest(clean, clock(), template.format.extension, "main.txt", template.description, template.id)
        dir.writeFile(Project.MANIFEST, json.encodeToString(ProjectManifest.serializer(), manifest).toByteArray())
        dir.writeFile("main.txt", template.source(clean).toByteArray())
        return Project(manifest, dir)
    }

    fun createFile(project: Project, fileName: String, content: String = ""): VirtualFile {
        val name = validateFileName(fileName)
        if (project.directory.child(name) != null) throw FsException("'$name' already exists")
        return project.directory.writeFile(name, content.toByteArray())
    }

    fun rename(project: Project, newName: String): Project {
        val clean = validateName(newName)
        if (clean == project.name) return project
        if (root.child(clean) != null) throw FsException("A project named '$clean' already exists")
        val dir = project.directory.renameTo(clean)
        val manifest = project.manifest.copy(name = clean)
        dir.writeFile(Project.MANIFEST, json.encodeToString(ProjectManifest.serializer(), manifest).toByteArray())
        return Project(manifest, dir)
    }

    fun updateManifest(project: Project, manifest: ProjectManifest): Project {
        project.directory.writeFile(Project.MANIFEST, json.encodeToString(ProjectManifest.serializer(), manifest).toByteArray())
        return project.copy(manifest = manifest)
    }

    fun delete(project: Project): Boolean = project.directory.delete()

    companion object {
        private val NAME = Regex("^[A-Za-z0-9][A-Za-z0-9 _.-]{0,63}$")
        private val FILE = Regex("^[A-Za-z0-9][A-Za-z0-9 _.-]{0,63}\\.(txt|sb|fxt|inc)$", RegexOption.IGNORE_CASE)

        fun validateName(name: String): String {
            val clean = name.trim()
            if (!NAME.matches(clean)) throw FsException("Project names use letters, digits, spaces, '.', '_' or '-' (1-64 characters)")
            return clean
        }

        fun validateFileName(name: String): String {
            val clean = name.trim()
            if (!FILE.matches(clean)) throw FsException("File names must end in .txt, .sb, .fxt or .inc and use letters, digits, spaces, '.', '_' or '-'")
            return clean
        }
    }
}
