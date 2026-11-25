# revenue_dog（RevenueDog Flutter SDK）

与 RevenueCat `purchases_flutter`（10.13.1）**同形**的 Dart 薄层，直接桥接 RevenueDog iOS / Android 原生 SDK。
Flutter 层不含任何支付逻辑：身份、缓存、上报、补报全在原生。设计：`docs/plan/flutter-sdk-design.md`（ADR 0100）。

> 当前状态：候选版 **0.1.0-rc.4**（原生钉 iOS 0.5.1 / Android 0.2.0）。候选版已在生产宿主中使用；
> 真机清单 F 系列（`docs/audit/2026-09-24-flutter-device-checklist.md`）跑完再出 0.1.0。各版变化见 `CHANGELOG.md`。

## 安装

git tag 依赖（公开只读镜像 `githubYiheng/revenue-dog-flutter`，D10；首个 tag 由发布流程定）：

```yaml
dependencies:
  revenue_dog:
    git:
      url: https://github.com/githubYiheng/revenue-dog-flutter.git
      ref: <tag>
```

前置：

- Flutter ≥ 3.44 / Dart ≥ 3.12；
- iOS 部署目标 ≥ 16，**必须启用 Swift Package Manager**（pubspec `flutter: config: enable-swift-package-manager: true` 或全局开启；本包不出 podspec，D8）；
- Android compileSdk 36、minSdk 24、Kotlin ≥ 2.1；购买用的 Activity launchMode 为 standard / singleTop。

## 从 purchases_flutter 迁移（两行）

```diff
- purchases_flutter: ^x.y.z
+ revenue_dog: { git: { url: ..., ref: <tag> } }
```

```diff
- import 'package:purchases_flutter/purchases_flutter.dart';
+ import 'package:revenue_dog/revenue_dog.dart';
```

其余代码不动；API key 换成 RevenueDog 的 public key（每个 app 一把）。宿主用到本包未提供的 RC API 会编译报错，按接入手册逐项处理。

```dart
await Purchases.setLogLevel(LogLevel.debug);        // 可在 configure 之前（R4）
await Purchases.configure(PurchasesConfiguration(apiKey)..diagnosticsEnabled = true);
Purchases.addCustomerInfoUpdateListener((info) { /* ... */ });
```

## API 面

与 RC `purchases_flutter` 10.13.1 同名同签名（设计 §1）。

| 里程碑 | `Purchases` 静态成员 | 模型 / 枚举 |
|---|---|---|
| M1 | `configure`、`setLogLevel`、`setLogHandler`、`isConfigured`、`logIn`、`logOut`、`appUserID`、`isAnonymous`、`getCustomerInfo`、`add/removeCustomerInfoUpdateListener`、`enableAdServicesAttributionTokenCollection` | `PurchasesConfiguration`、`CustomerInfo`、`EntitlementInfos` / `EntitlementInfo`、`SubscriptionInfo`、`StoreTransaction`、`LogInResult`、`PurchasesErrorCode` / `PurchasesErrorHelper` 等 |
| M2 | `getOfferings`、`purchase(PurchaseParams)`、`purchasePackage(Package)`（`@Deprecated`）、`restorePurchases`、`syncPurchases`、`checkTrialOrIntroductoryPriceEligibility` | `Offerings`、`Offering`、`Package` / `PackageType`、`PresentedOfferingContext`、`StoreProduct`（19 字段）、`IntroductoryPrice`、`PeriodUnit`、`ProductCategory`、`SubscriptionOption` / `PricingPhase` / `Price` / `Period` / `RecurrenceMode` / `OfferPaymentMode` / `InstallmentsInfo`（Android only）、`StoreProductDiscount`（只声明）、`PurchaseParams`（只有 `.package`）、`PurchaseResult`、`IntroEligibility` / `IntroEligibilityStatus` |
| rc.4 | 保留属性 setter（见下「广告转发（服务端）」）：`setEmail`、`setPhoneNumber`、`setATTConsentStatus`、`setIDFA`、`setIDFV`、`setFBAnonymousID`、`setFirebaseAppInstanceId`、`setTimezone`、`setAdMeasurementConsent`、`setFBCampaignIDs` | — |

