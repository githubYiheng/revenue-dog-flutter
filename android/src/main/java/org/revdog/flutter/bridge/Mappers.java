package org.revdog.flutter.bridge;

import org.revdog.purchases.OwnershipType;
import org.revdog.purchases.ProductType;
import org.revdog.purchases.PurchasesErrorCode;
import org.revdog.purchases.customerinfo.CustomerInfo;
import org.revdog.purchases.customerinfo.EntitlementInfo;
import org.revdog.purchases.customerinfo.NonSubscriptionTransaction;
import org.revdog.purchases.customerinfo.SubscriptionInfo;
import org.revdog.purchases.models.OfferPaymentMode;
import org.revdog.purchases.models.Period;
import org.revdog.purchases.models.Price;
import org.revdog.purchases.models.PricingPhase;
import org.revdog.purchases.models.StoreProduct;
import org.revdog.purchases.models.StoreTransaction;
import org.revdog.purchases.models.SubscriptionOption;
import org.revdog.purchases.offerings.Offering;
import org.revdog.purchases.offerings.Offerings;
import org.revdog.purchases.offerings.Package;
import org.revdog.purchases.offerings.PackageType;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Date;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeSet;

/**
 * 原生模型 → 通道 wire map（设计 §5.1 / 5.1b / 5.2 / 5.5；可执行版 = {@code test/fixtures/wire/*.json}）。
 *
 * 总则：键名 = RC Dart 字段名；可空键也必须在（值为 null）；时间 = epoch 毫秒 {@link Long}；
 * 枚举 = lower_snake_case（{@code Store.rawValue} / {@code PeriodType.rawValue} / {@code OwnershipType.rawValue}
 * 各自转小写，未知值原样小写）。不 import 任何 {@code io.flutter.*}（设计 §2 边界）。
 *
 * 契约非空而原生为 null → 抛 {@link WireContractException}（插件转码 12）；
 * 唯一的回退是 {@code EntitlementInfo.originalPurchaseDate}（裁定 3），回退时经 {@link DiagnosticsSink} 记诊断。
 *
 * 对照 RC：hybrid-common {@code CustomerInfoMapper.kt} 同样由原生模型逐键拼 map；
 * 偏离（D2）：时间发毫秒而非 ISO 串 + 毫秒双份，枚举发小写串，派生集合由本类按主代理钉死的规则从 subscriptions 推导。
 */
public final class Mappers {

    /** 诊断码：EntitlementInfo.originalPurchaseDate 回退为 latestPurchaseDate（设计 §5.2）。 */
    public static final String WARNING_FIELD_FALLBACK = "hybrid_field_fallback";
    /** 回退诊断的 detail（fixture README 钉死）。 */
    public static final String DETAIL_ENTITLEMENT_ORIGINAL_PURCHASE_DATE = "entitlement.originalPurchaseDate";

    /** 诊断码：剔除无商店商品的 package（裁定 5），detail = {@code <offeringId>/<packageId>}。 */
    public static final String WARNING_PACKAGE_DROPPED = "hybrid_package_dropped";
    /** 诊断码：剔空的 offering 从 all 去掉 / current 因此为空（裁定 5），detail = {@code <offeringId>}。 */
    public static final String WARNING_OFFERING_DROPPED = "hybrid_offering_dropped";
    /** 全部 package 查不到商品时码 2 的 underlyingErrorMessage（fixture {@code errors/store-problem-2.json}）。 */
    public static final String STORE_PRODUCTS_UNAVAILABLE = "store products unavailable";
    /** B5：非 pending 成功却无交易信息（码 0）的 underlyingErrorMessage。 */
    public static final String MISSING_STORE_TRANSACTION = "purchase completed without a store transaction";

    /** IntroEligibility unknown 档的固定英文（RC Android hybrid 原文，fixture README「IntroEligibility」）。 */
    static final String ELIGIBILITY_UNKNOWN_DESCRIPTION = "Status indeterminate.";

    /** 我方无 Trusted Entitlements，如实报 {@code not_requested}（设计 §5.2 文档化常量）。 */
    static final String VERIFICATION_NOT_REQUESTED = "not_requested";

    private Mappers() {
    }

    // -------------------------------------------------------------------------------------------
    // CustomerInfo（§5.1）
    // -------------------------------------------------------------------------------------------

