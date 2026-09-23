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
| `offerings.json`（M2） | `GET /v1/subscribers/{id}/offerings`（契约 §2.3）：`current_offering_id: "default"`；`default` = `$rc_monthly`→`premium_monthly`(plan `monthly-base`)、`$rc_annual`→`premium_annual`(plan `annual-base`)、`$rc_lifetime`→`lifetime_unlock`、`custom_pack`→`coin_pack_100`；`retention_offer` = `$rc_monthly`→`premium_monthly_discount`(plan `monthly-discount`，**商店侧故意缺失**)。两端共用一份：iOS 解码忽略 `platform_product_plan_identifier`（真实 Apple 响应无此键，一次性商品两端都无此键） |
| `offerings-current-dropped.json`（M2） | 同上，但 `current_offering_id: "retention_offer"`（指向会被剔空的 offering） |
| `store-products-ios.json`（M2） | **商店侧**商品字段清单 `{products: [...]}`，逐项喂 iOS `StoreProduct` 公开 init：`productIdentifier` / `localizedTitle` / `localizedDescription` / `price`（**十进制字符串**，用 `Decimal(string:)`，避免浮点）/ `currencyCode` / `localizedPriceString` / `subscriptionPeriod{unit, value}?` / `introductoryOffer{type, period{unit, value}, periodCount, price(字符串), displayPrice, isEligible}?`。4 个商品，**没有** `premium_monthly_discount` |
| `store-products-android.json`（M2） | 同上，逐项喂 `RevenueDogTestModels.storeProduct`（键 = 其参数名；`type` 为 `ProductType` 常量名 `SUBS\|INAPP`）；`subscriptionOptions[]` 喂 `subscriptionOption`（`productId` / `basePlanId` / `offerId?` / `pricingPhases` / `tags` / `offerToken`），`pricingPhases[]` 喂 `pricingPhase`（`billingPeriod` ISO / `recurrenceMode` 为 `RecurrenceMode` 常量名 / `billingCycleCount?` / `priceAmountMicros` / `priceCurrencyCode` / `formattedPrice`）。`defaultOption` 不在清单里，由工厂按既有规则推导 |

### `wire/`（原生插件必须产出的通道 map，也是 Dart 测试输入）

| 文件 | 形状 |
|---|---|
| `customer-info-minimal.json` / `customer-info-full.json` | §5.1 CustomerInfo（含 §5.1b SubscriptionInfo、§5.2 EntitlementInfos / EntitlementInfo、§5.5 非订阅 StoreTransaction） |
| `customer-info-original-purchase-date-null.json` | 权益 `originalPurchaseDate` = `latestPurchaseDate`（插件回退并记诊断 `hybrid_field_fallback`）；订阅明细 `originalPurchaseDate` 保持 `null`（契约可空） |
| `log-in-result.json` | `logIn` 返回 `{created: true, customerInfo: <minimal>}` |
| `purchase-result.json`（M2） | §5.5 `{customerInfo: <minimal>, storeTransaction: {transactionIdentifier: "2000000987654321", productIdentifier: "premium_monthly", purchaseDate: 1790164800000}}`（Dart 解码输入；原生侧按同形 map 断言，交易值为样例） |
| `offerings-ios.json` / `offerings-android.json`（M2） | §5.3 / §5.4 / §5.4b：`backend/offerings.json` + 对应 `store-products-*.json` 的期望输出，见下「Offerings」 |
| `offerings-current-dropped-ios.json` / `-android.json`（M2） | `backend/offerings-current-dropped.json` 的期望输出：`all` 只剩 `default`，`current: null` |
| `intro-eligibility-ios.json` / `-android.json`（M2） | §5.5，请求 `productIdentifiers: ["premium_monthly", "premium_annual", "unknown_product"]` 的期望输出，见下「IntroEligibility」 |
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
| `store-problem-2.json`（M2） | 插件合成：`getOfferings` 原生 offerings 非空但**全部** package 查不到商品（裁定 5）。非购买路径，**无** `userCancelled` 键 | 全部键逐字（`underlyingErrorMessage` = `store products unavailable`） |
| `product-not-found-5.json`（M2） | 插件合成：`purchasePackage` 按 `{offeringIdentifier, packageIdentifier}` 定位失败 / 该 package 无商品（B3） | `underlyingErrorMessage` 格式钉死：`package <packageIdentifier> not found in offering <offeringIdentifier>`（样例 `$rc_weekly` / `default`）；其余全部键逐字 |
| `invalid-argument-4.json`（M2） | 插件合成：Android 无当前 Activity（样例 `no current Activity`）或参数缺失（`missing argument <name>`）（B3） | `underlyingErrorMessage` 取二者之一；其余全部键逐字 |
| `pending-server-901.json` / `rejected-by-server-902.json` | 原生错误原样透传 | `code` / `details.code` / readable / `revdogCode` / `userCancelled` / 排障键的**有无**逐字；`message` / `underlyingErrorMessage` / 排障键的值为样例，原生测试按样例值构造源错误 |

