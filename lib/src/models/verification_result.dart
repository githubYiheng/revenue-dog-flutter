/// 权益验证结果。对照 RC：值集与顺序逐字照 RC `VerificationResult`。
///
/// 我方无 Trusted Entitlements，原生插件恒发文档化常量 `not_requested`（设计 §5.2）。
enum VerificationResult {
  /// 未请求验证（我方恒为此值）。
  notRequested,

  /// 已验证。
  verified,

  /// 设备端已验证。
  verifiedOnDevice,

  /// 验证失败。
  failed,
}

/// 通道值 → [VerificationResult]（不导出）。未知值 → [VerificationResult.notRequested]（同 RC 兜底）。
const Map<String, VerificationResult> verificationResultByWire = {
  'not_requested': VerificationResult.notRequested,
  'verified': VerificationResult.verified,
  'verified_on_device': VerificationResult.verifiedOnDevice,
  'failed': VerificationResult.failed,
};
