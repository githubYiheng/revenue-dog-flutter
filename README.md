# revenue_dog（RevenueDog Flutter SDK）

与 RevenueCat `purchases_flutter`（10.13.1）**同形**的 Dart 薄层，直接桥接 RevenueDog iOS / Android 原生 SDK。
Flutter 层不含任何支付逻辑：身份、缓存、上报、补报全在原生。设计：`docs/plan/flutter-sdk-design.md`（ADR 0100）。

> 当前状态：**M1 Dart 侧**。原生插件仍是桩（全部方法回 notImplemented），M1 原生实现、M2 目录与购买随后补齐；不要在宿主里接入。

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

## 错误处理

所有错误都是 `PlatformException(code: '<十进制码>', message, details: Map)`，用 `PurchasesErrorHelper.getErrorCode(e)` 取枚举。
RC 的原写法全部有效（`code == '1'`、`details['userCancelled']`、`details['readableErrorCode'] == 'PurchaseCancelledError'`、匿名 logOut 码 22）。
**必须新增处理**：

| 码 | 枚举 | 含义 | 宿主应做 |
|---:|---|---|---|
| 901 | `purchasePendingServerConfirmation` | 已扣款，服务端尚未确认，SDK 会重放 | 提示「稍后到账」，**绝不引导重买** |
| 902 | `purchaseRejectedByServer` | 已扣款，服务端确定性拒绝 | 引导联系客服 |
| 20 | `paymentPendingError` | 付款待批准（钱还没扣） | 既不发权益也不报失败 |
| 2 | `storeProblemError` | 商店商品整体取不到等商店故障 | 提示稍后再试 |

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
| 未提供 | 付费墙、Web、广告、优惠签名、旧购买 API、订阅者属性等 | 不做（设计 §2「不建」） | ADR 0100 |

## 开发

```bash
fvm spawn 3.44.4 test            # 单测（含 fixture 对账、码表一致性、版本一致性）
fvm spawn 3.44.4 analyze
~/fvm/versions/3.44.4/bin/dart run scripts/gen_error_codes.dart          # 改 sdk/error-codes.json 后重新生成
~/fvm/versions/3.44.4/bin/dart run scripts/gen_error_codes.dart --check  # 只比对
```

通道契约 fixture 与三方对账规则见 `test/fixtures/README.md`。
