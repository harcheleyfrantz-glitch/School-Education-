import org.jetbrains.kotlin.gradle.dsl.JvmTarget

/*
 * Development harness: compiles Rodwave's platform-neutral UI (app/.../core and app/.../ui) against
 * Compose Multiplatform for the desktop JVM. This type-checks the screens without an Android SDK,
 * renders screenshots for reviews (`./gradlew :desktop:run --args=screenshots`) and offers a
 * desktop preview window (`./gradlew :desktop:run`). The shipping product is the Android app.
 */
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.compose.compiler)
    alias(libs.plugins.compose.multiplatform)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

sourceSets {
    main {
        kotlin.srcDir("../app/src/main/java/com/rodwave/studio/core")
        kotlin.srcDir("../app/src/main/java/com/rodwave/studio/ui")
    }
}

dependencies {
    implementation(project(":engine"))
    implementation(compose.desktop.currentOs)
    implementation(compose.material3)
    implementation(compose.materialIconsExtended)
    implementation(libs.kotlinx.coroutines.swing)
    implementation(libs.kotlinx.serialization.json)
}

compose.desktop {
    application {
        mainClass = "com.rodwave.desktop.MainKt"
    }
}
