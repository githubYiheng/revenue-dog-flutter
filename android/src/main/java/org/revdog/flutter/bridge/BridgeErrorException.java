package org.revdog.flutter.bridge;

/**
 * Bridge 判定「这次调用应以某个现成信封失败」（设计 §5.3 码 2、§3 B5 / §5.5 购买结果的 0 / 12 / 20）。
 *
 * 与 {@link WireContractException} 的区别：后者一律转码 12 且不带 {@code userCancelled}；本异常自带完整信封
 * （购买路径带 {@code userCancelled}），插件原样回给 Dart。{@link #severe} 为 true 时插件打 error 日志
 * （原生契约违规：无交易 / 交易 id 空 / CustomerInfo 契约违约），否则不打（待定、商品全缺属正常业务结果）。
 */
public final class BridgeErrorException extends RuntimeException {

    public final ErrorEnvelope envelope;
    public final boolean severe;

    public BridgeErrorException(ErrorEnvelope envelope, boolean severe) {
        super(String.valueOf(envelope.details.get("underlyingErrorMessage")));
        this.envelope = envelope;
        this.severe = severe;
    }
}
