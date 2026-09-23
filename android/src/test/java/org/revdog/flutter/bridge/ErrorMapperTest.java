package org.revdog.flutter.bridge;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;
import org.revdog.purchases.PurchasesError;
import org.revdog.purchases.PurchasesErrorCode;

import java.io.File;
import java.util.HashMap;
import java.util.Map;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 错误信封对账（设计 §5.6）：每个 {@code test/fixtures/wire/errors/*.json} 由对应的原生 {@link PurchasesError}
 * （公开构造器）经 {@link ErrorMapper} 产出，与 fixture 深度相等。样例值（message / underlying / 排障键）按 fixture 构造源错误。
 */
public class ErrorMapperTest {

    private static Map<String, Object> toMap(ErrorEnvelope envelope) {
        Map<String, Object> map = new HashMap<>();
        map.put("code", envelope.code);
        map.put("message", envelope.message);
        map.put("details", envelope.details);
        return map;
    }

    private static void assertFixture(String file, ErrorEnvelope envelope) {
        Fixtures.assertDeepEquals(Fixtures.parse(Fixtures.read("wire/errors/" + file)), toMap(envelope));
    }

    /** fixture 与构造的对应表；{@link #everyErrorFixtureIsCovered} 保证不漏文件。 */
    private static Map<String, ErrorEnvelope> cases() {
        Map<String, ErrorEnvelope> cases = new TreeMap<>();
        // 购买路径（M2 用）：取消 / 待定由插件归一（D3），userCancelled 仅购买路径发。
        cases.put("purchase-cancelled-1.json", ErrorMapper.fromPurchasesError(
                new PurchasesError(PurchasesErrorCode.PurchaseCancelledError), true));
        cases.put("payment-pending-20.json", ErrorMapper.fromPurchasesError(
                new PurchasesError(PurchasesErrorCode.PaymentPendingError), false));
        // logOut 路径专用映射：14 → 22（裁定 6）。
        cases.put("log-out-anonymous-22.json", ErrorMapper.fromLogOutError(
                new PurchasesError(PurchasesErrorCode.InvalidAppUserIdError,
                        "logOut called while the current user is anonymous")));
        // 未配置守卫（插件合成）。
        cases.put("configuration-23.json", ErrorMapper.synthetic(
                PurchasesErrorCode.ConfigurationError, ErrorMapper.NOT_CONFIGURED_UNDERLYING));
        // 原生码 12（带排障键，非购买路径 → 无 userCancelled）。
        cases.put("unexpected-backend-12.json", ErrorMapper.fromPurchasesError(
                new PurchasesError(PurchasesErrorCode.UnexpectedBackendResponseError,
                        "missing request_date in subscriber response", null, 200, "req_01JABCDEF0123456789")));
        // 901 / 902：原生错误原样透传（购买路径）。
        cases.put("pending-server-901.json", ErrorMapper.fromPurchasesError(
                new PurchasesError(PurchasesErrorCode.PurchasePendingServerConfirmation,
                        "HTTP 503", null, 503, "req_01JPENDING000000001"), false));
        cases.put("rejected-by-server-902.json", ErrorMapper.fromPurchasesError(
                new PurchasesError(PurchasesErrorCode.PurchaseRejectedByServer,
                        "Bad parameters x", null, 400, "req_01JREJECTED00000001"), false));
        // M2 插件合成：getOfferings 商品全缺（码 2，非购买路径无 userCancelled，裁定 5）。
        cases.put("store-problem-2.json", ErrorMapper.synthetic(
                PurchasesErrorCode.StoreProblemError, Mappers.STORE_PRODUCTS_UNAVAILABLE));
        // M2 购买路径合成（B3）：定位失败码 5、无 Activity 码 4，均带 userCancelled:false。
        cases.put("product-not-found-5.json", ErrorMapper.syntheticPurchase(
                PurchasesErrorCode.ProductNotAvailableForPurchaseError, "package $rc_weekly not found in offering default"));
        cases.put("invalid-argument-4.json", ErrorMapper.syntheticPurchase(
                PurchasesErrorCode.PurchaseInvalidError, "no current Activity"));
        return cases;
    }

    @Test
    public void everyErrorFixtureMatches() {
        for (Map.Entry<String, ErrorEnvelope> entry : cases().entrySet()) {
            assertFixture(entry.getKey(), entry.getValue());
        }
    }

    @Test
    public void everyErrorFixtureIsCovered() {
        TreeSet<String> files = new TreeSet<>();
        File[] listed = new File(Fixtures.dir(), "wire/errors").listFiles((dir, name) -> name.endsWith(".json"));
        for (File file : listed) {
            files.add(file.getName());
        }
        assertEquals(files, new TreeSet<>(cases().keySet()));
    }

    /** 购买回调取消（码 1 + userCancelled）→ purchase-cancelled-1.json；待定原生错误（20）→ payment-pending-20.json。 */
    @Test
    public void purchaseCallbackErrorsMatchFixtures() {
        assertFixture("purchase-cancelled-1.json", ErrorMapper.fromPurchaseCallbackError(
                new PurchasesError(PurchasesErrorCode.PurchaseCancelledError), true));
        assertFixture("payment-pending-20.json", ErrorMapper.fromPurchaseCallbackError(
                new PurchasesError(PurchasesErrorCode.PaymentPendingError), false));
    }

    /** 原生 userCancelled == true 但码不是 1 → 按 1 发（D3），原生说明进 underlyingErrorMessage。 */
    @Test
    public void userCancelledWithOtherCodeIsReportedAsCode1() {
        PurchasesError error = new PurchasesError(PurchasesErrorCode.StoreProblemError, "billing flow closed");
        assertTrue(ErrorMapper.isInconsistentCancellation(error, true));
        ErrorEnvelope envelope = ErrorMapper.fromPurchaseCallbackError(error, true);
        assertEquals("1", envelope.code);
        assertEquals(Boolean.TRUE, envelope.details.get("userCancelled"));
        assertEquals("PurchaseCancelledError", envelope.details.get("readableErrorCode"));
        assertEquals("billing flow closed", envelope.details.get("underlyingErrorMessage"));
    }

    /** 购买路径非取消的原生错误（如 901）原样透传，userCancelled:false。 */
    @Test
    public void purchaseCallbackPassesThroughOtherCodes() {
        PurchasesError error = new PurchasesError(PurchasesErrorCode.PurchasePendingServerConfirmation,
                "HTTP 503", null, 503, "req_01JPENDING000000001");
        assertFixture("pending-server-901.json", ErrorMapper.fromPurchaseCallbackError(error, false));
    }

    /** 参数缺失（购买路径）→ 码 4，underlying 为 {@code missing argument <name>}，其余键同 invalid-argument-4.json。 */
    @Test
    public void missingArgumentOnPurchasePath() {
        @SuppressWarnings("unchecked")
        Map<String, Object> expected = (Map<String, Object>) Fixtures.parse(Fixtures.read("wire/errors/invalid-argument-4.json"));
        @SuppressWarnings("unchecked")
        Map<String, Object> details = (Map<String, Object>) expected.get("details");
        details.put("underlyingErrorMessage", "missing argument packageIdentifier");
        Fixtures.assertDeepEquals(expected, toMap(ErrorMapper.syntheticPurchase(
                PurchasesErrorCode.PurchaseInvalidError, "missing argument packageIdentifier")));
    }

    /** logOut 路径以外的 14 照常映射（不串路径）。 */
    @Test
    public void invalidAppUserIdOutsideLogOutStays14() {
        ErrorEnvelope envelope = ErrorMapper.fromPurchasesError(
                new PurchasesError(PurchasesErrorCode.InvalidAppUserIdError, "bad id"));
        assertEquals("14", envelope.code);
        assertEquals("bad id", envelope.message);
        assertEquals("InvalidAppUserIdError", envelope.details.get("readableErrorCode"));
    }

    /** logOut 路径上的其它码不被改写。 */
    @Test
    public void logOutPathKeepsOtherCodes() {
        ErrorEnvelope envelope = ErrorMapper.fromLogOutError(new PurchasesError(PurchasesErrorCode.NetworkError, "offline"));
        assertEquals("10", envelope.code);
        assertEquals("NetworkError", envelope.details.get("readable_error_code"));
        assertEquals("networkError", envelope.details.get("revdogCode"));
    }

    /** 合成短句表与 Dart {@code lib/src/errors.dart} 的 syntheticErrorMessages 逐字一致。 */
    @Test
    public void syntheticMessagesMatchDart() {
        String dart = Fixtures.read(new File(Fixtures.packageRoot(), "lib/src/errors.dart"));
        int start = dart.indexOf("syntheticErrorMessages = {");
        int end = dart.indexOf("};", start);
        Matcher matcher = Pattern.compile("(\\d+): '((?:[^'\\\\]|\\\\.)*)'").matcher(dart.substring(start, end));
        Map<Integer, String> fromDart = new TreeMap<>();
        while (matcher.find()) {
            fromDart.put(Integer.parseInt(matcher.group(1)), matcher.group(2).replace("\\'", "'"));
        }
        assertEquals(fromDart, new TreeMap<>(ErrorMapper.SYNTHETIC_MESSAGES));
    }

    /** readableErrorCode（code.name 首字母大写）与 Dart 生成码表 readableErrorCodeByNumber 对每个原生码位一致（D4）。 */
    @Test
    public void readableErrorCodesMatchDartTable() {
        String dart = Fixtures.read(new File(Fixtures.packageRoot(), "lib/src/generated/error_codes.dart"));
        int start = dart.indexOf("readableErrorCodeByNumber = {");
        int end = dart.indexOf("};", start);
        Matcher matcher = Pattern.compile("(\\d+): '([A-Za-z0-9]+)'").matcher(dart.substring(start, end));
        Map<Integer, String> fromDart = new TreeMap<>();
        while (matcher.find()) {
            fromDart.put(Integer.parseInt(matcher.group(1)), matcher.group(2));
        }
        for (PurchasesErrorCode code : PurchasesErrorCode.ALL) {
            ErrorEnvelope envelope = ErrorMapper.fromPurchasesError(new PurchasesError(code));
            assertEquals("code " + code.getCode(), fromDart.get(code.getCode()), envelope.details.get("readableErrorCode"));
        }
    }
}