合成错误的英文短句表在 `lib/src/errors.dart` 的 `syntheticErrorMessages`（0 / 1 / 2 / 4 / 5 / 12 / 20 / 22 / 23），原生插件逐字照抄。

购买路径（`purchasePackage`）的全部错误都带 `userCancelled`（仅码 1 为 `true`）；`getOfferings` / `restorePurchases` / `syncPurchases` / eligibility 的错误不带。
码 1 / 20 由插件按 D3 归一（原生取消 / 待定不是错误对象），`message` 取短句表、`underlyingErrorMessage` 为 `""`。

## Offerings（M2，设计 §5.3 / §5.4 / §5.4b）

### 剔除规则（插件 Mapper，裁定 5）

原生 offerings 里 package 的商店商品为空 = 商店查不到：

1. **部分**缺 → 剔除该 package，记 `sdk_warning{code: hybrid_package_dropped, detail}`；
2. 剔除后 offering 为空 → 整个 offering 从 `all` 去掉，记 `hybrid_offering_dropped`；`current` 因此不存在 → `current: null`（键仍在）+ warn；
3. 原生 offerings 非空但**全部** package 都查不到商品 → `getOfferings` 抛码 2（`errors/store-problem-2.json`）。原生测试：`backend/offerings.json` + **空商品表**。

本组 fixture：`premium_monthly_discount` 缺失 → `retention_offer` 唯一 package 被剔 → 该 offering 被去掉；`current` = `default`（`-current-dropped` 变体里 = `null`）。

### wire 形状

- `Offerings {all: {<id>: Offering}, current: Offering | null}`；`current` 与 `all[<id>]` 逐值相同（Dart 校验，不同 → 码 12）。
- `Offering {identifier, serverDescription, availablePackages: [Package]}`，package 保持后台顺序。
- `Package {identifier, packageType, offeringIdentifier, storeProduct, presentedOfferingContext}`；`packageType` 显式表：`$rc_lifetime|$rc_annual|$rc_six_month|$rc_three_month|$rc_two_month|$rc_monthly|$rc_weekly` → `lifetime|annual|six_month|three_month|two_month|monthly|weekly`，其它非空 id → `custom`，无法识别 → `unknown`；`offeringIdentifier` == `presentedOfferingContext.offeringIdentifier`。
- `presentedOfferingContext` 恒为 `{offeringIdentifier: <所属 offering>, placementIdentifier: null, targetingContext: null}`，出现在 Package、StoreProduct、（Android）每个 SubscriptionOption 上。
- `StoreProduct {identifier, title, description, priceAmountMicros, priceString, currencyCode, subscriptionPeriod, productCategory, introductoryPrice, defaultOption, subscriptionOptions, presentedOfferingContext}`，可空键**键必须在**。
- `IntroductoryPrice {priceAmountMicros, priceString, period, periodUnit, periodNumberOfUnits, cycles}`。
- Android：`SubscriptionOption {id, storeProductId, productId, pricingPhases, tags, isBasePlan, billingPeriod, isPrepaid, fullPricePhase, freePhase, introPhase, presentedOfferingContext}`；
  `PricingPhase {billingPeriod, recurrenceMode, billingCycleCount, price, offerPaymentMode}`；`Price {formatted, amountMicros, currencyCode}`；`Period {unit, value, iso8601}`。
  枚举：`recurrenceMode` `infinite_recurring|finite_recurring|non_recurring|unknown`，`offerPaymentMode` `free_trial|single_payment|discounted_recurring_payment|null`，`unit` `day|week|month|year|unknown`。
