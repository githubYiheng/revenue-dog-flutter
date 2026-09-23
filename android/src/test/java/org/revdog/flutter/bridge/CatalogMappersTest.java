package org.revdog.flutter.bridge;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.revdog.purchases.ProductType;
import org.revdog.purchases.RevenueDogTestModels;
import org.revdog.purchases.customerinfo.CustomerInfo;
import org.revdog.purchases.models.PricingPhase;
import org.revdog.purchases.models.PurchaseState;
import org.revdog.purchases.models.RecurrenceMode;
import org.revdog.purchases.models.StoreProduct;
import org.revdog.purchases.models.StoreTransaction;
import org.revdog.purchases.models.SubscriptionOption;
import org.revdog.purchases.offerings.Offerings;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * M2 三方对账（设计 §7）：backend fixture + 商店侧商品清单 → M0 测试工厂 → {@link Mappers} → 与 wire fixture 深度相等。
 * 商品清单 {@code store-products-android.json} 的键 = {@code RevenueDogTestModels} 参数名（fixture README）。
 */
public class CatalogMappersTest {

    private static final class RecordingSink implements DiagnosticsSink {
        final List<String> records = new ArrayList<>();

        @Override
        public void recordWarning(String code, String detail) {
            records.add(code + "|" + detail);
        }
    }

    private static final List<String> RETENTION_DROPPED = Arrays.asList(
            Mappers.WARNING_PACKAGE_DROPPED + "|retention_offer/$rc_monthly",
            Mappers.WARNING_OFFERING_DROPPED + "|retention_offer");

    // -------------------------------------------------------------------------------------------
    // 商店侧商品清单 → 原生模型
    // -------------------------------------------------------------------------------------------

    private static List<StoreProduct> storeProducts() {
        try {
            JSONArray products = new JSONObject(Fixtures.read("backend/store-products-android.json")).getJSONArray("products");
            List<StoreProduct> result = new ArrayList<>();
            for (int i = 0; i < products.length(); i++) {
                result.add(storeProduct(products.getJSONObject(i)));
            }
            return result;
        } catch (Exception e) {
            throw new AssertionError("invalid store-products-android.json", e);
        }
    }

    private static StoreProduct storeProduct(JSONObject p) throws Exception {
        List<SubscriptionOption> options = null;
        if (!p.isNull("subscriptionOptions")) {
            options = new ArrayList<>();
            JSONArray array = p.getJSONArray("subscriptionOptions");
            for (int i = 0; i < array.length(); i++) {
                options.add(subscriptionOption(array.getJSONObject(i)));
            }
        }
        return RevenueDogTestModels.storeProduct(
                p.getString("productId"),
                optString(p, "basePlanId"),
                (ProductType) ProductType.class.getField(p.getString("type")).get(null),
                p.getLong("priceAmountMicros"),
                p.getString("priceCurrencyCode"),
                p.getString("formattedPrice"),
                p.getString("name"),
                p.getString("title"),
                p.getString("description"),
                optString(p, "period"),
                options);
    }

    private static SubscriptionOption subscriptionOption(JSONObject o) throws Exception {
        List<PricingPhase> phases = new ArrayList<>();
        JSONArray array = o.getJSONArray("pricingPhases");
        for (int i = 0; i < array.length(); i++) {
            JSONObject ph = array.getJSONObject(i);
            phases.add(RevenueDogTestModels.pricingPhase(
                    ph.getString("billingPeriod"),
                    (RecurrenceMode) RecurrenceMode.class.getField(ph.getString("recurrenceMode")).get(null),
                    ph.isNull("billingCycleCount") ? null : ph.getInt("billingCycleCount"),
                    ph.getLong("priceAmountMicros"),
                    ph.getString("priceCurrencyCode"),
                    ph.getString("formattedPrice")));
        }
        List<String> tags = new ArrayList<>();
        JSONArray tagArray = o.getJSONArray("tags");
        for (int i = 0; i < tagArray.length(); i++) {
            tags.add(tagArray.getString(i));
        }
        return RevenueDogTestModels.subscriptionOption(
                o.getString("productId"), o.getString("basePlanId"), optString(o, "offerId"),
                phases, tags, o.getString("offerToken"));
    }

