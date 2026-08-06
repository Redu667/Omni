plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.omni.omni"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
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

flutter {
    source = "../.."
}
