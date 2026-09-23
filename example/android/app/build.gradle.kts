plugins {
    id("com.android.application")
    // 对齐 Selah：显式 apply kotlin-android（KGP 2.1.0）。宿主 MainActivity 仍是模板 Java。
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.revdog.revenue_dog_example"
    // 对齐 Selah：compileSdk 36 / minSdk 24 / targetSdk 36，Java 11（ADR 0099 后果）。
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        applicationId = "org.revdog.revenue_dog_example"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // 测试 app：debug 签名，`flutter run --release` 可直接跑。
            signingConfig = signingConfigs.getByName("debug")
            // 对齐 Selah：release 开 R8 + 资源压缩（F11 冷启动验证的前提）。
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
    }
}

flutter {
    source = "../.."
}
