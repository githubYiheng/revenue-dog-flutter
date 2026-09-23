package org.revdog.flutter.bridge;

/**
 * 契约规定非空、原生却给了 null（设计 §5 总则「可空与回退」）。
 *
 * Bridge 不做静默默认：抛出本异常，插件转成码 12 {@code unexpectedBackendResponseError} 信封并打 error 日志。
 * {@link #getMessage()} 即信封的 {@code underlyingErrorMessage}，写明缺的是哪个 wire 键。
 */
public final class WireContractException extends RuntimeException {

    public WireContractException(String message) {
        super(message);
    }
}