```dart
final offerings = await Purchases.getOfferings();
final package = offerings.current?.monthly;
if (package != null) {
  try {
    final result = await Purchases.purchase(PurchaseParams.package(package));
  } on PlatformException catch (e) {
    if (PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError) { /* 用户取消 */ }
  }
}
```

## 广告转发（服务端）

项目在后台开了 Meta / TikTok / GA4 转发后，服务端把 **App Store** 的购买事件发给广告平台，发送时读该客户**最后一次同步**的订阅者属性。
setter 只落原生本地缓冲，随原生既有时机同步（回后台、购买上报搭车、logIn 前后）；值没变不会多发请求。`null` 或空串 = 删除。
全部要在 `configure` 之后调（之前调抛码 23）。

| setter | 属性 | 写什么、何时写 |
|---|---|---|
| `setATTConsentStatus` + `setIDFA` | `$attConsentStatus` / `$idfa` | **两个总在同一处紧挨着写**。启动时与每次回前台都重读 ATT 状态再写（用户可能在系统设置里撤销）。状态写 `authorized` / `denied` / `restricted` / `notDetermined`，服务端只把 `authorized` 当作已授权；未授权或已撤销时 `setIDFA(null)` |
| `setIDFV` | `$idfv` | 与上一行同一时机 |
| `setFBAnonymousID` | `$fbAnonId` | Facebook SDK 的匿名 ID，与上一行同一时机 |
| `setFirebaseAppInstanceId` | `$firebaseAppInstanceId` | Firebase Analytics 的 app instance id（GA4 转发用），与上一行同一时机 |
| `setTimezone` | `$timezone` | **IANA 标识**（如 `America/New_York`）。Dart 的 `DateTime.timeZoneName` 是缩写（`CST`），不能用，要从系统读 IANA 标识 |
| `setAdMeasurementConsent` | `$adMeasurementConsent` | App 内「分享使用 / 广告衡量数据」开关的当前值，启动时与开关变化时写；服务端只把 `true` 当作同意 |
| `setFBCampaignIDs` | `$fbCampaignIds` | 处理 Facebook 回流深链时，链接里 `campaign_ids` 的原串；服务端只给写入后 7 天内的事件带上 |
| `setEmail` / `setPhoneNumber` | `$email` / `$phoneNumber` | 有才写；服务端给 Meta / TikTok 发时做 SHA-256 |

**Android**：前 7 个照样透传到原生；`setTimezone` / `setAdMeasurementConsent` / `setFBCampaignIDs` 原生 0.2.0 没有，插件静默成功、不落数据。服务端也不转发 Google Play 事件，宿主不必判平台。

**沙盒 / TestFlight 的购买不要发给广告平台。** 判断「这笔购买」的环境，读这笔商品自己的订阅记录，取不到按沙盒、不发：

```dart
final result = await Purchases.purchase(PurchaseParams.package(package));
final isSandbox = result.customerInfo
        .subscriptionsByProductIdentifier[result.storeTransaction.productIdentifier]
        ?.isSandbox ??
    true;
```

`PurchaseResult.customerInfo` 是服务端确认这笔交易之后返回的，刚买的这笔订阅已在里面；`isSandbox` 由服务端按 Apple 签名交易的环境给出，插件原样带上。
不要读 `entitlements.all['pro']?.isSandbox`：它描述的是**当前授予该权益的商品**，不一定是这笔购买。一次性商品在 Flutter 层读不到环境（RC 模型的 `StoreTransaction` 没有这个字段），按上面的写法会落到「按沙盒、不发」。

App 自己用 Facebook SDK 记购买事件时的 `event_id`、关闭 Facebook SDK 自动内购记录、`external_id` 高级匹配、隐私披露里写「IP 地址」，与原生 iOS 宿主相同，
见 iOS SDK README「Meta Conversions API 转发（服务端）」（`github.com/githubYiheng/revenue-dog-ios`）。`transactionId` 取 `result.storeTransaction.transactionIdentifier`。

## 错误处理

