pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// 工具链对齐首批宿主 Selah：AGP 8.9.1 / KGP 2.1.0 / Gradle 8.12（设计 §7「测试 app」、ADR 0099、
// D9 报告 §3.2）。改这里 = 改「插件在最低宿主工具链上能编」这条验证，先对照 Selah 再动。
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

// 与 D9 B1 的宿主同形：settings 声明仓库，根 build 另有 Selah 式 `allprojects { repositories }`。
// 在 PREFER_PROJECT 模式下后者生效、前者被忽略 —— 这正是插件必须用 `rootProject.allprojects`
// 自注入 maven.revdog.org 的原因（ADR 0099）；这里保留声明，以便宿主两种写法都被覆盖。
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://maven.revdog.org/releases")
            content { includeGroup("org.revdog") }
        }
    }
}

include(":app")
