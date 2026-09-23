import 'package:equatable/equatable.dart';

import '../wire.dart';

/// 商品被展示时所在的 offering 上下文（购买归因用）。
/// 对照 RC：字段集、构造签名、`toJson` 逐字照 RC 10.13.1 `PresentedOfferingContext`。
///
/// 填充规则（设计 §5.3）：`offeringIdentifier` = 所属 offering；`placementIdentifier` / `targetingContext`
/// 为文档化常量 `null`（我方无 placement / targeting，08 R8）。
class PresentedOfferingContext extends Equatable {
  /// 所属 offering 标识。
  final String offeringIdentifier;

  /// placement 标识（我方恒 null）。
  final String? placementIdentifier;

  /// targeting 上下文（我方恒 null）。
  final PresentedOfferingTargetingContext? targetingContext;

  const PresentedOfferingContext(
    this.offeringIdentifier,
    this.placementIdentifier,
    this.targetingContext,
  );

  /// 序列化（照 RC）。
  Map<String, Object?> toJson() => {
        'offeringIdentifier': offeringIdentifier,
        'placementIdentifier': placementIdentifier,
        'targetingContext': targetingContext?.toJson(),
      };

  /// 由通道 map 构造。缺键 / 类型错抛码 12。
  factory PresentedOfferingContext.fromJson(Map<String, dynamic> json) =>
      decodePresentedOfferingContext(WireMap.fromChannel(json));

  @override
  List<Object?> get props => [offeringIdentifier, placementIdentifier, targetingContext];
}

/// targeting 规则上下文。对照 RC：字段集、构造签名逐字照 RC 10.13.1 `PresentedOfferingTargetingContext`。
/// 我方无 targeting（Experiments P2），通道上恒 null；声明只为类型同形。
class PresentedOfferingTargetingContext extends Equatable {
  /// 规则版本。
  final int revision;

  /// 规则 id。
  final String ruleId;

  const PresentedOfferingTargetingContext(this.revision, this.ruleId);

  /// 序列化（照 RC）。
  Map<String, Object?> toJson() => {'revision': revision, 'ruleId': ruleId};

  /// 由通道 map 构造。缺键 / 类型错抛码 12。
  factory PresentedOfferingTargetingContext.fromJson(Map<String, dynamic> json) {
    final w = WireMap.fromChannel(json);
    return PresentedOfferingTargetingContext(w.requireInt('revision'), w.requireString('ruleId'));
  }

  @override
  List<Object> get props => [revision, ruleId];
}

/// wire → [PresentedOfferingContext]（不导出）。
PresentedOfferingContext decodePresentedOfferingContext(WireMap w) {
  final targeting = w.optionalMap('targetingContext');
  return PresentedOfferingContext(
    w.requireString('offeringIdentifier'),
    w.optionalString('placementIdentifier'),
    targeting == null
        ? null
        : PresentedOfferingTargetingContext(
            targeting.requireInt('revision'),
            targeting.requireString('ruleId'),
          ),
  );
}
