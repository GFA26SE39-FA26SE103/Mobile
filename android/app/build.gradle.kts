import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "vn.edu.fpt.gfa26se39.supermarket_staff"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Native Firebase values below are generated resources.
    buildFeatures {
        resValues = true
    }

    compileOptions {
        // flutter_local_notifications needs Java 8+ library desugaring on older Android versions.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "vn.edu.fpt.gfa26se39.supermarket_staff"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Firebase must exist natively before any Dart code runs: a push that arrives while the
        // app is closed starts only the Android process. The client values come from the same
        // --dart-define(-from-file) entries the Dart side uses, so no google-services.json is needed.
        val firebase = dartDefines()
        val firebaseResources = mapOf(
            "google_app_id" to "FIREBASE_APP_ID",
            "google_api_key" to "FIREBASE_API_KEY",
            "gcm_defaultSenderId" to "FIREBASE_MESSAGING_SENDER_ID",
            "project_id" to "FIREBASE_PROJECT_ID",
        )
        if (firebaseResources.values.all { !firebase[it].isNullOrBlank() }) {
            firebaseResources.forEach { (resource, key) -> resValue("string", resource, firebase.getValue(key)) }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

/** The `--dart-define` values Flutter passes to Gradle as comma-separated base64 `KEY=VALUE` pairs. */
fun dartDefines(): Map<String, String> =
    (project.findProperty("dart-defines") as String?).orEmpty()
        .split(',')
        .filter { it.isNotBlank() }
        .map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
        .filter { it.contains('=') }
        .associate { it.substringBefore('=') to it.substringAfter('=') }

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
