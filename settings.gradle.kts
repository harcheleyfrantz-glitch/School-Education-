pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
    }
}

rootProject.name = "Rodwave"

// Platform-independent scripting engine: compiler, decompiler, opcode database,
// compatibility rules, mod management. Plain Kotlin/JVM, tested without Android.
include(":engine")

// Compose Desktop preview harness. Compiles the platform-neutral UI from :app against
// Compose Multiplatform so screens are type-checked without an Android SDK. Running it (preview
// window, screenshots) also needs a few AndroidX runtime libraries from Google's Maven repository.
include(":desktop")

// The Android application. Pass -Prodwave.includeAndroid=false to build only the
// engine and desktop harness on machines without the Android SDK / Google Maven.
val includeAndroid = providers.gradleProperty("rodwave.includeAndroid")
    .map { it.toBoolean() }
    .getOrElse(true)
if (includeAndroid) {
    include(":app")
}