    /**
     * {@link CustomerInfo} → wire map。
     *
     * Android 派生规则（主代理钉死，fixture README「Android 侧派生规则」）：
     * <ul>
     *   <li>{@code activeSubscriptions} = subscriptions 中 {@code isActive} 的键，排序（不取原生 activeSubscriptions：
     *       0.2.0 那是活跃权益的商品 id，会含一次性商品）；</li>
     *   <li>{@code allPurchasedProductIdentifiers} = subscriptions 键 ∪ nonSubscriptions 键，排序；</li>
     *   <li>{@code allExpirationDates} = subscriptions 的 productId → expiresDate（不取原生 allExpirationDatesByProduct：
     *       0.2.0 对带 base plan 的订阅把键改写成 {@code productId:basePlanId}）；</li>
     *   <li>{@code allPurchaseDates} = subscriptions 的 purchaseDate + nonSubscriptions 每个商品最新一笔的 purchaseDate，
     *       键集 == allPurchasedProductIdentifiers；</li>
     *   <li>{@code latestExpirationDate} = subscriptions 非空 expiresDate 的最大值；</li>
     *   <li>{@code nonSubscriptionTransactions} 展平，按 purchaseDate 升序（null 最前）再按 transactionIdentifier；</li>
     *   <li>{@code originalApplicationVersion} = 文档化常量 null（同 RC Android）。</li>
     * </ul>
     *
     * @throws WireContractException 契约非空字段原生为 null（firstSeen / requestDate / 订阅 purchaseDate /
     *     非订阅交易 purchaseDate 或 id / 权益 latestPurchaseDate 等）。
     */
    public static Map<String, Object> customerInfo(CustomerInfo info, DiagnosticsSink diagnostics) {
        Map<String, SubscriptionInfo> subscriptions = info.getSubscriptions();
        Map<String, List<NonSubscriptionTransaction>> nonSubscriptions = info.getNonSubscriptions();

        Map<String, Object> map = new HashMap<>();
        map.put("entitlements", entitlementInfos(info, diagnostics));

        List<String> activeSubscriptions = new ArrayList<>();
        for (Map.Entry<String, SubscriptionInfo> entry : subscriptions.entrySet()) {
            if (entry.getValue().isActive()) {
                activeSubscriptions.add(entry.getKey());
            }
        }
        Collections.sort(activeSubscriptions);
        map.put("activeSubscriptions", activeSubscriptions);

        TreeSet<String> purchased = new TreeSet<>(subscriptions.keySet());
        purchased.addAll(nonSubscriptions.keySet());
        map.put("allPurchasedProductIdentifiers", new ArrayList<>(purchased));

        Long latestExpiration = null;
        Map<String, Object> allExpirationDates = new HashMap<>();
        Map<String, Object> allPurchaseDates = new HashMap<>();
        Map<String, Object> subscriptionsByProductIdentifier = new HashMap<>();
        for (Map.Entry<String, SubscriptionInfo> entry : subscriptions.entrySet()) {
            String productId = entry.getKey();
            SubscriptionInfo subscription = entry.getValue();
            Long expires = millis(subscription.getExpiresDate());
            allExpirationDates.put(productId, expires);
            if (expires != null && (latestExpiration == null || expires > latestExpiration)) {
                latestExpiration = expires;
            }
            allPurchaseDates.put(productId, requireMillis(
                    subscription.getPurchaseDate(),
                    "subscriptionsByProductIdentifier." + productId + ".purchaseDate"));
            subscriptionsByProductIdentifier.put(productId, subscriptionInfo(subscription));
        }

        List<NonSubscriptionTransaction> flattened = new ArrayList<>();
        for (Map.Entry<String, List<NonSubscriptionTransaction>> entry : nonSubscriptions.entrySet()) {
            Long latest = null;
            for (NonSubscriptionTransaction transaction : entry.getValue()) {
                Long purchaseDate = requireMillis(
                        transaction.getPurchaseDate(),
                        "nonSubscriptionTransactions[" + transaction.getTransactionIdentifier() + "].purchaseDate");
                if (latest == null || purchaseDate > latest) {
                    latest = purchaseDate;
                }
                flattened.add(transaction);
            }
            // 同一商品既是订阅又是一次性商品不会发生；万一发生，订阅的 purchaseDate 优先（与 allPurchasedProductIdentifiers 同键集）。
            if (latest != null && !allPurchaseDates.containsKey(entry.getKey())) {
                allPurchaseDates.put(entry.getKey(), latest);
            }
        }
        Collections.sort(flattened, NON_SUBSCRIPTION_ORDER);
        List<Object> nonSubscriptionTransactions = new ArrayList<>();
        for (NonSubscriptionTransaction transaction : flattened) {
            nonSubscriptionTransactions.add(nonSubscriptionTransaction(transaction));
        }

        map.put("latestExpirationDate", latestExpiration);
        map.put("firstSeen", requireMillis(info.getFirstSeen(), "firstSeen"));
        map.put("originalAppUserId", requireNonNull(info.getOriginalAppUserId(), "originalAppUserId"));
        map.put("requestDate", requireMillis(info.getRequestDate(), "requestDate"));
        map.put("allExpirationDates", allExpirationDates);
        map.put("allPurchaseDates", allPurchaseDates);
        // 文档化常量（设计 §5.1）：Android 原生不解析 original_application_version，同 RC Android 恒 null。
        map.put("originalApplicationVersion", null);
        map.put("originalPurchaseDate", millis(info.getOriginalPurchaseDate()));
        map.put("managementURL", info.getManagementURL() == null ? null : info.getManagementURL().toString());
        map.put("nonSubscriptionTransactions", nonSubscriptionTransactions);
        map.put("subscriptionsByProductIdentifier", subscriptionsByProductIdentifier);
        return map;
    }