    private static String optString(JSONObject object, String key) throws Exception {
        return object.isNull(key) ? null : object.getString(key);
    }

    private static Offerings offerings(String backend, List<StoreProduct> products) {
        return RevenueDogTestModels.offeringsFromJson(Fixtures.read("backend/" + backend), products);
    }

    // -------------------------------------------------------------------------------------------
    // Offerings（§5.3 / 5.4 / 5.4b，裁定 5）
    // -------------------------------------------------------------------------------------------

    @Test
    public void offeringsMatchFixtureAndDropRetentionOffer() {
        RecordingSink sink = new RecordingSink();
        Map<String, Object> actual = Mappers.offerings(offerings("offerings.json", storeProducts()), sink);
        Fixtures.assertDeepEquals(Fixtures.parse(Fixtures.read("wire/offerings-android.json")), actual);
        assertEquals(RETENTION_DROPPED, sink.records);
    }

    @Test
    public void currentDroppedBecomesNull() {
        RecordingSink sink = new RecordingSink();
        Map<String, Object> actual = Mappers.offerings(offerings("offerings-current-dropped.json", storeProducts()), sink);
        Fixtures.assertDeepEquals(Fixtures.parse(Fixtures.read("wire/offerings-current-dropped-android.json")), actual);
        assertTrue(actual.containsKey("current"));
        assertNull(actual.get("current"));
        // current 指向的 offering 已记过 hybrid_offering_dropped，不重记。
        assertEquals(RETENTION_DROPPED, sink.records);
    }

    @Test
    public void allProductsMissingIsStoreProblem2() {
        RecordingSink sink = new RecordingSink();
        try {
            Mappers.offerings(offerings("offerings.json", Collections.<StoreProduct>emptyList()), sink);
            fail("expected BridgeErrorException");
        } catch (BridgeErrorException e) {
            Map<String, Object> envelope = new HashMap<>();
            envelope.put("code", e.envelope.code);
            envelope.put("message", e.envelope.message);
            envelope.put("details", e.envelope.details);
            Fixtures.assertDeepEquals(Fixtures.parse(Fixtures.read("wire/errors/store-problem-2.json")), envelope);
            assertFalse(e.severe);
        }
        // 每个被剔的 package / offering 仍各记一条诊断（default 4 个 + retention 1 个 package，2 个 offering）。
        assertEquals(7, sink.records.size());
    }

    /** 后台没有任何 offering → {all: {}, current: null}，不是码 2（原生 all 本就为空）。 */
    @Test
    public void emptyBackendOfferingsIsEmptyMap() {
        RecordingSink sink = new RecordingSink();
        Offerings empty = RevenueDogTestModels.offeringsFromJson(
                "{\"current_offering_id\":null,\"offerings\":[]}", Collections.<StoreProduct>emptyList());
        Map<String, Object> actual = Mappers.offerings(empty, sink);
        assertEquals(Collections.emptyMap(), actual.get("all"));
        assertTrue(actual.containsKey("current"));
        assertNull(actual.get("current"));
        assertEquals(Collections.emptyList(), sink.records);
    }

    // -------------------------------------------------------------------------------------------
    // PurchaseResult（§5.5，D3 / B5 / 裁定 3）
    // -------------------------------------------------------------------------------------------

    private static CustomerInfo minimalCustomerInfo() {
        return RevenueDogTestModels.customerInfoFromJson(Fixtures.read("backend/customer-info-minimal.json"));
    }

    private static StoreTransaction transaction(String orderId) {
        return RevenueDogTestModels.storeTransaction(
                orderId,
                Collections.singletonList("premium_monthly"),
                ProductType.SUBS,
                1790164800000L,
                "test-purchase-token",
                PurchaseState.PURCHASED,
                true,
                false,
                "default",
                "monthly-base",
                null);
    }

