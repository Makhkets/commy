allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Flutter's standard out-of-tree build directory, so `flutter clean` finds it.
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

// Every Flutter plugin becomes its own Gradle subproject, and the Flutter Gradle
// plugin gives each one `ndkVersion = flutter.ndkVersion`. AGP then demands the
// highest version any subproject asked for and tries to DOWNLOAD it — which on a
// slow link produces a truncated archive and a build that dies seventeen minutes
// in with `java.util.zip.ZipException: Archive is not a ZIP archive`, naming a
// version nobody in this repo wrote down.
//
// Pinning only :app is not enough, which is how that failure was reached. Pin
// every Android subproject to the NDK that is actually installed — the one
// `gomobile bind` used for libbox.aar, so the core and the app agree
// (docs/13-libbox-reference.md).
val commyNdkVersion = "28.0.13004108"

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // afterEvaluate, and that is the whole trick. A `plugins.withId` callback
    // fires the moment the Android plugin is applied, which is *before* the
    // subproject's own `android { ndkVersion flutter.ndkVersion }` line runs —
    // so the pin gets overwritten by the very value it was meant to replace,
    // and the build still dies on a version nobody asked for. Running after the
    // subproject is evaluated puts us last.
    //
    // BaseExtension covers both library and application subprojects. The `as?`
    // makes a non-Android subproject a silent no-op rather than a cast failure.
    project.afterEvaluate {
        val androidExtension =
            project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        androidExtension?.ndkVersion = commyNdkVersion
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
