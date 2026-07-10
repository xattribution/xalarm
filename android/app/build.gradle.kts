import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Play Store upload key: android/key.properties (git-ignored; see
// docs/play_store.md). When absent, release builds fall back to the
// committed sideload keystore so the self-hosted download loop keeps
// working unchanged.
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasUploadKey = keyProperties.getProperty("storeFile") != null

android {
    namespace = "com.xattribution.xalarm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (uses newer java.time APIs).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Play Store identity — permanent once the first bundle is uploaded.
        applicationId = "com.xalarm"
        // Alarm scheduling + notifications need a modern minimum.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Committed keystore for the self-hosted/sideload channel: every
        // Docker build shares one signing identity so updates install over
        // each other. Not a secret worth protecting at the cost of broken
        // sideload updates — the Play channel uses the private upload key.
        create("release") {
            storeFile = file("xalarm-release.p12")
            storePassword = "xalarm-release"
            keyAlias = "xalarm"
            keyPassword = "xalarm-release"
            storeType = "PKCS12"
        }
        if (hasUploadKey) {
            create("upload") {
                storeFile = rootProject.file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                signingConfigs.getByName(if (hasUploadKey) "upload" else "release")
        }
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
