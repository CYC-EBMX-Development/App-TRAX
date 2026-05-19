plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.trax.trax_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.trax.trax_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // AMap Android SDK key is read from the env var AMAP_ANDROID_SDK_KEY.
        // Sourced by scripts/run_android.sh + scripts/build_apk.sh from
        // ~/trax-deploy.env so it never gets committed.
        manifestPlaceholders["AMAP_ANDROID_SDK_KEY"] =
            (System.getenv("AMAP_ANDROID_SDK_KEY") ?: "")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

// === OTA versioning override ============================================
// We use an 8-digit YYMMDDNN versionCode (see scripts/build_apk.sh and
// lib/common/services/app_update_service.dart). When --split-per-abi is
// enabled, Flutter's gradle plugin auto-shifts versionCode by
// +1000/+2000/+4000 per ABI so Play Store can treat them as distinct
// uploads. That shift corrupts the "DD" digits of our scheme:
//   base 26051805 → arm64-v8a output becomes 26053805,
//   which the OTA client then renders as "260538-05".
//
// We self-distribute only the arm64-v8a slice via OTA, so there is no
// uniqueness requirement. Force every split output back to the base
// versionCode that --build-number passed in.
android.applicationVariants.all {
    outputs.all {
        (this as com.android.build.gradle.internal.api.ApkVariantOutputImpl)
            .versionCodeOverride = flutter.versionCode
    }
}

// AMap native SDKs.
// The amap_flutter_map / amap_flutter_location plugins declare these as
// `compileOnly`, so the app must bring them in at runtime. The 3D map AAR
// already bundles the location classes (com.amap.api.location.*), so we do
// NOT add the separate location artifact — that would cause duplicate-class
// errors at D8 time.
dependencies {
    implementation("com.amap.api:3dmap:9.7.0")
}
