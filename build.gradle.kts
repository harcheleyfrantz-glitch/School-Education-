buildscript {
    // AGP is put on the root classpath only when the :app module is part of the build, so the
    // engine and desktop harness can be built where Google Maven is unreachable. It must live
    // in the root classloader next to the Kotlin plugin, otherwise kotlin-android cannot see it.
    val includeAndroid = (findProperty("rodwave.includeAndroid") as String?)?.toBoolean() ?: true
    if (includeAndroid) {
        repositories {
            google()
            mavenCentral()
        }
        dependencies {
            classpath(libs.android.gradle.plugin)
        }
    }
}

plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.compose.compiler) apply false
    alias(libs.plugins.compose.multiplatform) apply false
}
