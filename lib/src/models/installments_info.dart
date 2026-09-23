import 'package:equatable/equatable.dart';

import '../wire.dart';

/// Play 分期订阅信息。对照 RC：字段集、构造签名逐字照 RC 10.13.1 `InstallmentsInfo`。
///
/// 我方原生未解析 Play 分期：`SubscriptionOption.installmentsInfo` 为文档化常量 `null`，通道不发（设计 §5.4b）。
class InstallmentsInfo extends Equatable {
  /// 承诺期付款次数。
  final int commitmentPaymentsCount;

  /// 续订承诺期付款次数。
  final int renewalCommitmentPaymentsCount;

  const InstallmentsInfo(this.commitmentPaymentsCount, this.renewalCommitmentPaymentsCount);

  /// 由通道 map 构造。缺键 / 类型错抛码 12。
  factory InstallmentsInfo.fromJson(Map<String, dynamic> json) {
    final w = WireMap.fromChannel(json);
    return InstallmentsInfo(w.requireInt('commitmentPaymentsCount'), w.requireInt('renewalCommitmentPaymentsCount'));
  }

  @override
  List<Object?> get props => [commitmentPaymentsCount, renewalCommitmentPaymentsCount];
}
