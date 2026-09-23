# Changelog

语义化版本。公开面「减」或「改」= 主版本；只「增」= 次版本；无差异 = 修订号（判据 = 公开符号基线 `api_tester/api-baseline/public-api.txt` 的差异：有删 / 改行即主版本）。
tag 一经发布不可移动；首个 tag 由主代理定。`pubspec.yaml` 的 `version` 是插件版本唯一来源，与 `lib/src/version.dart` 一致（测试校验）。

## [Unreleased]

## [0.1.0-rc.1] - 2026-09-23

**首个候选版（真机 F 系列未跑完前不出 0.1.0）**：内容 = 下列 0.1.0 草稿全部；原生钉 iOS 0.4.1 / Android 0.2.0。

> **0.1.0 草稿**：内容已按可发布整理；发版时由主代理把本标题改成 `## [0.1.0] - <日期>`（门禁 ② 与 `scripts/sdk-flutter-release.sh` 据此校验），再新开空的 `[Unreleased]`。

首个版本：与 RevenueCat `purchases_flutter` 10.13.1 **同形**的 Dart 薄层，直接桥接 RevenueDog 原生 SDK（iOS 0.4.1 / Android 0.2.0）。
Flutter 层不含任何支付逻辑：身份、缓存、上报、补报全在原生（ADR 0100，`docs/plan/flutter-sdk-design.md`）。

### 新增

- 包 `revenue_dog`：Flutter ≥ 3.44 / Dart ≥ 3.12，只声明 android + ios（D13）；运行时依赖只有 `flutter` + `equatable`。
- 门面 `Purchases`（全静态，名字 / 签名逐字照 RC）：
  - 配置与日志：`configure`、`setLogLevel`（可在 configure 之前，R4）、`setLogHandler`、`isConfigured`；
  - 身份：`logIn`、`logOut`、`appUserID`、`isAnonymous`；
  - CustomerInfo：`getCustomerInfo`、`addCustomerInfoUpdateListener` / `removeCustomerInfoUpdateListener`（最近值回放；每个引擎一条原生订阅，D14）；
  - 目录与购买：`getOfferings`、`purchase(PurchaseParams.package(...))`、`purchasePackage`（`@Deprecated` 薄包装，D5）、`restorePurchases`、
    `syncPurchases`（两端都等原生完成）、`checkTrialOrIntroductoryPriceEligibility`；
  - 归因：`enableAdServicesAttributionTokenCollection`（Android 静默成功）。
- `PurchasesConfiguration`：RC 10.13.1 字段全量声明 + 我方扩展 `waitsForLogInBeforeSync`（iOS-only）、`baseUrl`（只给测试 / staging 构建）。
- 模型（RC 字段全量、equatable 值相等、手写 `fromJson`）：`CustomerInfo`、`EntitlementInfos` / `EntitlementInfo`、`SubscriptionInfo`（19 字段）、`StoreTransaction`、`LogInResult`、
  `Offerings` / `Offering`（便捷档位由 `availablePackages` 派生）、`Package`、`PresentedOfferingContext` / `PresentedOfferingTargetingContext`、`StoreProduct`（19 字段）、`IntroductoryPrice`、
  `SubscriptionOption` / `PricingPhase` / `Price` / `Period` / `InstallmentsInfo`（Android only）、`StoreProductDiscount`（只声明）、`PurchaseParams`、`PurchaseResult`、`IntroEligibility`；
  RC 弃用扩展 `ExtendedPackage` / `ExtendedStoreProduct` / `ExtendedSubscriptionOption` 与 `OfferingX` / `PackageListX`。
- 枚举（值集与顺序照 RC）：`Store`、`PeriodType`、`OwnershipType`、`VerificationResult`、`LogLevel`、`StoreKitVersion`、`EntitlementVerificationMode`、`PurchasesAreCompletedByType`、
  `PackageType`、`PeriodUnit`、`ProductCategory`、`RecurrenceMode`、`OfferPaymentMode`、`IntroEligibilityStatus`；`PurchasesAreCompletedBy*` 三个类。
