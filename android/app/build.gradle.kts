plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.puraair.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.puraair.app"
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

flutter {
    source = "../.."
}


dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

// Explicit local-test opt-in. Configure after the plugin's variant defaults.
val puraIsolatedTest = providers.environmentVariable("PURA_ISOLATED_TEST").orElse("false").get() == "true"
gradle.projectsEvaluated {
    if (puraIsolatedTest) {
        tasks.withType<com.google.gms.googleservices.GoogleServicesTask>().configureEach {
            googleServicesJsonFiles.set(listOf(file("src/emulator/google-services.json")))
            doLast {
                val generated = outputDirectory.file("values/values.xml").get().asFile.readText()
                check(generated.contains(">demo-pura-security</string>")) {
                    "Isolated test Firebase configuration was not generated; refusing APK"
                }
            }
        }
    }
}
