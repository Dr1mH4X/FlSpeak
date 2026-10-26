import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Debug and release signing come from android/key.properties (gitignored) or
// ANDROID_DEBUG_* / ANDROID_RELEASE_* environment variables. Debug falls back to the
// platform debug key and release falls back to the debug config, so local
// `flutter run --release` works. CI sets REQUIRE_RELEASE_SIGNING so a release artifact
// is never silently signed with the debug key.
val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.exists()) {
    FileInputStream(signingPropertiesFile).use { signingProperties.load(it) }
}

fun signingValue(property: String, environment: String): String? {
    val fromProperties = signingProperties.getProperty(property)
    return if (!fromProperties.isNullOrBlank()) fromProperties else System.getenv(environment)?.takeIf { it.isNotBlank() }
}

val debugKeystore = signingValue("debugStoreFile", "ANDROID_DEBUG_KEYSTORE_PATH")
val debugStorePassword = signingValue("debugStorePassword", "ANDROID_DEBUG_KEYSTORE_PASSWORD")
val debugKeyAlias = signingValue("debugKeyAlias", "ANDROID_DEBUG_KEY_ALIAS")
val debugKeyPassword = signingValue("debugKeyPassword", "ANDROID_DEBUG_KEY_PASSWORD")
val hasDebugSigning =
    debugKeystore != null &&
        debugStorePassword != null &&
        debugKeyAlias != null &&
        debugKeyPassword != null

val releaseKeystore = signingValue("releaseStoreFile", "ANDROID_RELEASE_KEYSTORE_PATH")
val releaseStorePassword = signingValue("releaseStorePassword", "ANDROID_RELEASE_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("releaseKeyAlias", "ANDROID_RELEASE_KEY_ALIAS")
val releaseKeyPassword = signingValue("releaseKeyPassword", "ANDROID_RELEASE_KEY_PASSWORD")
val hasReleaseSigning =
    releaseKeystore != null &&
        releaseStorePassword != null &&
        releaseKeyAlias != null &&
        releaseKeyPassword != null

if (System.getenv("REQUIRE_RELEASE_SIGNING") == "true" && !hasReleaseSigning) {
    error(
        "REQUIRE_RELEASE_SIGNING=true but release signing is incomplete: " +
            "provide release* entries in android/key.properties or ANDROID_RELEASE_* environment variables.",
    )
}

android {
    namespace = "com.dr1mh4x.flspeak"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.dr1mh4x.flspeak"
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
        // Reuse the debug config name so debug builds pick up the custom key without
        // touching buildTypes.
        if (hasDebugSigning) {
            getByName("debug") {
                storeFile = file(debugKeystore!!)
                storePassword = debugStorePassword
                keyAlias = debugKeyAlias
                keyPassword = debugKeyPassword
            }
        }
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseKeystore!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseSigning) {
                    signingConfigs.getByName("release")
                } else {
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
