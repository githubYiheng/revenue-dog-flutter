package org.revdog.flutter.bridge;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

/**
 * 通道方法 {@code setReservedAttribute {key, value}} 的键表（rc.4，设计 §5.8，ADR 0245）。
 *
 * <p>范围 = 服务端广告转发读取的全部保留属性；顺序与 {@code test/fixtures/wire/reserved-attributes.json} 逐行相同（JUnit 比对）。
 * {@link #passthrough} = Android 原生（0.2.0）有同名 setter，插件透传；{@code false} = 原生没有，插件校验参数后静默成功、不落数据
 * （原生补上后改为透传）。插件用 switch 分派到原生 setter，本类不碰原生单例。
 */
public enum ReservedAttribute {
    EMAIL("$email", ValueKind.STRING, true),
    PHONE_NUMBER("$phoneNumber", ValueKind.STRING, true),
    ATT_CONSENT_STATUS("$attConsentStatus", ValueKind.STRING, true),
    IDFA("$idfa", ValueKind.STRING, true),
    IDFV("$idfv", ValueKind.STRING, true),
    FB_ANONYMOUS_ID("$fbAnonId", ValueKind.STRING, true),
    FIREBASE_APP_INSTANCE_ID("$firebaseAppInstanceId", ValueKind.STRING, true),
    TIMEZONE("$timezone", ValueKind.STRING, false),
    AD_MEASUREMENT_CONSENT("$adMeasurementConsent", ValueKind.BOOL, false),
    FB_CAMPAIGN_IDS("$fbCampaignIds", ValueKind.STRING, false);

    public enum ValueKind {
        STRING("string"),
        BOOL("bool");

        public final String wire;

        ValueKind(String wire) {
            this.wire = wire;
        }
    }

    public final String key;
    public final ValueKind valueKind;
    public final boolean passthrough;

    ReservedAttribute(String key, ValueKind valueKind, boolean passthrough) {
        this.key = key;
        this.valueKind = valueKind;
        this.passthrough = passthrough;
    }

    /** 缺键 / 未知键 → {@link IllegalArgumentException}（插件转成码 4）。 */
    @NonNull
    public static ReservedAttribute fromKey(@Nullable String key) {
        if (key == null) {
            throw new IllegalArgumentException("missing argument key");
        }
        for (ReservedAttribute attribute : values()) {
            if (attribute.key.equals(key)) {
                return attribute;
            }
        }
        throw new IllegalArgumentException("unknown reserved attribute key " + key);
    }

    /**
     * 校验值类型：string 行收 {@code String} / null，bool 行收 {@code Boolean} / null；不符 → {@link IllegalArgumentException}。
     * 返回原值（null = 删除；空串原样交给原生，原生同样按删除处理）。
     */
    @Nullable
    public Object checkValue(@Nullable Object value) {
        if (value == null) {
            return null;
        }
        if (valueKind == ValueKind.STRING && value instanceof String) {
            return value;
        }
        if (valueKind == ValueKind.BOOL && value instanceof Boolean) {
            return value;
        }
        throw new IllegalArgumentException("argument value must be a "
                + (valueKind == ValueKind.STRING ? "String" : "bool") + " for " + key);
    }
}