所有错误都是 `PlatformException(code: '<十进制码>', message, details: Map)`，用 `PurchasesErrorHelper.getErrorCode(e)` 取枚举。
RC 的原写法全部有效（`code == '1'`、`details['userCancelled']`、`details['readableErrorCode'] == 'PurchaseCancelledError'`、匿名 logOut 码 22）。
**必须新增处理**：

| 码 | 枚举 | 含义 | 宿主应做 |
|---:|---|---|---|
| 901 | `purchasePendingServerConfirmation` | 已扣款，服务端尚未确认，SDK 会重放 | 提示「稍后到账」，**绝不引导重买** |
| 902 | `purchaseRejectedByServer` | 已扣款，服务端确定性拒绝 | 引导联系客服 |
| 20 | `paymentPendingError` | 付款待批准（钱还没扣） | 既不发权益也不报失败 |
| 2 | `storeProblemError` | 商店商品整体取不到等商店故障（`getOfferings` 全部商品查不到时 `underlyingErrorMessage` = `store products unavailable`） | 提示稍后再试 |

`details` 键：`code`（int）、`message`、`readableErrorCode` / `readable_error_code`（PascalCase，两端同值）、`revdogCode`（我方码名）、
`underlyingErrorMessage`（缺省 `""`），购买路径另有 `userCancelled`，排障键 `backendCode` / `httpStatusCode` / `requestId` 有值才出现。

## 与 purchases_flutter 的差异

| 项 | RC | RevenueDog | 依据 |
|---|---|---|---|
| 重复 `configure` | 换参数会替换原生实例 | 同参 → 复用、重挂订阅、打 warn；**异参 → 码 23**，换用户请用 `logIn` / `logOut` | R3 |
| `configure` 前的 `setLogLevel` | 纯静态 | 同样立即生效，另由插件记住并写进配置（原生 configure 会用配置覆盖日志级别） | R4 |
| 平台 | iOS / Android / macOS / Web | **只 iOS / Android**；其它平台任何方法抛 `UnsupportedPlatformException` | D13 |
| 错误码取法 | 按枚举下标，非数字抛 `FormatException` | 按码表查，非数字 / 未知 → `unknownError`，不抛 | D4 |
| 我方专有码 | — | 901 / 902（见上表），枚举末尾追加，RC 43 值原序不变 | D4 |
| `readableErrorCode` | iOS 为 `PURCHASE_CANCELLED`、Android 为 `PurchaseCancelledError` | 两端统一 PascalCase | D4 |
| 模型解码失败 | 裸 `TypeError` | `PlatformException` 码 12，`details.wireKey` 指出字段 | §5 总则 |
| 空交易 id | 吞成 `''` | 码 12 | 裁定 3 |
| 配置扩展 | — | `waitsForLogInBeforeSync`（iOS-only，logIn 前暂缓同步；Android 忽略）、`baseUrl`（只给测试 / staging 构建） | 裁定 9 |
| 不支持的配置取值 | — | `storeKitVersion: storeKit1`、`entitlementVerificationMode: informational`、`store: Store.amazon` → 码 23 | §1 #1 |
| 声明但不下发 | — | `preferredUILocaleOverride`、`automaticDeviceIdentifierCollectionEnabled`（我方无付费墙 / 归因网络） | §1 #1 |
| `Model.fromJson` 输入 | ISO 字符串 + 大写枚举 | 我方通道形状（epoch 毫秒 + lower_snake_case） | D2 |
| Android 试用周期 | 改写成天（1 周试用报「7 天」），零价串用设备 locale | 按 Play 原始单位（1 周试用报 `P1W` / `week`×1），价串取 Play 原串 | §5.4 |
| iOS 试用资格 | 直查 StoreKit | 由 offerings 里商品的介绍性优惠派生：有优惠且有资格 → eligible、有优惠无资格 → ineligible、无优惠 → noIntroOfferExists、不在 offerings 里 → unknown | §1 #19 |
| Android 试用资格 | 恒 unknown | 同 RC，恒 unknown（`Status indeterminate.`） | §1 #19 |
| 商店查不到的商品 | 不建该 package | 同：剔除 package、剔空的 offering 去掉（`current` 可能因此为 null）；**全部**查不到 → 码 2 | §5.3 |
| `syncPurchases` | Android 立即返回 | 两端都等原生完成 | §1 #24 |
| `StoreProduct.presentedOfferingContext` | iOS 不填 | 两端都填 | §5.4 |
| 价格折算 / 促销 / Web | `pricePerWeek/Month/Year(+String)`、`discounts`、`webCheckoutUrl`、`Offering.metadata` 有值 | 字段都声明，值恒为 `null` / `{}` | §5.3 / §5.4 |
| `PurchaseParams` | `.package` / `.storeProduct` / `.subscriptionOption` + 升降级、个性化价格、促销 / win-back、email 参数 | 只有 `PurchaseParams.package(package)`；`purchasePackage` 不带 RC 的升降级命名参数（D5） | §1 #21–22 |
| 订阅者属性 | `setAttributes` 与全套三方 ID setter、`collectDeviceIdentifiers`（自动采 IDFA / IDFV）；参数类型为 `String` | 只有广告转发读的 10 个（rc.4）；参数为 `String?`（RC 写法照样编译）；不自动采任何标识 | §5.8 / ADR 0245 |
| 未提供 | 付费墙、Web、广告、优惠签名、旧购买 API 等 | 不做（设计 §2「不建」） | ADR 0100 |

