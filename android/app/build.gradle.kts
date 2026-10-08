import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties (never committed; see
// docs/RELEASE.md). Missing keys fail CLOSED: release builds stop with setup
// instructions instead of silently shipping debug-signed APKs. Explicitly
// unsigned dev releases remain possible with DHADDA_ALLOW_UNSIGNED_RELEASE=1
// (never publish those artifacts). Debug builds and tests are unaffected.
//
// The same opt-in is also accepted as a Gradle property
// (-PdhaddaAllowUnsignedRelease) because F-Droid's build.yml has no field that
// maps to an arbitrary environment variable for the flutter process, so an
// env-only gate would make the tree unbuildable by F-Droid. The property is
// equivalent in force; neither is ever set by a tagged release, so the
// fail-closed default is unchanged.
val keyPropsFile = rootProject.file("key.properties")
val keyProps = Properties()
if (keyPropsFile.exists()) keyProps.load(keyPropsFile.inputStream())
val hasReleaseKeys = keyProps.containsKey("storeFile") &&
    keyProps.containsKey("storePassword") &&
    keyProps.containsKey("keyAlias") &&
    keyProps.containsKey("keyPassword")
val allowUnsignedRelease =
    System.getenv("DHADDA_ALLOW_UNSIGNED_RELEASE") == "1" ||
        (project.findProperty("dhaddaAllowUnsignedRelease")?.toString() == "true")

android {
    namespace = "com.dhadda.expense"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.dhadda.expense"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Populated only when android/key.properties exists; otherwise this
        // config stays empty and is never selected (see buildTypes below).
        create("release") {
            if (hasReleaseKeys) {
                // Paths resolve relative to android/app/.
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeys) {
                signingConfig = signingConfigs.getByName("release")
            } else if (allowUnsignedRelease) {
                // Explicit F-Droid/development path: genuinely unsigned
                // (no certificate at all — NOT debug-signed). Production
                // GitHub releases never take this branch: without keys and
                // without the flag, the taskGraph guard below fails closed.
                signingConfig = null
                logger.warn(
                    "Building UNSIGNED release (no signing certificate). " +
                        "Never publish this artifact.")
            } else {
                // Placeholder so configuration succeeds for non-release tasks
                // (debug builds, tests). A real release task without keys or
                // the explicit dev flag fails in the taskGraph guard below.
                signingConfig = signingConfigs.getByName("debug")
                logger.warn(
                    "No android/key.properties: release signing not configured.")
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

// Fail CLOSED at execution time: a real release task without keys and
// without the explicit dev flag stops with setup instructions instead of
// silently shipping a debug-signed "release". Debug builds, tests, and
// DHADDA_ALLOW_UNSIGNED_RELEASE=1 dev builds are unaffected.
gradle.taskGraph.whenReady {
    val wantsRelease = allTasks.any {
        it.name.contains("Release", ignoreCase = true)
    }
    if (wantsRelease && !hasReleaseKeys && !allowUnsignedRelease) {
        throw GradleException(
            "Release signing keys missing: create android/key.properties " +
                "(storeFile/storePassword/keyAlias/keyPassword) per " +
                "docs/RELEASE.md, or set DHADDA_ALLOW_UNSIGNED_RELEASE=1 " +
                "for a clearly-marked dev build that must never be published.")
    }
}

dependencies {
    // Required by flutter_local_notifications (Java 8+ time APIs).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
