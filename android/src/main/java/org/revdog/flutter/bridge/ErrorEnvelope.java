package org.revdog.flutter.bridge;

import java.util.Map;

/**
 * 错误信封（设计 §5.6），插件原样交给 {@code result.error(code, message, details)}，
 * Dart 侧得到 {@code PlatformException(code, message, details)}。不依赖 Flutter 类型。
 */
public final class ErrorEnvelope {

    /** 十进制码串，永不出非数字。 */
    public final String code;
    public final String message;
    public final Map<String, Object> details;

    ErrorEnvelope(String code, String message, Map<String, Object> details) {
        this.code = code;
        this.message = message;
        this.details = details;
    }
}
