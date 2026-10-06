import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release key lives in android/key.properties (storeFile, storePassword,
// keyAlias, keyPassword), never in git. Without it, release builds are signed
// with the debug key, so CI and fresh clones still build.
val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keyPropertiesFile.exists()
if (hasReleaseKey) {
    FileInputStream(keyPropertiesFile).use { keyProperties.load(it) }
}

android {
    namespace = "legal.p2p.lunaway"
    // 37: permission_handler_android compiles against it. compileSdk only
    // gives access to newer APIs; targetSdk sets the runtime behaviour.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "legal.p2p.lunaway"
        minSdk = flutter.minSdkVersion
        // Play requires API 35 for new apps from 2025-08 and 36 a year later;
        // the floor holds even if a Flutter release ships a lower default.
        targetSdk = maxOf(flutter.targetSdkVersion, 36)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKey) {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    // Two distributions of the same app. `store` is the Play build; `fdroid`
    // carries no Google Play Services (F-Droid refuses proprietary
    // dependencies) and shows the position through Android's own location
    // manager, which MapLibre uses by default.
    flavorDimensions += "distribution"
    productFlavors {
        create("store") {
            dimension = "distribution"
        }
        create("fdroid") {
            dimension = "distribution"
            versionNameSuffix = "-fdroid"
            proguardFile("proguard-fdroid.pro")
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKey) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            // Uncompressed and page-aligned native libraries: required for
            // 16 KB page devices and loaded straight from the APK.
            useLegacyPackaging = false
        }
    }
}

// maplibre_gl declares play-services-location for an optional high-accuracy
// engine the app does not use (it keeps the default, balanced priority, which
// runs on Android's LocationManager). The F-Droid build leaves Play Services
// out entirely.
configurations.configureEach {
    if (name.startsWith("fdroid")) {
        exclude(group = "com.google.android.gms")
        exclude(group = "com.google.firebase")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