    /** LogInResult（§5.5）：{@code {created, customerInfo}}。 */
    public static Map<String, Object> logInResult(CustomerInfo info, boolean created, DiagnosticsSink diagnostics) {
        Map<String, Object> map = new HashMap<>();
        map.put("created", created);
        map.put("customerInfo", customerInfo(info, diagnostics));
        return map;
    }

    // -------------------------------------------------------------------------------------------
    // EntitlementInfos / EntitlementInfo（§5.2）
    // -------------------------------------------------------------------------------------------

    private static Map<String, Object> entitlementInfos(CustomerInfo info, DiagnosticsSink diagnostics) {
        Map<String, Object> all = new HashMap<>();
        Map<String, Object> active = new HashMap<>();
        for (Map.Entry<String, EntitlementInfo> entry : info.getEntitlements().getAll().entrySet()) {
            EntitlementInfo entitlement = entry.getValue();
            // 每个权益只 map 一次：回退诊断只记一次，active 与 all 共用同一个 map。
            Map<String, Object> mapped = entitlementInfo(entitlement, info, diagnostics);
            all.put(entry.getKey(), mapped);
            // active = all 中 isActive 的子集（不另读原生 active，保证不变式 1）。
            if (entitlement.isActive()) {
                active.put(entry.getKey(), mapped);
            }
        }
        Map<String, Object> map = new HashMap<>();
        map.put("all", all);
        map.put("active", active);
        map.put("verification", VERIFICATION_NOT_REQUESTED);
        return map;
    }

    private static Map<String, Object> entitlementInfo(
            EntitlementInfo entitlement, CustomerInfo info, DiagnosticsSink diagnostics) {
        String identifier = entitlement.getIdentifier();
        Long latestPurchaseDate = requireMillis(
                entitlement.getLatestPurchaseDate(), "entitlements.all." + identifier + ".latestPurchaseDate");
        Long originalPurchaseDate = millis(entitlement.getOriginalPurchaseDate());
        if (originalPurchaseDate == null) {
            // 裁定 3：回退 latestPurchaseDate + 记诊断（两者皆空已在上面抛码 12）。
            // 对照 RC：RC Dart 的 originalPurchaseDate 为必需 String，RC 原生恒有值；我方后端可空，故回退。
            originalPurchaseDate = latestPurchaseDate;
            diagnostics.recordWarning(WARNING_FIELD_FALLBACK, DETAIL_ENTITLEMENT_ORIGINAL_PURCHASE_DATE);
        }

        String productIdentifier = entitlement.getProductIdentifier();
        String ownershipType = lower(entitlement.getOwnershipType().getRawValue());
        // 主代理裁定：非订阅商品授予的权益，Android 0.2.0 原生给 UNKNOWN（后端 non_subscriptions 不带该字段）
        // → 映射为 purchased，与 iOS 0.4.0 口径一致。订阅权益的 UNKNOWN 照原样报 unknown。
        if (OwnershipType.UNKNOWN.equals(entitlement.getOwnershipType())
                && !info.getSubscriptions().containsKey(productIdentifier)
                && info.getNonSubscriptions().containsKey(productIdentifier)) {
            ownershipType = "purchased";
        }

        Map<String, Object> map = new HashMap<>();
        map.put("identifier", identifier);
        map.put("isActive", entitlement.isActive());
        map.put("willRenew", entitlement.getWillRenew());
        map.put("periodType", lower(entitlement.getPeriodType().getRawValue()));
        map.put("latestPurchaseDate", latestPurchaseDate);
        map.put("originalPurchaseDate", originalPurchaseDate);
        map.put("expirationDate", millis(entitlement.getExpirationDate()));
        map.put("store", lower(entitlement.getStore().getRawValue()));
        map.put("productIdentifier", productIdentifier);
        map.put("productPlanIdentifier", entitlement.getProductPlanIdentifier());
        map.put("isSandbox", entitlement.isSandbox());
        map.put("unsubscribeDetectedAt", millis(entitlement.getUnsubscribeDetectedAt()));
        map.put("billingIssueDetectedAt", millis(entitlement.getBillingIssueDetectedAt()));
        map.put("ownershipType", ownershipType);
        map.put("verification", VERIFICATION_NOT_REQUESTED);
        return map;
    }

