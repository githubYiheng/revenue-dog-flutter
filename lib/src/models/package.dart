import 'package:equatable/equatable.dart';

import '../wire.dart';
import 'presented_offering_context.dart';
import 'store_product.dart';

/// package 类型。对照 RC：值集（9 值）与顺序逐字照 RC 10.13.1 `PackageType`（宿主穷尽 switch，值集冻结）。
///
/// 通道值 `unknown|custom|lifetime|annual|six_month|three_month|two_month|monthly|weekly`；
/// 非标准 package（如 `custom_pack`）由原生映射为 `custom`，未知值 → [PackageType.unknown]。
enum PackageType {
  /// 无法识别。
  unknown,

  /// 自定义 package。
  custom,

  /// 终身。
  lifetime,

  /// 年。
  annual,

  /// 六个月。
  sixMonth,

  /// 三个月。
  threeMonth,

  /// 两个月。
  twoMonth,

  /// 月。
  monthly,

  /// 周。
  weekly,
}

/// 通道值 → [PackageType]（不导出）。
const Map<String, PackageType> packageTypeByWire = {
  'unknown': PackageType.unknown,
  'custom': PackageType.custom,
  'lifetime': PackageType.lifetime,
  'annual': PackageType.annual,
  'six_month': PackageType.sixMonth,
  'three_month': PackageType.threeMonth,
  'two_month': PackageType.twoMonth,
  'monthly': PackageType.monthly,
  'weekly': PackageType.weekly,
};

/// offering 里的一个档位。对照 RC：字段集、构造签名逐字照 RC 10.13.1 `Package`；填充规则见设计 §5.3。
///
/// 通道形状：`{identifier, packageType, offeringIdentifier, storeProduct, presentedOfferingContext}`；
/// `offeringIdentifier` 必须等于 `presentedOfferingContext.offeringIdentifier`（否则码 12）。
/// [webCheckoutUrl] 为文档化常量 `null`（我方无 Web 购买，通道不发）。
class Package extends Equatable {
  /// package 标识（如 `$rc_monthly`）。
  final String identifier;

  /// package 类型。
  final PackageType packageType;

  /// 商店商品（剔除规则保证恒非空，设计 §5.3）。
  final StoreProduct storeProduct;

  /// 所属 offering 上下文（购买时回传 `offeringIdentifier`）。
  final PresentedOfferingContext presentedOfferingContext;

  /// Web 购买链接（我方恒 null）。
  final String? webCheckoutUrl;

  const Package(
    this.identifier,
    this.packageType,
    this.storeProduct,
    this.presentedOfferingContext, {
    this.webCheckoutUrl,
  });

  /// 由通道 map 构造（设计 §5.3）。缺键 / 类型错抛码 12。
  ///
  /// 偏离 RC：商品键为 `storeProduct`（RC 通道为 `product`），枚举为 lower_snake_case（RC 为大写）。
  factory Package.fromJson(Map<String, dynamic> json) => decodePackage(WireMap.fromChannel(json));

  @override
  List<Object?> get props => [identifier, packageType, storeProduct, presentedOfferingContext, webCheckoutUrl];
}

/// 对照 RC：`ExtendedPackage`（弃用的 offering 标识 getter）逐字照抄。
extension ExtendedPackage on Package {
  /// 所属 offering 标识。
  @Deprecated('use presentedOfferingContext')
  String get offeringIdentifier => presentedOfferingContext.offeringIdentifier;
}

/// wire → [Package]（不导出）。
Package decodePackage(WireMap w) {
  final offeringIdentifier = w.requireString('offeringIdentifier');
  final context = decodePresentedOfferingContext(w.requireMap('presentedOfferingContext'));
  if (context.offeringIdentifier != offeringIdentifier) {
    throwWireError(
      w.keyPath('presentedOfferingContext.offeringIdentifier'),
      'does not match offeringIdentifier $offeringIdentifier',
    );
  }
  return Package(
    w.requireString('identifier'),
    w.requireEnum('packageType', packageTypeByWire, PackageType.unknown),
    decodeStoreProduct(w.requireMap('storeProduct')),
    context,
  );
}
