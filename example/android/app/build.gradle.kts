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
        // 复用 Play 上原生 example 的 app（`org.revdog.example`）：同一套测试商品与 license tester 名单，
        // 不另建 Play app。namespace 仍是模板的 `org.revdog.revenue_dog_example`（只决定 R / MainActivity 包名）。
        applicationId = "org.revdog.example"
        minSdk = 24
        targetSdk = 36
        // versionCode 来自 example/pubspec.yaml `version` 的 build number（100 起，高于原生 example 的 1）。
        // 不在这里 check()：纯 Gradle 任务（门禁 ⑦ 的 :revenue_dog:testDebugUnitTest）读的是 local.properties 里
        // 上次 flutter build 写下的值，可能是 1；「≥ 100」由 scripts/sdk-flutter-check.sh ⑦ 对 pubspec 校验。
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // 测试 app：debug 签名，`flutter run --release` 可直接跑（与 D9 验证宿主一致）。
            // 要传 Play 测试轨道时另用 ~/selah-keys/revdog-android-example 的 upload key 在仓库外重签。
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