- **不上通道的文档化常量**（Dart 填）：`Offering.metadata = {}`、`Offering.webCheckoutUrl` / `Package.webCheckoutUrl = null`、便捷档位 `lifetime…weekly`（Dart 从 `availablePackages` 按类型取首个）、
  `StoreProduct.discounts` / `pricePerWeek|Month|Year(+String) = null`、`SubscriptionOption.installmentsInfo = null`。插件**不发**这些键。
- 金额只发 int micros，**不发 double**（`price` 由 Dart 派生 `micros / 10⁶`）。

### 两端差异点（同一份 backend fixture）

| 项 | iOS | Android |
|---|---|---|
| 订阅商品 `identifier` | `premium_monthly` | `premium_monthly:monthly-base`（同 RC） |
| `title` | StoreKit 标题 `Premium Monthly` | Play 标题 `Premium Monthly (RevenueDog Example)`（取 `title`，不是 `name`） |
| `introductoryPrice` 来源 | `introductoryOffer`：`$0.00`、`P1W`、`week`×1、cycles = `periodCount` | `defaultOption.freePhase ?? introPhase`：价串取 Play 原串 `Free`、周期按 Play 原始单位（`P1W` = week×1，**不改写成 7 天**）、cycles = `billingCycleCount ?? 1` |
| `subscriptionPeriod` | `P{value}{D\|W\|M\|Y}` | Play `period.iso8601` 原样 |
| `defaultOption` / `subscriptionOptions` | 恒 `null` | 订阅：`[base plan, offers…]` 按工厂输入顺序；`defaultOption` = 最长免费试用 → 最便宜 intro → base plan（`trial7`；年订阅为 `annual-base`）；一次性商品为 `null` |
| `SubscriptionOption.id` | — | `basePlanId` 或 `basePlanId:offerId`；`storeProductId` = `productId:basePlanId` |

## IntroEligibility（M2，设计 §1 #19 / §5.5）

`{<productId>: {status, description}}`，每个请求的 id 都必须有条目（Dart 校验，缺 → 码 12）。description 每状态一句固定英文（前三句取 RC iOS `IntroEligibility.description` 原文，unknown 取 RC Android hybrid 原文）：

| status | description | iOS 派生 |
|---|---|---|
| `eligible` | `Eligible for trial or introductory price.` | offerings 里有该商品、有 `introductoryOffer` 且 `isEligible == true` |
| `ineligible` | `Not eligible for trial or introductory price.` | 有 `introductoryOffer` 且 `isEligible == false` |
| `no_intro_offer_exists` | `Product does not have trial or introductory price.` | 有该商品、无 `introductoryOffer` |
| `unknown` | `Status indeterminate.` | 不在 offerings 里（本 fixture 的 `unknown_product`）|

Android 恒 `unknown`（同 RC）。iOS 按 `StoreProduct.identifier`（= 商店商品 id）匹配。

## Android 侧派生规则（主代理裁定，原生插件 Mapper 对照实现）

- `activeSubscriptions` = `subscriptionsByProductIdentifier` 中 `isActive == true` 的键（字典序排序）。
  不取原生 `CustomerInfo.activeSubscriptions`（Android 0.2.0 为活跃**权益**的商品 id，会含一次性商品 `lifetime_unlock`）。
- `allExpirationDates` / `allPurchaseDates` 的键 = 商品 id（**不带** base plan），`allPurchaseDates` 键集 == `allPurchasedProductIdentifiers`。
  不取原生 `allExpirationDatesByProduct` / `allPurchaseDatesByProduct`（Android 0.2.0 对带 `product_plan_identifier` 的订阅把键改写为 `productId:basePlanId`）。
- 非订阅商品授予的权益 `ownershipType`：Android 0.2.0 原生为 `UNKNOWN`（后端 non_subscriptions 不带该字段）→ 插件映射为 `purchased`（与 iOS 0.4.0 一致）。

## 其它已知的原生差异
- `originalApplicationVersion`：iOS 透传后端值，Android 恒 null（设计 §5.1 文档化常量）；本 fixture 后端即为 null，两端同值。
- `SubscriptionInfo.managementURL`：iOS 取顶层、Android 取每条订阅的 `management_url`；本 fixture 两者相同。