## 开发 / 门禁 / 发布

工具链：`fvm spawn 3.44.4 <子命令>`（本机没有全局 `flutter`；**不要**写成 `fvm spawn 3.44.4 flutter …`，pitfalls P44），`dart` = `~/fvm/versions/3.44.4/bin/dart`。

### 目录

| 路径 | 是什么 |
|---|---|
| `lib/` · `test/` | Dart 包与单测（fixture 三方对账，`test/fixtures/README.md`） |
| `ios/revenue_dog` · `ios/RevenueDogBridge` | iOS 插件（只 SPM）与纯映射包（可 `swift test`） |
| `android/` | Android 插件（Java）；Bridge JUnit 经 `example/android` 的 Gradle 跑 |
| `example/` | 测试 app（真机清单 F 系列的操作台，见下） |
| `api_tester/` | 公开 API 编译期守门 + 公开符号基线 `api-baseline/public-api.txt` |
| `scripts/gen_error_codes.dart` | 由 `sdk/error-codes.json` 生成 `lib/src/generated/error_codes.dart` |

### 日常

```bash
fvm spawn 3.44.4 analyze                  # 包 + example + api_tester 一起分析
fvm spawn 3.44.4 test                     # Dart 单测（含 fixture 对账、码表、版本一致）
~/fvm/versions/3.44.4/bin/dart run scripts/gen_error_codes.dart [--check]    # 改 sdk/error-codes.json 后重新生成 / 只比对
(cd ios/RevenueDogBridge && swift test)   # iOS Bridge 三方对账
(cd example/android && ./gradlew :revenue_dog:testDebugUnitTest)   # Android Bridge JUnit（先在 example 里 pub get）
```

### 测试 app（`example/`）

单页 Material 手测台：顶部状态（`isConfigured` / `appUserID` / `isAnonymous` / active entitlements / activeSubscriptions）、
每个公开方法一个按钮、档位列表点即购买、R3 同参 / 异参再 configure、F9 后台引擎（Android）、F15 不适用选项开关，
监听器回调与原生日志（`setLogHandler`）都进底部日志面板，错误统一显示 `code / readableErrorCode / revdogCode / userCancelled / underlyingErrorMessage`。

```bash
example/run.sh android [--release] [-d <id>]   # key：~/selah-keys/revdog-example-android-staging-pk.txt（staging 项目 revdog-example）
example/run.sh ios [--release] [-d <id>]       # key：~/selah-keys/revdog-staging-demo-pk.txt（staging 项目 demo），App Store 沙盒
example/run.sh ios-xcode                       # 只生成带 key 的 Xcode 配置，然后 Xcode 里 Run：走本地 RevenueDog.storekit
example/run.sh android --build --release       # 只构建不运行（--build 对 ios 同样可用）
```

