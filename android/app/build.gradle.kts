import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "sevendash.app"
    compileSdk = flutter.compileSdkVersion
    buildToolsVersion = "35.0.0"
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // App-bundle size reduction. SAFE: these never touch the call audio path —
    // the core Agora RTC engine, JNI wrapper, video encoder, audio codecs and AI
    // noise/echo-suppression libraries are all KEPT. Only optional feature
    // extensions the app never enables are stripped, plus the emulator-only
    // x86/x86_64 architectures (no shipping phone uses them).
    packaging {
        jniLibs {
            excludes += listOf(
                "**/x86/**",
                "**/x86_64/**",
                "**/libagora_lip_sync_extension.so",          // lip-sync avatar
                "**/libagora_clear_vision_extension.so",      // low-light enhance
                "**/libagora_content_inspect_extension.so",   // content moderation
                "**/libagora_face_capture_extension.so",      // face capture
                "**/libagora_face_detection_extension.so",    // face detection
                "**/libagora_segmentation_extension.so",      // virtual background
                "**/libagora_spatial_audio_extension.so",     // spatial audio
                "**/libagora_audio_beauty_extension.so",      // voice beautifier
                "**/libagora_video_av1_encoder_extension.so", // AV1 (H264/VP8 used)
                "**/libagora_video_quality_analyzer_extension.so",
                "**/libagora_screen_capture_extension.so"     // screen sharing
            )
        }
    }

    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    defaultConfig {
        applicationId = "sevendash.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            // Sign debug builds with the same key as release so that debug and
            // release APKs can be swapped without hitting INSTALL_FAILED_UPDATE_INCOMPATIBLE.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.core:core:1.16.0")
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("com.google.android.material:material:1.12.0")
}
