import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Must come after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is optional on purpose. Without a keystore the build still
// produces an installable APK signed with the debug key, so CI and a fresh
// clone both work. A project that cannot build until someone uploads a keystore
// is a project nobody can contribute to.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun signingValue(key: String, env: String): String? =
    keystoreProperties.getProperty(key) ?: System.getenv(env)

val storeFilePath = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
val hasReleaseSigning = storeFilePath != null && file(storeFilePath).exists()

// Whether this invocation is building an app bundle rather than APKs.
//
// Read from the requested task names because there is no other signal: the
// Android extension is configured once, before any task runs, and the ABI split
// setting it needs differs between `assemble*` and `bundle*`. Flutter invokes
// `bundleRelease` for `flutter build appbundle`, so matching "Bundle" catches
// it without matching `assembleRelease`.
val isBundleTask = gradle.startParameter.taskNames.any {
    it.contains("bundle", ignoreCase = true)
}

android {
    namespace = "dev.commy.app"
    compileSdk = 36

    // Pinned, not flutter.ndkVersion. Gradle compiles nothing native here — we
    // link a prebuilt AAR — but AGP still insists the NDK it was told about is
    // installed, and fails configuration with "NDK not configured" if it is
    // not. Following Flutter's default means that version moves with every SDK
    // upgrade and the build breaks on a machine that has the NDK we actually
    // use. This is the one gomobile built libbox.aar with
    // (docs/13-libbox-reference.md), so the core and the app agree.
    ndkVersion = "28.0.13004108"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.commy.app"
        // 24, not flutter.minSdkVersion: libbox.aar is built with
        // `gomobile bind -androidapi 24`, and a lower minSdk here fails at
        // manifest merge with a message that does not mention the AAR.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(storeFilePath!!)
                storePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseSigning) {
                    signingConfigs.getByName("release")
                } else {
                    logger.warn(
                        "commy: no release keystore found — signing with the debug key. " +
                            "This build must not be distributed.",
                    )
                    signingConfigs.getByName("debug")
                }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }

    splits {
        abi {
            // Off for a bundle, on for APKs. An app bundle already carries every
            // ABI and lets Play split them, so the two mechanisms overlap — and
            // with resource shrinking on they do not merely overlap, they fail:
            // R8 writes one shrunk-resources file per split and `bundleRelease`
            // finds four where it expects one.
            //
            //   Multiple shrunk-resources files found in directory
            //   '…/shrunk_resources_proto_format/release/minifyReleaseWithR8'
            //
            // https://issuetracker.google.com/402800800. The release workflow
            // builds split APKs, a universal APK and an AAB in one job, so this
            // has to be decided per invocation rather than once.
            isEnable = !isBundleTask
            reset()
            // 32-bit ARM is still worth carrying: plenty of cheap phones in the
            // regions this app exists for have never seen an arm64 build.
            include("arm64-v8a", "armeabi-v7a", "x86_64")
            isUniversalApk = true
        }
    }

    packaging {
        jniLibs {
            // libbox.so is ~39 MB uncompressed. Keeping it uncompressed lets the
            // loader mmap it straight out of the APK instead of unpacking a copy
            // into the data partition on install.
            useLegacyPackaging = false
        }
    }

    buildFeatures {
        // Off by default since AGP 8, and CoreSetup reads BuildConfig.DEBUG to
        // decide whether to hand libbox a debug log level and redirect the Go
        // stderr crash dump to a file. Without this the module does not compile
        // at all, with three "Unresolved reference 'BuildConfig'" that say
        // nothing about a Gradle default having changed.
        buildConfig = true
    }

    lint {
        checkReleaseBuilds = false
    }
}

dependencies {
    // The sing-box core. Produced by scripts/build_core.sh, not by Gradle.
    implementation(files("libs/libbox.aar"))

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Fail early and legibly. Without the AAR the build dies deep inside the Kotlin
// compiler complaining about an unresolved `io.nekohasekai.libbox`, which tells
// a newcomer nothing about what to do next.
tasks.named("preBuild") {
    doFirst {
        val aar = file("libs/libbox.aar")
        if (!aar.exists()) {
            throw GradleException(
                """
                |
                |  The sing-box core is missing: ${aar.path}
                |
                |  Build it first:
                |      COMMY_ANDROID_ABIS=android/arm64 scripts/build_core.sh android
                |
                |  It needs Go 1.24+, a JDK and Android NDK 28.0.13004108.
                |  See core/README.md and docs/13-libbox-reference.md.
                |
                """.trimMargin(),
            )
        }
    }
}
