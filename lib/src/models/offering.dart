import 'package:equatable/equatable.dart';

import '../wire.dart';
import 'package.dart';

/// 一组可售档位。对照 RC：字段集（12 字段）、构造签名、`getPackage` 逐字照 RC 10.13.1 `Offering`；填充规则见设计 §5.3。
///
/// 通道形状：`{identifier, serverDescription, availablePackages}`。
/// - [metadata] 为文档化常量 `{}`（两端原生无 metadata，08 R8；通道不发）；
/// - [lifetime] / [annual] / [sixMonth] / [threeMonth] / [twoMonth] / [monthly] / [weekly] 通道不发，
///   由 Dart 从 [availablePackages] 按 [PackageType] 取首个；
/// - [webCheckoutUrl] 为文档化常量 `null`（通道不发）。
/// [availablePackages] 已由原生插件剔除查不到商品的 package（设计 §5.3）。
class Offering extends Equatable {
  /// offering 标识。
  final String identifier;

  /// 后台描述。
  final String serverDescription;

  /// 后台 metadata（我方恒 `{}`）。
  final Map<String, Object> metadata;

  /// 可售档位（后台顺序）。
  final List<Package> availablePackages;

  /// 终身档。
  final Package? lifetime;

  /// 年档。
  final Package? annual;

  /// 六个月档。
  final Package? sixMonth;

  /// 三个月档。
  final Package? threeMonth;

  /// 两个月档。
  final Package? twoMonth;

  /// 月档。
  final Package? monthly;

  /// 周档。
  final Package? weekly;

  /// Web 购买链接（我方恒 null）。
  final String? webCheckoutUrl;

  const Offering(
    this.identifier,
    this.serverDescription,
    this.metadata,
    this.availablePackages, {
    this.lifetime,
    this.annual,
    this.sixMonth,
    this.threeMonth,
    this.twoMonth,
    this.monthly,
    this.weekly,
    this.webCheckoutUrl,
  });

  /// 按 package 标识取档位（精确匹配）。
  Package? getPackage(String identifier) =>
      availablePackages.firstWhereOrNull((package) => package.identifier == identifier);

  /// 由通道 map 构造（设计 §5.3）。缺键 / 类型错抛码 12。
  ///
  /// 偏离 RC：便捷档位不从输入读，由 [availablePackages] 派生；`metadata` 恒 `{}`。
  factory Offering.fromJson(Map<String, dynamic> json) => decodeOffering(WireMap.fromChannel(json));

  @override
  List<Object?> get props => [
        identifier,
        serverDescription,
        metadata,
        availablePackages,
        lifetime,
        annual,
        sixMonth,
        threeMonth,
        twoMonth,
        monthly,
        weekly,
        webCheckoutUrl,
      ];
}

/// 对照 RC：`OfferingX.getMetadataString` 逐字照抄（我方 metadata 恒空，恒返回 [defaultValue]）。
extension OfferingX on Offering {
  /// 取 metadata 里的字符串，缺失或非字符串 → [defaultValue]。
  String getMetadataString(String key, String defaultValue) {
    final value = metadata[key];
    if (value != null && value is String) {
      return value;
    }
    return defaultValue;
  }
}

/// 对照 RC：`PackageListX.firstWhereOrNull` 逐字照抄。
extension PackageListX on List<Package> {
  /// 第一个满足 [test] 的 package；没有 → null。
  Package? firstWhereOrNull(bool Function(Package element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

/// wire → [Offering]（不导出）。
Offering decodeOffering(WireMap w) {
  final packages = w.requireMapList('availablePackages').map(decodePackage).toList();
  Package? first(PackageType type) => packages.firstWhereOrNull((p) => p.packageType == type);
  return Offering(
    w.requireString('identifier'),
    w.requireString('serverDescription'),
    const <String, Object>{},
    packages,
    lifetime: first(PackageType.lifetime),
    annual: first(PackageType.annual),
    sixMonth: first(PackageType.sixMonth),
    threeMonth: first(PackageType.threeMonth),
    twoMonth: first(PackageType.twoMonth),
    monthly: first(PackageType.monthly),
    weekly: first(PackageType.weekly),
  );
}
