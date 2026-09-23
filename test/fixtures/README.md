# 通道契约 fixture（三方对账）

设计依据：`docs/plan/flutter-sdk-design.md` §5（wire 契约）、§7（测试基建）。本目录是 §5 的可执行版，**路径固定**，改形状 = 改契约。

## 三方对账规则

| 方 | 输入 | 断言 |
|---|---|---|
| iOS 插件（`RevenueDogBridge` 测试） | `backend/*.json` → 原生 `CustomerInfo`（公开 `init(from:)` / wire 解码入口） | Bridge Mapper 产出的 map **==** `wire/` 同名文件（逐键、逐值，含 null 键） |
| Android 插件（JUnit） | `backend/*.json` → M0 测试工厂（后端 JSON → 模型） | 同上 |
| Dart（`test/wire_fixtures_test.dart`） | `wire/*.json`（经 `StandardMessageCodec` 往返，得到真机同款 `Map<Object?, Object?>`） | 解码后的模型字段与三条不变式 |

任一方改形状，另两方红。

### 参照时间

`isActive` 的名义参照时间 = **`request_date`（2026-09-23T12:00:00Z）**；原生在 `request_date` 距当前超过 3 天后会改用本机时钟。
能注入 now 的一端（iOS `CustomerInfo(wireModel:now:)`）可注入 `request_date`，不能注入的（Android 测试工厂）直接用本机时钟。
**所有 fixture 的活跃 / 过期结论在 2026–2098 年间与本机时钟无关**：
活跃订阅 / 权益到期 = 2099-01-01T00:00:00Z（宽限期 null），已过期订阅的到期、宽限期、退订、扣款问题时间全部在 2020 年，
所以不论参照时间取 `request_date` 还是本机时钟，判定都一样（Android 测试工厂不能注入 now 也不受影响）。

### wire 形状总则（设计 §5 总则）

- 键名 = RC Dart 字段名；map 键按字母序、列表按下述顺序（JSON 对象键序对 map 等价比较无影响，列表顺序有影响）。
- 时间 = epoch 毫秒 `int`；可空时间为 `null`（**键必须在**）。
- 枚举 = lower_snake_case：`store` 为我方小写原样（`app_store` / `play_store` …），`ownershipType` 为 `purchased|family_shared|unknown`，
  `periodType` 为 `intro|normal|trial|prepaid|unknown`，`verification` 恒 `not_requested`。
- 列表顺序：`activeSubscriptions` / `allPurchasedProductIdentifiers` 字典序升序；`nonSubscriptionTransactions` 按 `purchaseDate` 升序、同时间按 `transactionIdentifier` 升序。
- 非订阅商品授予的权益 `ownershipType` = `purchased`（iOS 原生口径；Android 原生给 UNKNOWN 时由插件映射，主代理裁定）。
- `CustomerInfo.subscriptionsByProductIdentifier.*.managementURL` = 顶层 `managementURL`（iOS 原生只有一份；backend fixture 里每条订阅的 `management_url` 与顶层相同，使两端同值）。

### 三条不变式（Dart 测试逐 fixture 断言，原生产出的 map 也必须满足）

1. `entitlements.active` 键集 == `entitlements.all` 中 `isActive == true` 的键集；
2. `activeSubscriptions` == `subscriptionsByProductIdentifier` 中 `isActive == true` 的键；
3. `allPurchaseDates` 键集 == `allPurchasedProductIdentifiers`（订阅 ∪ 一次性商品，**用原始商品 id**）。

## 文件与用途

### `backend/`（我方后端 `GET /v1/subscribers/{id}` 响应体，契约 `api-contract-v1.md` §2.2：snake_case、ISO 8601 秒精度）

| 文件 | 场景 |
|---|---|
| `customer-info-minimal.json` | 匿名新用户（`$RDAnonymousID:` + 32 hex）：entitlements / subscriptions / non_subscriptions 全空，`management_url` 等为 null |
| `customer-info-full.json` | `premium` ← 活跃 Play 订阅 `premium_monthly`（会续订，`display_name` / `product_plan_identifier` 有值）；`legacy_pro` ← 已过期 Play 订阅 `pro_annual`（`unsubscribe_detected_at`、`billing_issues_detected_at`、`grace_period_expires_date` 有值，全部在 2020 年）；`lifetime` ← 一次性商品 `lifetime_unlock`（App Store，终身）；另有一次性 `coin_pack_100`（不关联权益）。共 2 笔非订阅交易 |
| `customer-info-original-purchase-date-null.json` | `premium` 关联订阅的 `original_purchase_date` 为 null：权益回退规则（裁定 3） |