    // -------------------------------------------------------------------------------------------
    // SubscriptionInfo（§5.1b，RC 19 字段全量）
    // -------------------------------------------------------------------------------------------

    private static Map<String, Object> subscriptionInfo(SubscriptionInfo subscription) {
        String productId = subscription.getProductIdentifier();
        Map<String, Object> map = new HashMap<>();
        map.put("productIdentifier", productId);
        map.put("purchaseDate", requireMillis(
                subscription.getPurchaseDate(), "subscriptionsByProductIdentifier." + productId + ".purchaseDate"));
        map.put("originalPurchaseDate", millis(subscription.getOriginalPurchaseDate()));
        map.put("expiresDate", millis(subscription.getExpiresDate()));
        map.put("store", lower(subscription.getStore().getRawValue()));
        map.put("unsubscribeDetectedAt", millis(subscription.getUnsubscribeDetectedAt()));
        map.put("isSandbox", subscription.isSandbox());
        map.put("billingIssuesDetectedAt", millis(subscription.getBillingIssuesDetectedAt()));
        map.put("gracePeriodExpiresDate", millis(subscription.getGracePeriodExpiresDate()));
        map.put("ownershipType", lower(subscription.getOwnershipType().getRawValue()));
        map.put("periodType", lower(subscription.getPeriodType().getRawValue()));
        map.put("refundedAt", millis(subscription.getRefundedAt()));
        map.put("storeTransactionId", subscription.getStoreTransactionId());
        map.put("isActive", subscription.isActive());
        map.put("willRenew", subscription.getWillRenew());
        map.put("autoResumeDate", millis(subscription.getAutoResumeDate()));
        map.put("displayName", subscription.getDisplayName());
        map.put("managementURL",
                subscription.getManagementURL() == null ? null : subscription.getManagementURL().toString());
        map.put("productPlanIdentifier", subscription.getProductPlanIdentifier());
        return map;
    }

    // -------------------------------------------------------------------------------------------
    // 非订阅交易（§5.5 StoreTransaction 同形）
    // -------------------------------------------------------------------------------------------

    private static Map<String, Object> nonSubscriptionTransaction(NonSubscriptionTransaction transaction) {
        Map<String, Object> map = new HashMap<>();
        map.put("transactionIdentifier",
                requireNonNull(transaction.getTransactionIdentifier(), "nonSubscriptionTransactions.transactionIdentifier"));
        map.put("productIdentifier",
                requireNonNull(transaction.getProductIdentifier(), "nonSubscriptionTransactions.productIdentifier"));
        map.put("purchaseDate", requireMillis(transaction.getPurchaseDate(),
                "nonSubscriptionTransactions[" + transaction.getTransactionIdentifier() + "].purchaseDate"));
        return map;
    }

    /** purchaseDate 升序（null 最前），同时间按 transactionIdentifier 升序（fixture README「列表顺序」）。 */
    private static final Comparator<NonSubscriptionTransaction> NON_SUBSCRIPTION_ORDER = (a, b) -> {
        Date da = a.getPurchaseDate();
        Date db = b.getPurchaseDate();
        if (da == null && db != null) {
            return -1;
        }
        if (da != null && db == null) {
            return 1;
        }
        if (da != null) {
            int byDate = Long.compare(da.getTime(), db.getTime());
            if (byDate != 0) {
                return byDate;
            }
        }
        return String.valueOf(a.getTransactionIdentifier()).compareTo(String.valueOf(b.getTransactionIdentifier()));
    };

