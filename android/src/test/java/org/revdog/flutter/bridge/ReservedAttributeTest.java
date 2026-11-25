package org.revdog.flutter.bridge;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.fail;

import org.junit.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 保留属性键表对账（rc.4，设计 §5.8）：{@link ReservedAttribute#values()} 与 {@code wire/reserved-attributes.json}
 * 逐行相等（键、值类型、Android 行为，顺序也比）。
 */
public class ReservedAttributeTest {

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> rows() {
        Map<String, Object> table = (Map<String, Object>) Fixtures.parse(Fixtures.read("wire/reserved-attributes.json"));
        assertEquals("setReservedAttribute", table.get("method"));
        return (List<Map<String, Object>>) table.get("attributes");
    }

    @Test
    public void valuesMatchFixtureInOrder() {
        List<String> expected = new ArrayList<>();
        for (Map<String, Object> row : rows()) {
            expected.add(row.get("key") + "|" + row.get("value") + "|" + row.get("android"));
        }
        List<String> actual = new ArrayList<>();
        for (ReservedAttribute attribute : ReservedAttribute.values()) {
            actual.add(attribute.key + "|" + attribute.valueKind.wire + "|"
                    + (attribute.passthrough ? "passthrough" : "noop"));
        }
        assertEquals(expected, actual);
    }

    @Test
    public void passthroughRowsAreAllStrings() {
        // 插件把透传值按 String 交给原生 setter；bool 行（$adMeasurementConsent）原生 0.2.0 没有 setter，只能是 noop。
        for (ReservedAttribute attribute : ReservedAttribute.values()) {
            if (attribute.passthrough) {
                assertSame(attribute.key, ReservedAttribute.ValueKind.STRING, attribute.valueKind);
            }
        }
    }

    @Test
    public void fromKeyAndCheckValue() {
        for (ReservedAttribute attribute : ReservedAttribute.values()) {
            assertSame(attribute, ReservedAttribute.fromKey(attribute.key));
            Object present = attribute.valueKind == ReservedAttribute.ValueKind.BOOL ? Boolean.TRUE : "value_1";
            assertEquals(present, attribute.checkValue(present));
            assertNull(attribute.checkValue(null));
        }
        assertEquals("", ReservedAttribute.IDFA.checkValue(""));
        assertEquals(Boolean.FALSE, ReservedAttribute.AD_MEASUREMENT_CONSENT.checkValue(Boolean.FALSE));
    }

    @Test
    public void invalidArguments() {
        expectInvalid("missing argument key", () -> ReservedAttribute.fromKey(null));
        expectInvalid("unknown reserved attribute key $unknown", () -> ReservedAttribute.fromKey("$unknown"));
        expectInvalid("argument value must be a String for $idfa", () -> ReservedAttribute.IDFA.checkValue(Boolean.TRUE));
        expectInvalid("argument value must be a String for $idfa", () -> ReservedAttribute.IDFA.checkValue(1));
        expectInvalid("argument value must be a bool for $adMeasurementConsent",
                () -> ReservedAttribute.AD_MEASUREMENT_CONSENT.checkValue("true"));
        expectInvalid("argument value must be a bool for $adMeasurementConsent",
                () -> ReservedAttribute.AD_MEASUREMENT_CONSENT.checkValue(1));
    }

    private static void expectInvalid(String message, Runnable body) {
        try {
            body.run();
            fail("expected IllegalArgumentException: " + message);
        } catch (IllegalArgumentException e) {
            assertEquals(message, e.getMessage());
        }
    }
}
