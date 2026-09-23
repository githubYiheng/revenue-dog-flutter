/// 权益验证模式。对照 RC：值集与顺序逐字照 RC `EntitlementVerificationMode`（`enforced` RC 亦未开放）。
///
/// 我方无 Trusted Entitlements：`configure` 时非 [disabled] → 抛码 23（设计 §1 #1）。
/// 偏离：RC 另有扩展 `EntitlementVerificationModeExtension.name`（通道值），我方不下发该字段，未声明。
enum EntitlementVerificationMode {
  /// 不做验证（默认，我方唯一支持的取值）。
  disabled,

  /// 信息性验证（我方不支持）。
  informational,
}