### `wire/`（原生插件必须产出的通道 map，也是 Dart 测试输入）

| 文件 | 形状 |
|---|---|
| `customer-info-minimal.json` / `customer-info-full.json` | §5.1 CustomerInfo（含 §5.1b SubscriptionInfo、§5.2 EntitlementInfos / EntitlementInfo、§5.5 非订阅 StoreTransaction） |
| `customer-info-original-purchase-date-null.json` | 权益 `originalPurchaseDate` = `latestPurchaseDate`（插件回退并记诊断 `hybrid_field_fallback`）；订阅明细 `originalPurchaseDate` 保持 `null`（契约可空） |
| `log-in-result.json` | `logIn` 返回 `{created: true, customerInfo: <minimal>}` |
| `errors/*.json` | §5.6 错误信封 `{code: "<十进制>", message, details}` |

### 错误信封（`errors/`）

`details` 必有 `code`（int）、`message`（== 外层 `message`）、`readableErrorCode` == `readable_error_code`（`lib/src/generated/error_codes.dart` 的 `readableErrorCodeByNumber`）、
`revdogCode`（我方 `code.name`）、`underlyingErrorMessage`（缺省 `""`）；可选 `userCancelled`（仅购买路径：码 1 为 true，其余 false）、
`backendCode` / `httpStatusCode` / `requestId`（有值才发键）。不允许其它键（码 12 由 Dart 合成时另带 `wireKey`，不属于原生信封）。

| 文件 | 来源 | 严格比对 |
|---|---|---|
| `purchase-cancelled-1.json` | 插件合成（D3：两端取消归一） | 全部键逐字 |
| `payment-pending-20.json` | 插件合成（D3：两端待定归一） | 全部键逐字 |
| `log-out-anonymous-22.json` | 插件在 logOut 路径把我方 14 映射为 22（裁定 6），`revdogCode` 仍为 `invalidAppUserIdError` | `message` 取码表短句；`underlyingErrorMessage` 为原生 message（样例值） |
| `configuration-23.json` | 插件合成（未配置守卫） | `message` 取码表短句；`underlyingErrorMessage` 为样例 |
| `unexpected-backend-12.json` | 原生码 12（契约非空键为 nil 等） | `message` 取码表短句；其余为样例 |
| `pending-server-901.json` / `rejected-by-server-902.json` | 原生错误原样透传 | `code` / `details.code` / readable / `revdogCode` / `userCancelled` / 排障键的**有无**逐字；`message` / `underlyingErrorMessage` / 排障键的值为样例，原生测试按样例值构造源错误 |

合成错误的英文短句表在 `lib/src/errors.dart` 的 `syntheticErrorMessages`（0 / 1 / 2 / 4 / 5 / 12 / 20 / 22 / 23），原生插件逐字照抄。

## Android 侧派生规则（主代理裁定，原生插件 Mapper 对照实现）

- `activeSubscriptions` = `subscriptionsByProductIdentifier` 中 `isActive == true` 的键（字典序排序）。
  不取原生 `CustomerInfo.activeSubscriptions`（Android 0.2.0 为活跃**权益**的商品 id，会含一次性商品 `lifetime_unlock`）。
- `allExpirationDates` / `allPurchaseDates` 的键 = 商品 id（**不带** base plan），`allPurchaseDates` 键集 == `allPurchasedProductIdentifiers`。
  不取原生 `allExpirationDatesByProduct` / `allPurchaseDatesByProduct`（Android 0.2.0 对带 `product_plan_identifier` 的订阅把键改写为 `productId:basePlanId`）。
- 非订阅商品授予的权益 `ownershipType`：Android 0.2.0 原生为 `UNKNOWN`（后端 non_subscriptions 不带该字段）→ 插件映射为 `purchased`（与 iOS 0.4.0 一致）。

## 其它已知的原生差异
- `originalApplicationVersion`：iOS 透传后端值，Android 恒 null（设计 §5.1 文档化常量）；本 fixture 后端即为 null，两端同值。
- `SubscriptionInfo.managementURL`：iOS 取顶层、Android 取每条订阅的 `management_url`；本 fixture 两者相同。
