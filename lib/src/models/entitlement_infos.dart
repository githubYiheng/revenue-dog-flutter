import 'package:equatable/equatable.dart';

import '../wire.dart';
import 'entitlement_info.dart';
import 'verification_result.dart';

/// 用户的全部权益。对照 RC：字段集与构造签名逐字照 RC `EntitlementInfos`。
class EntitlementInfos extends Equatable {
  /// 全部权益（含已过期），键 = 权益标识。
  final Map<String, EntitlementInfo> all;

  /// 有效权益，键 = 权益标识。不变式：键集 == [all] 中 `isActive == true` 的键集（fixture 测试钉死）。
  final Map<String, EntitlementInfo> active;

  /// 验证结果；我方恒 [VerificationResult.notRequested]。
  final VerificationResult verification;

  const EntitlementInfos(
    this.all,
    this.active, {
    this.verification = VerificationResult.notRequested,
  });

  /// 由通道 map 构造（设计 §5.2）。缺键 / 类型错抛码 12。
  factory EntitlementInfos.fromJson(Map<String, dynamic> json) =>
      decodeEntitlementInfos(WireMap.fromChannel(json));

  @override
  List<Object?> get props => [all, active, verification];
}

/// wire → [EntitlementInfos]（不导出）。
EntitlementInfos decodeEntitlementInfos(WireMap w) => EntitlementInfos(
      w.requireMapOfMaps('all').map((k, v) => MapEntry(k, decodeEntitlementInfo(v))),
      w.requireMapOfMaps('active').map((k, v) => MapEntry(k, decodeEntitlementInfo(v))),
      verification: w.requireEnum('verification', verificationResultByWire, VerificationResult.notRequested),
    );
