import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.cycmotor.trax"
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
        applicationId = "com.cycmotor.trax"
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

// === Release build guard =================================================
// Refuse any *Release* assemble that wasn't routed through
// scripts/build_apk.sh (which calls scripts/release_naming.sh to allocate
// the next YYMMDDNN versionCode for today). This catches the common
// failure mode of running `flutter build apk --release` directly — that
// path uses the stale `+YYMMDDNN` baked into pubspec.yaml and produces an
// APK with an OLDER versionCode than what's already on testers' devices,
// blocking the install with INSTALL_FAILED_VERSION_DOWNGRADE.
//
// Bypass (rare, e.g. local debugging of Gradle issues):
//   TRAX_SKIP_RELEASE_VERSION_GUARD=1 flutter build apk --release
gradle.taskGraph.whenReady {
    val isRelease = allTasks.any { it.name.contains("Release") &&
        (it.name.startsWith("assemble") || it.name.startsWith("bundle") ||
         it.name.startsWith("package")) }
    if (!isRelease) return@whenReady
    if (System.getenv("TRAX_SKIP_RELEASE_VERSION_GUARD") == "1") return@whenReady

    val code = flutter.versionCode
    val todayPrefix = LocalDate
        .now(ZoneId.of("Asia/Shanghai"))
        .format(DateTimeFormatter.ofPattern("yyMMdd"))
        .toInt()
    val codePrefix = code / 100  // YYMMDDNN → YYMMDD

    if (codePrefix != todayPrefix) {
        throw GradleException(
            """
            |
            |============================================================
            |  TRAX release build refused.
            |============================================================
            |  versionCode = $code   (YYMMDD prefix = $codePrefix)
            |  expected today (Asia/Shanghai) = $todayPrefix
            |
            |  Always build release APKs via:
            |      ./scripts/build_apk.sh           # local only
            |      ./scripts/build_apk.sh --deploy  # local + OTA upload
            |
            |  That script:
            |    1. allocates the next YYMMDDNN versionCode for today via
            |       scripts/release_naming.sh (also dedupes with the
            |       server's /var/www/trax-download/ listing).
            |    2. injects --build-name / --build-number into Flutter so
            |       the resulting APK can install over older builds
            |       without an INSTALL_FAILED_VERSION_DOWNGRADE.
            |    3. copies the arm64-v8a slice to
            |       build/dist/trax-test-YYMMDD-NN.apk.
            |
            |  Do NOT run `flutter build apk --release` directly.
            |  See AGENTS.md and docs (or pubspec.yaml header comment).
            |
            |  Emergency bypass (will produce a stale versionCode):
            |      TRAX_SKIP_RELEASE_VERSION_GUARD=1 ./scripts/build_apk.sh
            |============================================================
            """.trimMargin()
        )
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
