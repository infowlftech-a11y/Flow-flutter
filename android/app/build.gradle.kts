plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// FCM needs the Google Services plugin to process google-services.json (§11.3).
// Applied only when the file is present: the plugin hard-fails the build when
// it is missing, and a checkout without credentials should still compile.
// Drop android/app/google-services.json in and push wiring activates itself.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.warn(
        "google-services.json not found in android/app — building without FCM. " +
        "Push notifications will not be delivered until it is added."
    )
}

android {
    namespace = "com.wlftech.flow"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Deliberately migrated from com.kiteflow.app to the WLF Tech brand
        // namespace, overriding APP_LOGIC_BLUEPRINT.md §12/§15 which froze the
        // old id. This is a new Play listing and a new Firebase Android app —
        // see README "Identity migration" for the console work it requires.
        applicationId = "com.wlftech.flow"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
