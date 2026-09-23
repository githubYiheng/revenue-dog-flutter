package org.revdog.flutter.bridge;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import org.json.JSONObject;
import org.junit.Test;
import org.revdog.purchases.RevenueDogTestModels;
import org.revdog.purchases.customerinfo.CustomerInfo;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * 三方对账（设计 §7「Android Bridge 测试」）：backend fixture → M0 测试工厂（与真实网络路径同一解析器）
 * → {@link Mappers} → 与 wire fixture 深度相等。每次运行都重新读 fixture 文件（fixture 是契约，可能被并行修改）。
 */
public class MappersTest {

    /** 记录型诊断替身：断言回退被记下。 */
    private static final class RecordingSink implements DiagnosticsSink {
        final List<String> records = new ArrayList<>();

        @Override
        public void recordWarning(String code, String detail) {
            records.add(code + "|" + detail);
        }
    }

    private static CustomerInfo backend(String name) {
        return RevenueDogTestModels.customerInfoFromJson(Fixtures.read("backend/" + name));
    }

    private static void assertCustomerInfoFixture(String name, List<String> expectedDiagnostics) {
        RecordingSink sink = new RecordingSink();
        Map<String, Object> actual = Mappers.customerInfo(backend(name), sink);
        Fixtures.assertDeepEquals(Fixtures.parse(Fixtures.read("wire/" + name)), actual);
        assertEquals(expectedDiagnostics, sink.records);
    }

    @Test
    public void customerInfoMinimal() {
        assertCustomerInfoFixture("customer-info-minimal.json", Collections.emptyList());
    }

    @Test
    public void customerInfoFull() {
        assertCustomerInfoFixture("customer-info-full.json", Collections.emptyList());
    }

    @Test
    public void customerInfoOriginalPurchaseDateNullFallsBackAndRecordsDiagnostic() {
        assertCustomerInfoFixture("customer-info-original-purchase-date-null.json",
                Collections.singletonList(
                        Mappers.WARNING_FIELD_FALLBACK + "|" + Mappers.DETAIL_ENTITLEMENT_ORIGINAL_PURCHASE_DATE));
    }

    @Test
    public void logInResult() {
        Map<String, Object> actual =
                Mappers.logInResult(backend("customer-info-minimal.json"), true, DiagnosticsSink.NONE);
        Fixtures.assertDeepEquals(Fixtures.parse(Fixtures.read("wire/log-in-result.json")), actual);
    }

    @Test
    public void timesAreLongs() {
        Map<String, Object> actual = Mappers.customerInfo(backend("customer-info-full.json"), DiagnosticsSink.NONE);
        assertTrue(actual.get("firstSeen") instanceof Long);
        assertTrue(actual.get("requestDate") instanceof Long);
        assertTrue(actual.get("latestExpirationDate") instanceof Long);
    }

    /** 契约非空键原生为 null（这里：first_seen 缺失）→ WireContractException（插件转码 12），不静默默认。 */
    @Test
    public void missingFirstSeenViolatesContract() throws Exception {
        JSONObject body = new JSONObject(Fixtures.read("backend/customer-info-minimal.json"));
        body.getJSONObject("subscriber").remove("first_seen");
        CustomerInfo info = RevenueDogTestModels.customerInfoFromJson(body.toString());
        try {
            Mappers.customerInfo(info, DiagnosticsSink.NONE);
            fail("expected WireContractException");
        } catch (WireContractException e) {
            assertTrue(e.getMessage(), e.getMessage().contains("firstSeen"));
        }
    }
}
