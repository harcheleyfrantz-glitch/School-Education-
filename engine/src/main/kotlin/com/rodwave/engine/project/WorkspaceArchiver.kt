package com.rodwave.engine.project

import com.rodwave.engine.archive.ArchiveFile
import com.rodwave.engine.archive.SafeZip
import com.rodwave.engine.fs.VirtualFile
import com.rodwave.engine.fs.readBytes
import com.rodwave.engine.fs.resolve
import com.rodwave.engine.fs.walk
import com.rodwave.engine.fs.writeFile
import java.io.ByteArrayOutputStream

data class RestorePlan(val newFiles: List<String>, val conflicts: List<String>, val rejected: List<String>, val files: List<ArchiveFile>)

/** Backs up and restores the projects folder as a ZIP file. */
object WorkspaceArchiver {
    fun export(projectsRoot: VirtualFile): ByteArray {
        val base = projectsRoot.path.trimEnd('/')
        val files = projectsRoot.walk(maxDepth = 6).filter { it.isFile }.map {
            val relative = if (base.isEmpty()) it.path else it.path.removePrefix(base).trimStart('/')
            ArchiveFile("projects/$relative", it.readBytes())
        }.toList()
        val out = ByteArrayOutputStream()
        SafeZip.write(out, files)
        return out.toByteArray()
    }

    /** Dry run: which files a restore would create and which already exist. */
    fun planRestore(zip: ByteArray, projectsRoot: VirtualFile): RestorePlan {
        val contents = SafeZip.read(zip.inputStream())
        val files = contents.files.filter { it.path.startsWith("projects/") }.map { it.copy(path = it.path.removePrefix("projects/")) }
            .filter { it.path.isNotEmpty() }
        val (conflicts, fresh) = files.partition { projectsRoot.resolve(it.path) != null }
        return RestorePlan(fresh.map { it.path }, conflicts.map { it.path }, contents.rejected.map { "${it.path}: ${it.reason}" }, files)
    }

    /** Writes the files of [plan]; existing files are only replaced when [overwrite] is true. */
    fun restore(plan: RestorePlan, projectsRoot: VirtualFile, overwrite: Boolean): Int {
        var written = 0
        for (f in plan.files) {
            if (!overwrite && f.path in plan.conflicts) continue
            projectsRoot.writeFile(f.path, f.data)
            written++
        }
        return written
    }
}