    private static Map<String, Object> envelopeMap(ErrorEnvelope envelope) {
        Map<String, Object> map = new HashMap<>();
        map.put("code", envelope.code);
        map.put("message", envelope.message);
        map.put("details", envelope.details);
        return map;
    }

    @Test
    public void purchaseResultMatchesFixture() {
        Map<String, Object> actual = Mappers.purchaseResult(
                minimalCustomerInfo(), transaction("2000000987654321"), false, DiagnosticsSink.NONE);
        Fixtures.assertDeepEquals(Fixtures.parse(Fixtures.read("wire/purchase-result.json")), actual);
        @SuppressWarnings("unchecked")
        Map<String, Object> tx = (Map<String, Object>) actual.get("storeTransaction");
        assertTrue(tx.get("purchaseDate") instanceof Long);
    }

    @Test
    public void pendingIsPaymentPending20() {
        try {
            Mappers.purchaseResult(minimalCustomerInfo(), transaction("2000000987654321"), true, DiagnosticsSink.NONE);
            fail("expected BridgeErrorException");
        } catch (BridgeErrorException e) {
            Fixtures.assertDeepEquals(
                    Fixtures.parse(Fixtures.read("wire/errors/payment-pending-20.json")), envelopeMap(e.envelope));
            assertFalse(e.severe);
        }
    }

    @Test
    public void emptyOrderIdIsCode12() {
        for (String orderId : Arrays.asList("", null)) {
            try {
                Mappers.purchaseResult(minimalCustomerInfo(), transaction(orderId), false, DiagnosticsSink.NONE);
                fail("expected BridgeErrorException for orderId=" + orderId);
            } catch (BridgeErrorException e) {
                assertEquals("12", e.envelope.code);
                assertEquals(Boolean.FALSE, e.envelope.details.get("userCancelled"));
                assertEquals("UnexpectedBackendResponseError", e.envelope.details.get("readableErrorCode"));
                assertTrue(e.severe);
            }
        }
    }

    @Test
    public void missingTransactionIsCode0() {
        try {
            Mappers.purchaseResult(minimalCustomerInfo(), null, false, DiagnosticsSink.NONE);
            fail("expected BridgeErrorException");
        } catch (BridgeErrorException e) {
            assertEquals("0", e.envelope.code);
            assertEquals("Unknown error.", e.envelope.message);
            assertEquals(Boolean.FALSE, e.envelope.details.get("userCancelled"));
            assertEquals(Mappers.MISSING_STORE_TRANSACTION, e.envelope.details.get("underlyingErrorMessage"));
            assertTrue(e.severe);
        }
    }

    /** CustomerInfo 契约违约在购买路径 → 码 12 且带 userCancelled:false（不走无 userCancelled 的通用 12）。 */
    @Test
    public void customerInfoContractViolationOnPurchasePathCarriesUserCancelled() throws Exception {
        JSONObject body = new JSONObject(Fixtures.read("backend/customer-info-minimal.json"));
        body.getJSONObject("subscriber").remove("first_seen");
        CustomerInfo info = RevenueDogTestModels.customerInfoFromJson(body.toString());
        try {
            Mappers.purchaseResult(info, transaction("2000000987654321"), false, DiagnosticsSink.NONE);
            fail("expected BridgeErrorException");
        } catch (BridgeErrorException e) {
            assertEquals("12", e.envelope.code);
            assertEquals(Boolean.FALSE, e.envelope.details.get("userCancelled"));
        }
    }

    // -------------------------------------------------------------------------------------------
    // IntroEligibility（§5.5）
    // -------------------------------------------------------------------------------------------

    @Test
    public void eligibilityIsAlwaysUnknown() {
        Map<String, Object> actual = Mappers.introEligibility(
                Arrays.asList("premium_monthly", "premium_annual", "unknown_product"));
        Fixtures.assertDeepEquals(Fixtures.parse(Fixtures.read("wire/intro-eligibility-android.json")), actual);
    }
}
