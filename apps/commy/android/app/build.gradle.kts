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

// `flutter build apk --split-per-abi` arrives here as this Gradle property.
// Flutter's own plugin reads it too and switches the universal APK off — but
// it configures `splits` before the block below runs, so whatever that block
// says about `isUniversalApk` wins. It has to ask the same question itself.
val isSplitPerAbi =
    (findProperty("split-per-abi")?.toString()?.toBoolean()) ?: false

// `--target-platform android-arm,android-arm64` arrives as this property.
// Flutter uses it to decide which engine and which Dart snapshot go in; the
// core comes from libbox.aar, which Flutter knows nothing about, so without
// help an APK "for two platforms" still carried the 13 MB x86_64 core next to
// an engine that was not there to load it. The ABIs named here are the only
// ones whose native libraries are packaged. Absent — `flutter run`, the CI
// debug build — nothing is excluded.
val targetAbis: Set<String>? =
    findProperty("target-platform")?.toString()
        ?.split(',')
        ?.mapNotNull {
            when (it.trim()) {
                "android-arm" -> "armeabi-v7a"
                "android-arm64" -> "arm64-v8a"
                "android-x64" -> "x86_64"
                else -> null
            }
        }
        ?.toSet()
        ?.takeIf { it.isNotEmpty() }

android {
    namespace = "dev.commy.app"

    // 37, one ahead of the targetSdk below, and that gap is the point:
    // compileSdk decides which APIs the compiler can see, targetSdk decides
    // which runtime behaviour the app opts into. androidx.core 1.19.0 is built
    // against 37 and AGP refuses to link a project compiled against less, so
    // this had to move for the library. Nothing about how the app behaves on a
    // device changes until targetSdk moves too, which is its own decision with
    // its own reading of the behaviour changes.
    compileSdk = 37

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
            // Only when asked for. Left on for every APK build, a universal
            // build also dropped three per-ABI files beside the one it was
            // for — among them an x86_64 APK with no core in it, because the
            // excludes below had done their job on it too.
            isEnable = isSplitPerAbi && !isBundleTask
            reset()
            // 32-bit ARM is still worth carrying: plenty of cheap phones in the
            // regions this app exists for have never seen an arm64 build.
            include("arm64-v8a", "armeabi-v7a", "x86_64")
            // One file on the releases page — the owner's decision of
            // 2026-09-18: three per-ABI APKs left people guessing which to
            // take. The universal APK is that file. It is built for the two
            // ABIs phones have (`--target-platform android-arm,android-arm64`)
            // and carries nothing for x86_64, which only emulators run — see
            // `targetAbis` above and the `jniLibs` excludes below. Per-ABI
            // files are still produced by `--split-per-abi` for whoever wants
            // them; they are not published. Rule R11, CLAUDE.md.
            isUniversalApk = false
        }
    }

    packaging {
        jniLibs {
            // Compressed inside an APK, stored inside a bundle.
            //
            // 66 of the 69 MB of an arm64 APK were native libraries stored
            // as-is, and libbox.so alone is 39 MB that deflates to 13. An APK
            // from the releases page is downloaded exactly as it is built —
            // nothing between GitHub and the phone compresses it — so stored
            // libraries cost every user 40 MB of download for nothing they can
            // see. Compressed, the same app is a 28 MB file.
            //
            // The price is on the device: the installer unpacks the libraries
            // next to the APK, so the installed size grows by roughly what the
            // download shrank. It is paid once, at install, and buys nothing
            // back at run time either way — a library mapped from the APK and
            // one mapped from a file start equally fast. For a client people
            // fetch over the very connection it is meant to fix, the download
            // is the number that matters.
            //
            // A bundle is the opposite case: Play compresses the download
            // itself and serves per-device splits, so there stored libraries
            // cost nothing in transit and save the unpacked copy on disk.
            useLegacyPackaging = !isBundleTask
            // Only a universal APK needs this: a split already holds one ABI.
            if (!isSplitPerAbi && !isBundleTask) {
                targetAbis?.let { wanted ->
                    listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
                        .filterNot(wanted::contains)
                        .forEach { excludes += "lib/$it/**" }
                }
            }
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

    implementation("androidx.core:core-ktx:1.19.0")
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
