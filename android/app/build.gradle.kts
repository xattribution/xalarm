import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. Two channels, both keyed from files that are never
// committed (see docs/signing.md):
//
//   android/key.properties       Play Store upload key   (build-play.sh)
//   android/sideload.properties  self-hosted APK key     (update.sh generates
//                                                         one on first run)
//
// XALARM_SIGNING_PROPERTIES may point at either file explicitly (the Docker
// build mounts it as a secret). With no key file at all, release builds are
// signed with the debug key so `flutter build apk` still works for local
// testing — such builds cannot be installed over a properly signed one.
fun loadProps(file: File): Properties? =
    if (file.exists()) Properties().apply { file.inputStream().use { load(it) } } else null

val signingProps: Properties? =
    System.getenv("XALARM_SIGNING_PROPERTIES")?.let { loadProps(File(it)) }
        ?: loadProps(rootProject.file("key.properties"))
        ?: loadProps(rootProject.file("sideload.properties"))

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
        // The self-hosted channel is signed with a different key, so the
        // Docker build gives it its own id (XALARM_APP_ID_SUFFIX=.sideload)
        // and it can live next to the Play build. Unset = plain com.xalarm.
        applicationId = "com.xalarm" + (System.getenv("XALARM_APP_ID_SUFFIX") ?: "")
        // Alarm scheduling + notifications need a modern minimum.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingProps != null) {
            create("release") {
                val storePath = signingProps.getProperty("storeFile")
                    ?: error("storeFile missing from signing properties")
                storeFile = File(storePath).let { f ->
                    if (f.isAbsolute) f else rootProject.file(storePath)
                }
                storePassword = signingProps.getProperty("storePassword")
                keyAlias = signingProps.getProperty("keyAlias")
                keyPassword = signingProps.getProperty("keyPassword")
                signingProps.getProperty("storeType")?.let { storeType = it }
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (signingProps != null) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "xalarm: no signing properties found — release build is " +
                        "DEBUG-signed (see docs/signing.md)",
                )
                signingConfigs.getByName("debug")
            }
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
