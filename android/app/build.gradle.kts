plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

val versionNameBase = project.findProperty("VERSION_NAME") as String? ?: "VERSION_PLACEHOLDER"
val commitHash = project.findProperty("CI_COMMIT_SHA")?.toString()?.take(7) ?: "COMMIT_PLACEHOLDER"
val buildNumber = project.findProperty("CI_BUILD_NUMBER")?.toString() ?: "BUILD_PLACEHOLDER"
val versionName = "$versionNameBase-$commitHash-$buildNumber"

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
        versionName = versionName
    }

    val keystoreProperties = Properties()
    val keystorePropertiesFile = file("keystore.properties")
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(keystorePropertiesFile.inputStream())
    }

    buildTypes {
        release {
            signingConfigs {
                create("release") {
                    storeFile = file("keystore.jks")
                    storePassword = keystoreProperties.getProperty("storePassword", "")
                    keyAlias = keystoreProperties.getProperty("keyAlias", "")
                    keyPassword = keystoreProperties.getProperty("keyPassword", "")
                }
            }
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
