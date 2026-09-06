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
val keyPropsFile = rootProject.file("key.properties")
val keyProps = java.util.Properties()
if (keyPropsFile.exists()) keyProps.load(keyPropsFile.inputStream())
val hasReleaseKeys = keyProps.containsKey("storeFile") &&
    keyProps.containsKey("storePassword") &&
    keyProps.containsKey("keyAlias") &&
    keyProps.containsKey("keyPassword")
val allowUnsignedRelease =
    System.getenv("DHADDA_ALLOW_UNSIGNED_RELEASE") == "1"

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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
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
                signingConfig = signingConfigs.getByName("debug")
                logger.warn(
                    "DHADDA_ALLOW_UNSIGNED_RELEASE=1: building an explicitly " +
                        "unsigned dev release. Do NOT publish this artifact.")
            } else {
                throw GradleException(
                    "Release signing keys missing: create android/key.properties " +
                        "(storeFile/storePassword/keyAlias/keyPassword) per " +
                        "docs/RELEASE.md, or set DHADDA_ALLOW_UNSIGNED_RELEASE=1 " +
                        "for a clearly-marked dev build. " +
                        "Debug builds and tests are unaffected.")
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
    // Required by flutter_local_notifications (Java 8+ time APIs).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
