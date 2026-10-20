import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
        // The engine runs on Android: restrict the visible JDK API to Java 17.
        freeCompilerArgs.add("-Xjdk-release=17")
    }
}

dependencies {
    implementation(libs.kotlinx.serialization.json)

    testImplementation(kotlin("test"))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.test {
    useJUnitPlatform()
    // Optional maintainer check: point at a Sanny Builder Library sa_mobile.json to verify the
    // built-in core opcode table against it (see OpcodeDatabaseTest).
    System.getenv("RODWAVE_SBL_JSON")?.let { environment("RODWAVE_SBL_JSON", it) }
    // SamplesTest compiles every script in samples/.
    val samples = rootProject.file("samples")
    inputs.dir(samples).withPropertyName("samples")
    systemProperty("rodwave.samplesDir", samples.absolutePath)
    testLogging {
        events("failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
