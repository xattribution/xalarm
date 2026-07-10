allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Some Flutter plugins pin an outdated compileSdk in their own build.gradle
// (the `alarm` plugin pins 34, while its flutter_fgbg dependency requires
// 35+), which fails the AAR metadata check. Force every Android module up to
// a current compileSdk; this only changes which APIs modules compile against,
// not minSdk/targetSdk runtime behaviour.
//
// evaluationDependsOn(":app") above means some projects are already evaluated
// when this block runs — configure those immediately, defer the rest.
subprojects {
    fun forceCompileSdk(project: Project) {
        project.extensions
            .findByType(com.android.build.gradle.BaseExtension::class.java)
            ?.compileSdkVersion(36)
    }
    if (state.executed) {
        forceCompileSdk(this)
    } else {
        afterEvaluate { forceCompileSdk(this) }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
