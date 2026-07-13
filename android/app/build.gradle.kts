plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import org.gradle.api.tasks.Exec

val rustManifest = rootProject.file("../rust/Cargo.toml")
val rustSourceDirectory = rootProject.file("../rust")
val rustJniLibsDirectory = file("src/main/jniLibs")
val rustAndroidAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")
val androidLocalProperties = Properties()
val androidLocalPropertiesFile = rootProject.file("local.properties")
if (androidLocalPropertiesFile.isFile) {
    androidLocalPropertiesFile.inputStream().use { androidLocalProperties.load(it) }
}
val androidSdkDirectory =
    listOf(
        System.getenv("ANDROID_SDK_ROOT"),
        System.getenv("ANDROID_HOME"),
        androidLocalProperties.getProperty("sdk.dir"),
    ).firstOrNull { !it.isNullOrBlank() }?.let(::file)
val configuredAndroidNdkDirectory =
    androidSdkDirectory?.resolve("ndk/${flutter.ndkVersion}")

android {
    namespace = "com.mazha0309.openlogtool"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.mazha0309.openlogtool"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val keystoreProperties = Properties()
    val keystorePropertiesFile = file("keystore.properties")
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    }

    val releaseKeystoreFile =
        keystoreProperties
            .getProperty("storeFile")
            ?.takeIf(String::isNotBlank)
            ?.let(::file)
            ?: file("keystore.jks")
    val hasReleaseSigning =
        releaseKeystoreFile.isFile &&
            listOf("storePassword", "keyAlias", "keyPassword")
                .all { !keystoreProperties.getProperty(it).isNullOrBlank() }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseKeystoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseSigning) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }

    sourceSets.getByName("main").jniLibs.srcDir(rustJniLibsDirectory)
}

flutter {
    source = "../.."
}

val buildRustAndroid by tasks.registering(Exec::class) {
    group = "build"
    description = "Builds the Rust core library for all supported Android ABIs."
    // cargo-ndk 4.1.2 resolves metadata from its working directory before it
    // applies --manifest-path, so the task must start inside the Rust crate.
    workingDir(rustSourceDirectory)
    if (configuredAndroidNdkDirectory?.isDirectory == true) {
        environment("ANDROID_NDK_HOME", configuredAndroidNdkDirectory.absolutePath)
    }

    commandLine(
        "cargo",
        "ndk",
        "--platform",
        "24",
        "-t",
        "arm64-v8a",
        "-t",
        "armeabi-v7a",
        "-t",
        "x86_64",
        "-o",
        rustJniLibsDirectory.absolutePath,
        "--manifest-path",
        rustManifest.absolutePath,
        "build",
        "--release",
        "--locked",
        "--lib",
    )

    inputs.file(rustManifest)
    inputs.file(rootProject.file("../rust/Cargo.lock"))
    inputs.file(rootProject.file("../rust-toolchain.toml"))
    inputs.dir(rootProject.file("../rust/src"))
    outputs.files(
        rustAndroidAbis.map { abi ->
            rustJniLibsDirectory.resolve("$abi/libopenlogtool_core.so")
        },
    )
}

tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(buildRustAndroid)
}
