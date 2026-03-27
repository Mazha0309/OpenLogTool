plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

val appVersionName = "VERSION_PLACEHOLDER"

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
        versionName = appVersionName
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
