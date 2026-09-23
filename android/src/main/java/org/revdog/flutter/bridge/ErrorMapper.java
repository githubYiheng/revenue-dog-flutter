package org.revdog.flutter.bridge;

import org.revdog.purchases.PurchasesError;
import org.revdog.purchases.PurchasesErrorCode;

import java.util.Collections;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * {@link PurchasesError} → 错误信封（设计 §5.6；可执行版 = {@code test/fixtures/wire/errors/*.json}）。
 *
 * 信封：{@code code} 十进制串；{@code message}；{@code details{code:int, message, readableErrorCode,
 * readable_error_code, revdogCode, underlyingErrorMessage(缺省 ""), userCancelled(仅购买路径),
 * backendCode? / httpStatusCode? / requestId?(无值不放键)}}。
 *
 * {@code message} 规则：码在合成短句表（{@link #SYNTHETIC_MESSAGES}，逐字照抄 Dart {@code lib/src/errors.dart}
 * 的 {@code syntheticErrorMessages}）里 → 取表中短句，原生 message 进 {@code underlyingErrorMessage}；
 * 否则（如 901 / 902）→ 原生 {@code PurchasesError.getMessage()} 原样透传。
 *
 * 对照 RC：hybrid-common {@code ErrorContainer} 同样发 code / message / details(readableErrorCode,
 * readable_error_code, underlyingErrorMessage, userCancelled)；偏离（D4）：readable 统一 PascalCase 查表、
 * 增补 {@code revdogCode} 与排障键。
 */
public final class ErrorMapper {

    /**
     * 合成错误英文短句表。**逐字照抄** {@code sdk/flutter/lib/src/errors.dart} 的 {@code syntheticErrorMessages}，
     * 改一处必须两处一起改（wire fixture 会红）。
     */
    static final Map<Integer, String> SYNTHETIC_MESSAGES;

    static {
        Map<Integer, String> m = new HashMap<>();
        m.put(0, "Unknown error.");
        m.put(1, "Purchase was cancelled.");
        m.put(2, "There was a problem with the store.");
        m.put(4, "One or more of the arguments provided are invalid.");
        m.put(5, "The product is not available for purchase.");
        m.put(12, "unexpected backend response");
        m.put(20, "The payment is pending.");
        m.put(22, "LogOut was called but the current user is anonymous.");
        m.put(23, "There is an issue with your configuration. Check the underlying error for more details.");
        SYNTHETIC_MESSAGES = Collections.unmodifiableMap(m);
    }

    /** logOut 路径专用映射的目标码（RC {@code logOutWithAnonymousUserError}，裁定 6）。 */
    static final int LOG_OUT_WITH_ANONYMOUS_USER_CODE = 22;
    static final String LOG_OUT_WITH_ANONYMOUS_USER_READABLE = "LogOutWithAnonymousUserError";

    /** 未配置守卫的 underlyingErrorMessage（与 wire fixture {@code configuration-23.json} 同值）。 */
    public static final String NOT_CONFIGURED_UNDERLYING =
            "Purchases has not been configured; call Purchases.configure first";

    private ErrorMapper() {
    }

    /**
     * 原生错误 → 信封（非购买路径：不放 {@code userCancelled} 键）。
     */
    public static ErrorEnvelope fromPurchasesError(PurchasesError error) {
        return build(error.getCode().getCode(), error.getCode().getName(), null, error, null);
    }

    /**
     * 购买路径（M2）：带 {@code userCancelled}（码 1 为 true、其余 false，D3）。
     */
    public static ErrorEnvelope fromPurchasesError(PurchasesError error, boolean userCancelled) {
        return build(error.getCode().getCode(), error.getCode().getName(), null, error, userCancelled);
    }

    /**
     * logOut 路径专用映射（裁定 6）：我方码 14 {@code invalidAppUserIdError} → 信封 {@code code "22"}、
     * readable {@code LogOutWithAnonymousUserError}、{@code revdogCode} 仍为 {@code invalidAppUserIdError}。
     * 其它码照常映射。对照 RC：RC Android 在 logOut 匿名用户时直接报 22，宿主按 22 写的判断因此照旧有效。
     */
    public static ErrorEnvelope fromLogOutError(PurchasesError error) {
        if (error.getCode().getCode() == PurchasesErrorCode.InvalidAppUserIdError.getCode()) {
            return build(LOG_OUT_WITH_ANONYMOUS_USER_CODE, error.getCode().getName(),
                    LOG_OUT_WITH_ANONYMOUS_USER_READABLE, error, null);
        }
        return fromPurchasesError(error);
    }

    /**
     * 插件合成错误（未配置守卫 23、wire 契约违约 12、参数错误 4 …）。
     *
     * @param code 我方码位（{@link PurchasesErrorCode}）；message 取短句表。
     * @param underlyingErrorMessage 排障说明；null → {@code ""}。
     */
    public static ErrorEnvelope synthetic(PurchasesErrorCode code, String underlyingErrorMessage) {
        return fromPurchasesError(new PurchasesError(code, underlyingErrorMessage));
    }

    /**
     * 购买路径（M2）的插件合成错误：带 {@code userCancelled}（码 1 为 true、其余 false，D3）。
     * 用于 purchasePackage 的参数缺失 / 无 Activity（4）、定位失败（5）、待定（20）、无交易（0，B5）、交易 id 空（12，裁定 3）。
     */
    public static ErrorEnvelope syntheticPurchase(PurchasesErrorCode code, String underlyingErrorMessage) {
        return fromPurchasesError(new PurchasesError(code, underlyingErrorMessage),
                code.getCode() == PurchasesErrorCode.PurchaseCancelledError.getCode());
    }

    /**
     * {@code PurchaseCallback.onError(error, userCancelled)} → 信封（D3 / B4）。
     *
     * 归一：{@code userCancelled == true} 或原生码为 1 → 一律发码 1 + {@code userCancelled: true}；
     * 其余原样（含 901 / 902），{@code userCancelled: false}。原生取消时码应为 1，两者不一致由插件记 error 日志
     * （{@link #isInconsistentCancellation}），这里只管产出信封；不一致时原生错误的说明进 {@code underlyingErrorMessage}。
     * 对照 RC：hybrid-common {@code ErrorContainer} 同样以回调参数 userCancelled 为准；偏离：RC 不改写码，我方强制码 1（D3 两端归一）。
     */
    public static ErrorEnvelope fromPurchaseCallbackError(PurchasesError error, boolean userCancelled) {
        if (isInconsistentCancellation(error, userCancelled)) {
            String underlying = error.getUnderlyingErrorMessage() != null
                    ? error.getUnderlyingErrorMessage() : error.getMessage();
            return fromPurchasesError(new PurchasesError(PurchasesErrorCode.PurchaseCancelledError, underlying), true);
        }
        boolean cancelled = error.getCode().getCode() == PurchasesErrorCode.PurchaseCancelledError.getCode();
        return fromPurchasesError(error, cancelled);
    }

    /** 原生 {@code userCancelled} 与码 1 不一致（任一方说取消、另一方不是）。 */
    public static boolean isInconsistentCancellation(PurchasesError error, boolean userCancelled) {
        boolean codeIsCancel = error.getCode().getCode() == PurchasesErrorCode.PurchaseCancelledError.getCode();
        return userCancelled != codeIsCancel;
    }

    private static ErrorEnvelope build(
            int number, String revdogCode, String readableOverride, PurchasesError error, Boolean userCancelled) {
        String nativeMessage = error.getMessage();
        String underlying = error.getUnderlyingErrorMessage() == null ? "" : error.getUnderlyingErrorMessage();
        String synthetic = SYNTHETIC_MESSAGES.get(number);
        String message = synthetic != null ? synthetic : nativeMessage;
        String readable = readableOverride != null ? readableOverride : readableErrorCode(revdogCode);

        Map<String, Object> details = new HashMap<>();
        details.put("code", number);
        details.put("message", message);
        details.put("readableErrorCode", readable);
        details.put("readable_error_code", readable);
        details.put("revdogCode", revdogCode);
        details.put("underlyingErrorMessage", underlying);
        if (userCancelled != null) {
            details.put("userCancelled", userCancelled);
        }
        // 我方增补的排障键：无值不发键（§5.6）。
        if (error.getBackendCode() != null) {
            details.put("backendCode", error.getBackendCode());
        }
        if (error.getHttpStatusCode() != null) {
            details.put("httpStatusCode", error.getHttpStatusCode());
        }
        if (error.getRequestId() != null) {
            details.put("requestId", error.getRequestId());
        }
        return new ErrorEnvelope(String.valueOf(number), message, details);
    }

    /**
     * readableErrorCode = 我方 {@code code.name} 首字母大写（RC Android 式 PascalCase，D4）。
     * 我方码名与 RC Android 枚举名在 0–42 同形（如 {@code configurationError} → {@code ConfigurationError}），
     * 900+ 为我方名（{@code PurchasePendingServerConfirmation}）。
     */
    static String readableErrorCode(String name) {
        if (name.isEmpty()) {
            return name;
        }
        return name.substring(0, 1).toUpperCase(Locale.ROOT) + name.substring(1);
    }
}
