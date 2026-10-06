import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release key lives in android/key.properties (storeFile, storePassword,
// keyAlias, keyPassword), never in git. A store release without it fails: a
// build signed with the debug key looks like a release and cannot update the
// published app. `-PallowDebugSigning` (through flutter: `-P
// allowDebugSigning=true`) signs it with the debug key on purpose, to test a
// release build on a device; such a build says so in its version name
// (-debugsigned) and in the build log. F-Droid builds are never signed here:
// F-Droid signs the APK it builds with its own key.
val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keyPropertiesFile.exists()
if (hasReleaseKey) {
    FileInputStream(keyPropertiesFile).use { keyProperties.load(it) }
}
// Only the bare flag or `true`: a stray value (`no`, `1`) in a gradle.properties
// file or an ORG_GRADLE_PROJECT_ variable does not sign a store build with the
// debug key.
val allowDebugSigning = providers.gradleProperty("allowDebugSigning").orNull in setOf("", "true")
val debugSignedStore = !hasReleaseKey && allowDebugSigning

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
            // The release build type sets no signing config, so this one
            // applies; debug and profile builds keep the debug key.
            signingConfig =
                when {
                    hasReleaseKey -> signingConfigs.getByName("release")
                    allowDebugSigning -> signingConfigs.getByName("debug")
                    else -> null
                }
            if (debugSignedStore) {
                versionNameSuffix = "-debugsigned"
            }
        }
        create("fdroid") {
            dimension = "distribution"
            versionNameSuffix = "-fdroid"
            proguardFile("proguard-fdroid.pro")
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

// Stops a store release before anything is built when it has no key to be
// signed with. preStoreReleaseBuild runs first in every task of the variant
// (assemble, bundle, install).
val checkStoreReleaseSigning by tasks.registering {
    val signable = hasReleaseKey || allowDebugSigning
    val debugSigned = debugSignedStore
    doLast {
        if (debugSigned) {
            logger.warn("Store release signed with the DEBUG key (-PallowDebugSigning): for local tests only, never to publish.")
        }
        if (!signable) {
            throw GradleException(
                "Store release without android/key.properties: add the upload key, or pass " +
                    "-PallowDebugSigning (flutter: -P allowDebugSigning=true) to sign this build " +
                    "with the debug key for a local test. F-Droid builds (--flavor fdroid) need no key.",
            )
        }
    }
}
tasks.matching { it.name == "preStoreReleaseBuild" }.configureEach { dependsOn(checkStoreReleaseSigning) }

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
