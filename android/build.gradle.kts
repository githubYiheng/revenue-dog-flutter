group = "org.revdog.flutter"
version = "1.0"

// 插件 Android 侧：纯 Java（ADR 0099 决定 1），不引入 Kotlin 源码。
// buildscript 的 AGP 与测试 app / 首批宿主 Selah 一致（8.9.1）；宿主已加载 AGP 时以宿主为准。
buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.9.1")
    }
}

// 对照 RC purchases_flutter `android/build.gradle`：往宿主根工程的所有 project 注入仓库。
// Selah 式宿主在根 build 用 `allprojects { repositories }`，PREFER_PROJECT 模式下 settings 里声明的
// 仓库对插件的传递依赖无效（D9 报告 §3.2 B1 首跑失败），所以由插件自注入，宿主不改根构建文件（ADR 0099）。
rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://maven.revdog.org/releases")
            content { includeGroup("org.revdog") }
        }
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "org.revdog.flutter"

    compileSdk = 36

    // 宿主 Selah 用 Java 11 target（ADR 0099 后果）。
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        minSdk = 24
    }

    testOptions {
        // Bridge 测试是纯 JVM（不用 Robolectric）：android.jar 里未 mock 的方法（如 SDK 内部 Logger 的
        // android.util.Log）返回默认值而不是抛异常。android.net.Uri 另有测试替身，见 src/test/java/android/net/Uri.java。
        unitTests.isReturnDefaultValues = true
        unitTests.all {
            it.outputs.upToDateWhen { false }
            // 三方对账 fixture（设计 §7）。工作目录就是本模块目录，另用系统属性给绝对路径兜底。
            it.systemProperty("revdog.fixturesDir", file("../test/fixtures").absolutePath)
            it.testLogging {
                events("passed", "skipped", "failed")
                exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
            }
        }
    }
}

dependencies {
    // 精确版本（D12）；`implementation` 不把 SDK 与 billing / coroutines 放上宿主 compile classpath（ADR 0099）。
    implementation("org.revdog:purchases:0.2.0")

    testImplementation("junit:junit:4.13.2")
    // Android 单测里 org.json 是 stub，塞一个真实实现（对照 sdk/android/gradle/libs.versions.toml 的 `json`）。
    testImplementation("org.json:json:20260814")
}
