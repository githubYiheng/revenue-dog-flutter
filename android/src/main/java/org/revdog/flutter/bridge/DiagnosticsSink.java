package org.revdog.flutter.bridge;

/**
 * Bridge 记诊断的出口（设计 §5 总则「诊断」、裁定 10）。
 *
 * 插件里的实现转给原生 M0 内部入口 {@code Purchases.recordDiagnosticsWarning}（未配置时不记）；
 * Bridge 测试注入记录型替身断言回退被记下。Bridge 因此不直接碰原生单例，保持纯函数、可单测。
 */
public interface DiagnosticsSink {

    /** 记一条 {@code sdk_warning{code, detail}}，例如 {@code hybrid_field_fallback}。 */
    void recordWarning(String code, String detail);

    /** 什么都不记（未配置 / 不关心诊断的调用方）。 */
    DiagnosticsSink NONE = (code, detail) -> { };
}