    // -------------------------------------------------------------------------------------------
    // Offerings / Offering / Package（§5.3，裁定 5）
    // -------------------------------------------------------------------------------------------

    /**
     * {@link Offerings} → wire map {@code {all, current}}（可执行版 = {@code wire/offerings-android.json}）。
     *
     * 剔除规则（裁定 5；fixture README「剔除规则」）：
     * <ol>
     *   <li>{@code product == null} 的 package 剔除，记 {@code hybrid_package_dropped}（{@code <offeringId>/<packageId>}）；</li>
     *   <li>剔后为空的 offering 从 {@code all} 去掉，记 {@code hybrid_offering_dropped}（{@code <offeringId>}）；</li>
     *   <li>原生 {@code all} 非空而剔后为空 → 抛 {@link BridgeErrorException}（码 2，{@code store products unavailable}，
     *       非购买路径无 {@code userCancelled}）；</li>
     *   <li>{@code current} = 剔后 {@code all} 里 {@code currentOfferingIdentifier} 对应项；后台指了 current 却不在剔后 all 里
     *       → {@code null} + 记 {@code hybrid_offering_dropped}（上一步已记过同一 offering 则不重记）；warn 日志由插件打
     *       （Bridge 不碰 android.util.Log）。{@code current} 键恒在。</li>
     * </ol>
     * 对照 RC：RC {@code OfferingParser.createPackage} 查不到商品即不建 package、空 offering 不进 all，Dart 看到的形态与 RC 相同；
     * 偏离：我方原生保留 package（{@code product} 可空），剔除放在 Bridge 并记诊断；全部查不到抛码 2（RC 行为未核实，裁定 5）。
     *
     * @throws BridgeErrorException 商品全缺（码 2）。
     */
    public static Map<String, Object> offerings(Offerings offerings, DiagnosticsSink diagnostics) {
        Map<String, Offering> nativeAll = offerings.getAll();
        Map<String, Object> all = new LinkedHashMap<>();
        List<String> droppedOfferings = new ArrayList<>();
        for (Map.Entry<String, Offering> entry : nativeAll.entrySet()) {
            Offering offering = entry.getValue();
            String offeringId = offering.getIdentifier();
            List<Object> packages = new ArrayList<>();
            for (Package pkg : offering.getAvailablePackages()) {
                StoreProduct product = pkg.getProduct();
                if (product == null) {
                    diagnostics.recordWarning(WARNING_PACKAGE_DROPPED, offeringId + "/" + pkg.getIdentifier());
                    continue;
                }
                packages.add(packageMap(pkg, product, offeringId));
            }
            if (packages.isEmpty()) {
                diagnostics.recordWarning(WARNING_OFFERING_DROPPED, offeringId);
                droppedOfferings.add(offeringId);
                continue;
            }
            Map<String, Object> map = new HashMap<>();
            map.put("identifier", offeringId);
            map.put("serverDescription", offering.getServerDescription());
            map.put("availablePackages", packages);
            all.put(entry.getKey(), map);
        }
        if (!nativeAll.isEmpty() && all.isEmpty()) {
            throw new BridgeErrorException(
                    ErrorMapper.synthetic(PurchasesErrorCode.StoreProblemError, STORE_PRODUCTS_UNAVAILABLE), false);
        }

        String currentId = offerings.getCurrentOfferingIdentifier();
        Object current = currentId == null ? null : all.get(currentId);
        if (currentId != null && current == null && !droppedOfferings.contains(currentId)) {
            diagnostics.recordWarning(WARNING_OFFERING_DROPPED, currentId);
        }

        Map<String, Object> map = new HashMap<>();
        map.put("all", all);
        map.put("current", current);
        return map;
    }

    private static Map<String, Object> packageMap(Package pkg, StoreProduct product, String offeringId) {
        Map<String, Object> map = new HashMap<>();
        map.put("identifier", pkg.getIdentifier());
        map.put("packageType", packageType(pkg.getPackageType()));
        // offeringIdentifier == presentedOfferingContext.offeringIdentifier（fixture README），均取所属 offering。
        map.put("offeringIdentifier", offeringId);
        map.put("storeProduct", storeProduct(product, offeringId));
        map.put("presentedOfferingContext", presentedOfferingContext(offeringId));
        return map;
    }