- key 只经 `--dart-define-from-file` 的 0600 临时文件注入（`REVDOG_API_KEY_IOS` / `REVDOG_API_KEY_ANDROID` / `REVDOG_BASE_URL`，缺省 staging），脚本退出即删；**仓库里没有任何 key**。
- Android：applicationId `org.revdog.example`（复用 Play 上原生 example 的测试商品与 license tester），versionCode = `example/pubspec.yaml` 的 build number（100 起），release 用 debug 签名、开 R8 + 资源压缩；
  debug 构建额外信任用户 CA（抓包 / 注入 5xx 用），release 不信任。
- iOS：bundle id `ai.loomalabs.revenuedog.example`（同 `sdk/ios/Example`），部署目标 16；`ios/RevenueDog.storekit` 是 `sdk/ios/Tests/StoreKitTestSupport/RevenueDog.storekit` 的副本（门禁 ⑦ 校验一致），
  挂在 Runner scheme 的 StoreKit Configuration 上 —— 只在「Xcode 里点 Run」时生效，`flutter run` 不走它。本地交易绝不打线上（cutover-gate C1）。

### 门禁（`scripts/sdk-flutter-check.sh`，仓库根跑）

| # | 门禁 |
|---|---|
| ① | `gen_error_codes.dart --check` |
| ② | 插件版本：`pubspec.yaml` `version` == `lib/src/version.dart` == CHANGELOG 最新已发布条目 |
| ③ | 原生钉版本（D12）：两个 `Package.swift` 的 `exact:`、`android/build.gradle.kts` 的 `org.revdog:purchases:<v>` 与 `scripts/sdk-flutter-pin.lock` 一致，三份 `Package.resolved` 已解析到同一 iOS 版本 |
| ④ | 包 `analyze` + `test` |
| ⑤ | `api_tester` analyze（编译期守门）+ 公开符号清单 `--check` |
| ⑥ | iOS Bridge `swift test` |
| ⑦ | example：pub get → versionCode ≥ 100 → StoreKit 副本一致 → widget test → Android Bridge JUnit → `build apk --release` → `build ios --simulator --debug`（P45 顺序） |

`SKIP_BUILDS=1` 跳过 ⑦ 的两次整包构建（**跳过 ≠ 通过**）。D11 的「最低 + stable 双跑」：fvm stable 目前 3.41.4 < 下限，只跑 3.44.4；stable ≥ 3.44 后设 `EXTRA_FLUTTER_VERSIONS=stable`。

**公开 API 改动**：`api_tester/lib/api_tester.dart` 把每个公开符号按各种形态调一遍（显式类型、枚举穷尽 switch）；公开面变了先改它，再
`cd api_tester && ~/fvm/versions/3.44.4/bin/dart scripts/api_symbols.dart` 重新生成基线并 review 差异 —— 基线里删 / 改一行 = 主版本，只增 = 次版本。

### 改原生版本

```bash
scripts/sdk-flutter-pin.sh <ios-version> <android-version>   # 改写两个 Package.swift + build.gradle.kts + lock，Bridge resolve，跑门禁 ③
```

之后在 example 里跑一次 `build ios`（重写 example 的两份 `Package.resolved`）、CHANGELOG 记一笔、完整跑门禁。插件自身版本（`pubspec.yaml` + `lib/src/version.dart` + CHANGELOG）手动改，门禁 ② 校验。

### 发布（D10，git tag）

```bash
scripts/sdk-flutter-release.sh <version>            # dry-run：门禁（含完整 sdk-flutter-check）、subtree split、push --dry-run
scripts/sdk-flutter-release.sh <version> --apply    # 推镜像 githubYiheng/revenue-dog-flutter 的 main + 打 v<version>
```

发版前：CHANGELOG `[Unreleased]` 改成 `[<version>]`，pubspec / version.dart 同值，全部提交（工作区必须干净），真机清单 F 系列至少首轮跑过。
机制同 `scripts/sdk-release.sh`（iOS）/ `sdk-android-release.sh`：monorepo 是唯一开发源，镜像只读，tag 不可移动。
