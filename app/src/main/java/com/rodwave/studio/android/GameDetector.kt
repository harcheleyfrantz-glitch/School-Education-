package com.rodwave.studio.android

import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import com.rodwave.engine.compat.InstalledGame
import com.rodwave.engine.scm.Abi
import java.io.File
import java.util.zip.ZipFile

/**
 * Reads what Android reports about the installed game: version, ABIs and the native libraries in its
 * APK files. APKs under /data/app are world-readable; nothing inside them is extracted or executed.
 */
object GameDetector {
    const val PACKAGE = "com.rockstargames.gtasa"

    fun detect(pm: PackageManager): InstalledGame? {
        val info = packageInfo(pm) ?: return null
        val appInfo: ApplicationInfo = info.applicationInfo ?: return null
        val apks = listOfNotNull(appInfo.sourceDir) + (appInfo.splitSourceDirs?.toList() ?: emptyList())
        val libraries = mutableListOf<String>()
        val abis = mutableSetOf<Abi>()
        var apkReadable = false
        for (apk in apks) {
            try {
                ZipFile(apk).use { zip ->
                    apkReadable = true
                    for (entry in zip.entries()) {
                        // Native libraries live at lib/<abi>/<name>.so inside the base or split APKs.
                        val parts = entry.name.split('/')
                        if (parts.size == 3 && parts[0] == "lib" && parts[2].endsWith(".so")) {
                            Abi.fromAndroidName(parts[1])?.let(abis::add)
                            libraries += parts[2]
                        }
                    }
                }
            } catch (e: Exception) {
                // An unreadable split is not fatal; the report says whether any APK could be read.
            }
        }
        val running = abiOfLibraryDir(appInfo.nativeLibraryDir)
        if (abis.isEmpty() && running != null) abis += running
        if (!apkReadable) {
            // Extracted libraries (extractNativeLibs=true) can still be listed from the library folder.
            appInfo.nativeLibraryDir?.let { dir -> File(dir).list()?.filter { it.endsWith(".so") }?.let(libraries::addAll) }
        }
        val versionCode = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
        return InstalledGame(
            packageName = PACKAGE,
            versionName = info.versionName,
            versionCode = versionCode,
            abis = abis,
            nativeLibraries = libraries.distinct().sorted(),
            apkReadable = apkReadable,
            targetSdk = appInfo.targetSdkVersion,
            runningAbi = running,
        )
    }

    private fun packageInfo(pm: PackageManager): PackageInfo? = try {
        if (Build.VERSION.SDK_INT >= 33) {
            pm.getPackageInfo(PACKAGE, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(PACKAGE, 0)
        }
    } catch (e: PackageManager.NameNotFoundException) {
        null
    }

    /**
     * Android installs one ABI's libraries per app and names the folder after the instruction set,
     * e.g. /data/app/.../lib/arm64. That folder tells which ABI the game process uses.
     */
    fun abiOfLibraryDir(dir: String?): Abi? = when (dir?.trimEnd('/')?.substringAfterLast('/')) {
        "arm64" -> Abi.ARM64_V8A
        "arm" -> Abi.ARMEABI_V7A
        "x86_64" -> Abi.X86_64
        "x86" -> Abi.X86
        else -> null
    }
}