- 错误：`PurchasesErrorCode` = RC 43 值原序 + `notImplementedError`（900）/ `purchasePendingServerConfirmation`（901）/ `purchaseRejectedByServer`（902），
  由 `sdk/error-codes.json` 生成；`PurchasesErrorHelper.getErrorCode` 按码表查，非数字 / 未知码 → `unknownError`（不抛）。
  所有错误都是 `PlatformException(code: '<十进制码>', details: {code, message, readableErrorCode, readable_error_code, revdogCode, underlyingErrorMessage, …})`，两端同值。
- `UnsupportedPlatformException`：iOS / Android 以外的平台调用任何方法时抛出。
- 原生插件：iOS Swift（只 SPM，iOS 16，D7 / D8）+ 纯映射包 `RevenueDogBridge`；Android Java（minSdk 24 / compileSdk 36，
  `rootProject.allprojects` 自注入 `https://maven.revdog.org/releases`，宿主不改根构建文件，ADR 0099）。
- 插件诊断（经原生内部入口记 `sdk_warning`）：`hybrid_option_ignored`、`hybrid_field_fallback`、`hybrid_package_dropped`、`hybrid_offering_dropped`、`hybrid_duplicate_configure`。
- 请求头：原生带 `X-Platform-Flavor: flutter` + `X-Platform-Flavor-Version: <本包版本>`（R1）。

### 与 purchases_flutter 的行为差异（宿主须知，详见 README）

- 同一进程重复 `configure`：同参 → 复用并重挂订阅（warn）；**异参 → 码 23**，换用户用 `logIn` / `logOut`（R3；RC 会替换实例）。
- 新增必须处理的码：**901**（已扣款待服务端确认，提示稍后到账、绝不引导重买）、**902**（服务端拒绝，引导客服）；20（待批准）、2（商店商品整体取不到）照 RC 语义。
- `readableErrorCode` 两端统一 PascalCase；模型解码失败 / 空交易 id → 码 12（RC 抛 `TypeError` / 吞成 `''`）。
- 商店查不到的 package 剔除、剔空的 offering 去掉（`current` 可能为 null），全部查不到 → 码 2。
- Android 试用周期按 Play 原始单位（1 周试用报 `P1W`，RC 报 7 天）；iOS 试用资格由 offerings 派生（RC 直查 StoreKit）；Android 恒 unknown（同 RC）。
- 只支持 iOS / Android；iOS 只 SPM（宿主须启用 Swift Package Manager）；`storeKitVersion: storeKit1`、`entitlementVerificationMode: informational`、`store: Store.amazon` → 码 23。

### 依赖

- 原生精确钉版本（D12）：iOS `revenue-dog-ios` **0.4.1**（`exact:`）、Android `org.revdog:purchases:`**0.2.0**；改版本只走 `scripts/sdk-flutter-pin.sh`（仓库根）。

### 工程（不进宿主运行时）

- 测试 app `example/`（真机清单 F 系列操作台；Android `org.revdog.example` versionCode 100 起、iOS `ai.loomalabs.revenuedog.example` + 本地 `RevenueDog.storekit`；key 由 `example/run.sh` 注入）。
- `api_tester/`：公开 API 编译期守门 + 公开符号基线 `api-baseline/public-api.txt`（51 个顶层符号）。
- 门禁 `scripts/sdk-flutter-check.sh`（七道）、钉版本 `scripts/sdk-flutter-pin.sh` + `scripts/sdk-flutter-pin.lock`、发布 `scripts/sdk-flutter-release.sh`（镜像 `githubYiheng/revenue-dog-flutter`，git tag）。
- 通道契约 fixture：`test/fixtures/backend/` + `test/fixtures/wire/`，三方对账（Dart 141 / Android JUnit 26 / iOS Bridge 44）。