    /**
     * PackageType → lower_snake 显式表（设计 §5 总则「插件 mapper 显式建表」）。原生对非标准 id 已给 CUSTOM；
     * 表外（含 UNKNOWN）→ {@code unknown}。
     */
    static String packageType(PackageType type) {
        if (PackageType.LIFETIME.equals(type)) {
            return "lifetime";
        } else if (PackageType.ANNUAL.equals(type)) {
            return "annual";
        } else if (PackageType.SIX_MONTH.equals(type)) {
            return "six_month";
        } else if (PackageType.THREE_MONTH.equals(type)) {
            return "three_month";
        } else if (PackageType.TWO_MONTH.equals(type)) {
            return "two_month";
        } else if (PackageType.MONTHLY.equals(type)) {
            return "monthly";
        } else if (PackageType.WEEKLY.equals(type)) {
            return "weekly";
        } else if (PackageType.CUSTOM.equals(type)) {
            return "custom";
        }
        return "unknown";
    }

    /** 恒为 {@code {offeringIdentifier, placementIdentifier: null, targetingContext: null}}（我方无 placement / targeting）。 */
    private static Map<String, Object> presentedOfferingContext(String offeringId) {
        Map<String, Object> map = new HashMap<>();
        map.put("offeringIdentifier", offeringId);
        map.put("placementIdentifier", null);
        map.put("targetingContext", null);
        return map;
    }

    // -------------------------------------------------------------------------------------------
    // StoreProduct / IntroductoryPrice（§5.4）+ SubscriptionOption / PricingPhase / Price / Period（§5.4b）
    // -------------------------------------------------------------------------------------------

    /**
     * {@link StoreProduct} → wire map。不发的键（Dart 填文档化常量）：{@code discounts} / {@code pricePerX(String)}，
     * Option 的 {@code installmentsInfo}；金额只发 int micros。
     *
     * 对照 RC：hybrid-common {@code StoreProductMapper.kt} 逐键拼 map；偏离：
     * ① {@code introductoryPrice.priceString} 取 Play 原串（RC 用设备 locale 格式化零价）；
     * ② {@code periodUnit / periodNumberOfUnits} 取 Play 原始单位（RC 把 WEEK 改写成 DAY×7）；
     * ③ 枚举发 lower_snake 串（RC 发 Google 整数 / 大写名）；④ 不发 double {@code price}（Dart 由 micros 派生）。
     *
     * @param offeringIdentifier 所属 offering（填 {@code presentedOfferingContext}）。
     */
    public static Map<String, Object> storeProduct(StoreProduct product, String offeringIdentifier) {
        Price price = product.getPrice();
        Period period = product.getPeriod();
        SubscriptionOption defaultOption = product.getDefaultOption();
        List<SubscriptionOption> options = product.getSubscriptionOptions();

        Map<String, Object> map = new HashMap<>();
        map.put("identifier", product.getId());
        // 取 Play 的 title（带应用名），不是 name（fixture README「两端差异点」）。
        map.put("title", product.getTitle());
        map.put("description", product.getDescription());
        map.put("priceAmountMicros", price.getAmountMicros());
        map.put("priceString", price.getFormatted());
        map.put("currencyCode", price.getCurrencyCode());
        map.put("subscriptionPeriod", period == null ? null : period.getIso8601());
        map.put("productCategory", productCategory(product.getType()));
        map.put("introductoryPrice", introductoryPrice(defaultOption));
        map.put("defaultOption", defaultOption == null ? null : subscriptionOption(defaultOption, offeringIdentifier));
        if (options == null) {
            map.put("subscriptionOptions", null);
        } else {
            List<Object> mapped = new ArrayList<>();
            for (SubscriptionOption option : options) {
                mapped.add(subscriptionOption(option, offeringIdentifier));
            }
            map.put("subscriptionOptions", mapped);
        }
        map.put("presentedOfferingContext", presentedOfferingContext(offeringIdentifier));
        return map;
    }

    /** SUBS → subscription、INAPP → non_subscription；其它（UNKNOWN）→ {@code unknown}（Dart 容忍为 null，照 RC）。 */
    private static String productCategory(ProductType type) {
        if (ProductType.SUBS.equals(type)) {
            return "subscription";
        }
        if (ProductType.INAPP.equals(type)) {
            return "non_subscription";
        }
        return "unknown";
    }

