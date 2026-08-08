plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.omni.omni"
    compileSdk = flutter.compileSdkVersion
    // Several plugins ask for a newer NDK than the Flutter SDK's default.
    // NDK releases are backward compatible, so the highest wins.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // flutter_local_notifications uses java.time, which only exists on
        // API 26+; desugaring backports it so Omni still runs on older
        // phones.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "dev.omni.omni"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Pre-release/dev signing key checked into the repo. Before any real
    // distribution, replace with a private keystore via env vars:
    // OMNI_KEYSTORE_PATH, OMNI_KEYSTORE_PASSWORD, OMNI_KEY_ALIAS, OMNI_KEY_PASSWORD.
    signingConfigs {
        create("release") {
            val envKeystore = System.getenv("OMNI_KEYSTORE_PATH")
            storeFile = if (envKeystore != null) file(envKeystore) else file("dev-keystore.jks")
            storePassword = System.getenv("OMNI_KEYSTORE_PASSWORD") ?: "omni-dev-password"
            keyAlias = System.getenv("OMNI_KEY_ALIAS") ?: "omni-dev"
            keyPassword = System.getenv("OMNI_KEY_PASSWORD") ?: "omni-dev-password"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
