package org.revdog.flutter.bridge;

import org.revdog.purchases.OwnershipType;
import org.revdog.purchases.customerinfo.CustomerInfo;
import org.revdog.purchases.customerinfo.EntitlementInfo;
import org.revdog.purchases.customerinfo.NonSubscriptionTransaction;
import org.revdog.purchases.customerinfo.SubscriptionInfo;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Date;
import java.util.HashMap;
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