    /** {@code defaultOption.freePhase ?? defaultOption.introPhase}；都没有 → null（照 RC）。 */
    private static Map<String, Object> introductoryPrice(SubscriptionOption defaultOption) {
        if (defaultOption == null) {
            return null;
        }
        PricingPhase phase = defaultOption.getFreePhase() != null ? defaultOption.getFreePhase() : defaultOption.getIntroPhase();
        if (phase == null) {
            return null;
        }
        Period period = phase.getBillingPeriod();
        Integer cycles = phase.getBillingCycleCount();
        Map<String, Object> map = new HashMap<>();
        map.put("priceAmountMicros", phase.getPrice().getAmountMicros());
        map.put("priceString", phase.getPrice().getFormatted());
        map.put("period", period.getIso8601());
        map.put("periodUnit", lower(period.getUnit().getRawValue()));
        map.put("periodNumberOfUnits", period.getValue());
        // 照 RC：billingCycleCount 缺省按 1 个周期。
        map.put("cycles", cycles == null ? 1 : cycles);
        return map;
    }

    private static Map<String, Object> subscriptionOption(SubscriptionOption option, String offeringIdentifier) {
        List<Object> phases = new ArrayList<>();
        for (PricingPhase phase : option.getPricingPhases()) {
            phases.add(pricingPhase(phase));
        }
        Map<String, Object> map = new HashMap<>();
        map.put("id", option.getId());
        map.put("storeProductId", option.getProductId() + StoreProduct.ID_SEPARATOR + option.getBasePlanId());
        map.put("productId", option.getProductId());
        map.put("pricingPhases", phases);
        map.put("tags", new ArrayList<>(option.getTags()));
        map.put("isBasePlan", option.isBasePlan());
        map.put("billingPeriod", periodMap(option.getBillingPeriod()));
        map.put("isPrepaid", option.isPrepaid());
        map.put("fullPricePhase", pricingPhaseOrNull(option.getFullPricePhase()));
        map.put("freePhase", pricingPhaseOrNull(option.getFreePhase()));
        map.put("introPhase", pricingPhaseOrNull(option.getIntroPhase()));
        map.put("presentedOfferingContext", presentedOfferingContext(offeringIdentifier));
        return map;
    }

    private static Map<String, Object> pricingPhaseOrNull(PricingPhase phase) {
        return phase == null ? null : pricingPhase(phase);
    }

    private static Map<String, Object> pricingPhase(PricingPhase phase) {
        Price price = phase.getPrice();
        Map<String, Object> priceMap = new HashMap<>();
        priceMap.put("formatted", price.getFormatted());
        priceMap.put("amountMicros", price.getAmountMicros());
        priceMap.put("currencyCode", price.getCurrencyCode());

        OfferPaymentMode paymentMode = phase.getOfferPaymentMode();
        Map<String, Object> map = new HashMap<>();
        map.put("billingPeriod", periodMap(phase.getBillingPeriod()));
        // 原生常量名 INFINITE_RECURRING 等 → 小写即 lower_snake；UNKNOWN → unknown。偏离 RC：RC 通道发 Google 整数。
        map.put("recurrenceMode", lower(phase.getRecurrenceMode().getName()));
        map.put("billingCycleCount", phase.getBillingCycleCount());
        map.put("price", priceMap);
        map.put("offerPaymentMode", paymentMode == null ? null : lower(paymentMode.getName()));
        return map;
    }

    /** Period → {@code {unit, value, iso8601}}（原始单位，不改写）。 */
    private static Map<String, Object> periodMap(Period period) {
        if (period == null) {
            return null;
        }
        Map<String, Object> map = new HashMap<>();
        map.put("unit", lower(period.getUnit().getRawValue()));
        map.put("value", period.getValue());
        map.put("iso8601", period.getIso8601());
        return map;
    }

    // -------------------------------------------------------------------------------------------
    // PurchaseResult（§5.5，D3 / B5 / 裁定 3）
    // -------------------------------------------------------------------------------------------

