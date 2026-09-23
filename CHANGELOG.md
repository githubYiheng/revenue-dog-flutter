# Changelog

语义化版本。公开面「减」或「改」= 主版本；只「增」= 次版本；无差异 = 修订号（公开符号基线 `api_tester/` M3 落地）。
tag 一经发布不可移动；首个 tag 由主代理定。`pubspec.yaml` 的 `version` 是插件版本唯一来源，与 `lib/src/version.dart` 一致（测试校验）。

## [Unreleased]

M1（Dart 侧）：包骨架与身份面。原生插件（iOS Swift / Android Java）仍是桩，全部方法回 notImplemented。

### 新增

- 包 `revenue_dog`（Flutter ≥ 3.44 / Dart ≥ 3.12，只声明 android + ios）；运行时依赖只有 `flutter` + `equatable`。
- 门面 `Purchases`（全静态，与 RC `purchases_flutter` 10.13.1 同名同签名）：`configure`、`setLogLevel`、`isConfigured`、
  `logIn`、`logOut`、`appUserID`、`isAnonymous`、`getCustomerInfo`、`enableAdServicesAttributionTokenCollection`、
  `addCustomerInfoUpdateListener` / `removeCustomerInfoUpdateListener`（最近值回放）、`setLogHandler`。
- `PurchasesConfiguration`：RC 10.13.1 字段全量声明 + 我方扩展 `waitsForLogInBeforeSync`（iOS-only）、`baseUrl`（测试 / staging）。
- 模型（equatable 值相等，RC 字段全量）：`CustomerInfo`、`EntitlementInfos`、`EntitlementInfo`、`SubscriptionInfo`、`StoreTransaction`、`LogInResult`；
  枚举 `Store`、`PeriodType`、`OwnershipType`、`VerificationResult`、`LogLevel`、`StoreKitVersion`、`EntitlementVerificationMode`、
  `PurchasesAreCompletedByType` 及 `PurchasesAreCompletedBy*`（值集与顺序照 RC）。
- 错误：`PurchasesErrorCode`（RC 43 值原序 + `notImplementedError` / `purchasePendingServerConfirmation` / `purchaseRejectedByServer`），
  由 `scripts/gen_error_codes.dart` 从 `sdk/error-codes.json` 生成；`PurchasesErrorHelper.getErrorCode` 按码表查找，非数字 / 未知码 → `unknownError`。
- `UnsupportedPlatformException`：iOS / Android 以外的平台调用任何方法时抛出。
- R3：同一进程重复 `configure` 同参 → 复用并重挂订阅（warn）；异参 → 码 23。R4：`configure` 前的 `setLogLevel` 随配置下发。
- 通道契约 fixture：`test/fixtures/backend/`（后端响应形状）+ `test/fixtures/wire/`（原生插件必须产出的通道 map），三方对账规则见 `test/fixtures/README.md`。