    /**
     * 购买成功回调 → {@code {customerInfo, storeTransaction{transactionIdentifier, productIdentifier, purchaseDate}}}。
     * 入参拆开传（原生 {@code PurchaseResult} 无公开构造器，Bridge 测试无法造）。
     *
     * 归一（全部为购买路径信封，带 {@code userCancelled: false}）：
     * <ul>
     *   <li>{@code isPending} → 码 20（D3；对照 RC：RC Android 同样以 PaymentPendingError 报待定）；</li>
     *   <li>非 pending 却无 {@code storeTransaction} → 码 0（B5，原生契约违规，severe）；</li>
     *   <li>{@code orderId} 为 null / 空串 → 码 12（裁定 3，不吞成 {@code ''}，偏离 RC Dart；severe）；
     *       {@code productIds} 为空同属交易契约违约 → 码 12；</li>
     *   <li>CustomerInfo 契约违约（{@link WireContractException}）→ 码 12 + {@code userCancelled: false}（severe）。</li>
     * </ul>
     *
     * @throws BridgeErrorException 以上任一情形。
     */
    public static Map<String, Object> purchaseResult(
            CustomerInfo info, StoreTransaction transaction, boolean isPending, DiagnosticsSink diagnostics) {
        if (isPending) {
            throw new BridgeErrorException(ErrorMapper.syntheticPurchase(PurchasesErrorCode.PaymentPendingError, null), false);
        }
        if (transaction == null) {
            throw new BridgeErrorException(
                    ErrorMapper.syntheticPurchase(PurchasesErrorCode.UnknownError, MISSING_STORE_TRANSACTION), true);
        }
        String orderId = transaction.getOrderId();
        if (orderId == null || orderId.isEmpty()) {
            throw purchaseContractViolation("missing storeTransaction.transactionIdentifier (orderId) in purchase result");
        }
        List<String> productIds = transaction.getProductIds();
        if (productIds.isEmpty() || productIds.get(0) == null) {
            throw purchaseContractViolation("missing storeTransaction.productIdentifier in purchase result");
        }

        Map<String, Object> customerInfo;
        try {
            customerInfo = customerInfo(info, diagnostics);
        } catch (WireContractException e) {
            throw purchaseContractViolation(e.getMessage());
        }

        Map<String, Object> storeTransaction = new HashMap<>();
        storeTransaction.put("transactionIdentifier", orderId);
        storeTransaction.put("productIdentifier", productIds.get(0));
        storeTransaction.put("purchaseDate", transaction.getPurchaseTime());

        Map<String, Object> map = new HashMap<>();
        map.put("customerInfo", customerInfo);
        map.put("storeTransaction", storeTransaction);
        return map;
    }

    private static BridgeErrorException purchaseContractViolation(String underlying) {
        return new BridgeErrorException(
                ErrorMapper.syntheticPurchase(PurchasesErrorCode.UnexpectedBackendResponseError, underlying), true);
    }

    // -------------------------------------------------------------------------------------------
    // IntroEligibility（§5.5）
    // -------------------------------------------------------------------------------------------

    /**
     * Android 恒 {@code unknown}（对照 RC：purchases-hybrid-common Android 同样对每个 id 回 UNKNOWN，
     * ADR 0100）。每个请求的 id 都有条目；不调原生。
     */
    public static Map<String, Object> introEligibility(List<String> productIdentifiers) {
        Map<String, Object> map = new HashMap<>();
        for (String productId : productIdentifiers) {
            Map<String, Object> entry = new HashMap<>();
            entry.put("status", "unknown");
            entry.put("description", ELIGIBILITY_UNKNOWN_DESCRIPTION);
            map.put(productId, entry);
        }
        return map;
    }

    // -------------------------------------------------------------------------------------------
    // 工具
    // -------------------------------------------------------------------------------------------

    private static Long millis(Date date) {
        return date == null ? null : date.getTime();
    }

    private static Long requireMillis(Date date, String wireKey) {
        if (date == null) {
            throw new WireContractException("missing " + wireKey + " in customer info");
        }
        return date.getTime();
    }

    private static <T> T requireNonNull(T value, String wireKey) {
        if (value == null) {
            throw new WireContractException("missing " + wireKey + " in customer info");
        }
        return value;
    }

    /**
     * 枚举 → lower_snake_case。原生 rawValue 已是 snake（Store / PeriodType 小写、OwnershipType 大写），
     * 统一转小写；未知值原样小写（Dart 侧落 RC 的 unknown 档）。rawValue 在 Kotlin 侧非空。
     */
    private static String lower(String rawValue) {
        return rawValue.toLowerCase(Locale.ROOT);
    }
}
