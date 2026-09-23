import 'package:equatable/equatable.dart';

import '../wire.dart';
import 'store.dart';
import 'verification_result.dart';

/// 权益的周期类型。对照 RC：值集与顺序逐字照 RC `PeriodType`。通道值 `intro|normal|trial|prepaid|unknown`。
enum PeriodType {
  /// 优惠价周期。
  intro,

  /// 常规周期。
  normal,

  /// 试用期。
  trial,

  /// 预付费周期。
  prepaid,

  /// 无法判定。
  unknown,
}

/// 所有权类型。对照 RC：值集与顺序逐字照 RC `OwnershipType`。通道值 `purchased|family_shared|unknown`。
enum OwnershipType {
  /// 本人购买。
  purchased,

  /// 家庭共享。
  familyShared,

  /// 未知。
  unknown,
}

/// 通道值 → [PeriodType]（不导出）。
const Map<String, PeriodType> periodTypeByWire = {
  'intro': PeriodType.intro,
  'normal': PeriodType.normal,
  'trial': PeriodType.trial,
  'prepaid': PeriodType.prepaid,
  'unknown': PeriodType.unknown,
};

/// 通道值 → [OwnershipType]（不导出）。
const Map<String, OwnershipType> ownershipTypeByWire = {
  'purchased': OwnershipType.purchased,
  'family_shared': OwnershipType.familyShared,
  'unknown': OwnershipType.unknown,
};

/// 单个权益。对照 RC：字段集、构造签名、默认值逐字照 RC `EntitlementInfo`（15 字段）；填充规则见设计 §5.2。
class EntitlementInfo extends Equatable {
  /// 权益标识。
  final String identifier;

  /// 是否有效。iOS 取原生 `entitlements.active` 成员关系（08 R7），Android 取原生 `isActive`。
  final bool isActive;

  /// 是否会续订。
  final bool willRenew;

  /// 最近一次购买 / 续订时间（UTC ISO 8601）。
  final String latestPurchaseDate;

  /// 首次购买时间。原生为空时插件回退 [latestPurchaseDate] 并记诊断（裁定 3）。
  final String originalPurchaseDate;

  /// 解锁此权益的商品。Android 订阅为 subId（同 RC）。
  final String productIdentifier;

  /// 是否沙盒购买。
  final bool isSandbox;

  /// 所有权类型。
  final OwnershipType ownershipType;

  /// 来源商店。
  final Store store;

  /// 周期类型。
  final PeriodType periodType;

  /// 到期时间；null = 终身。
  final String? expirationDate;

  /// 检测到关闭自动续订的时间。
  final String? unsubscribeDetectedAt;

  /// 检测到扣款问题的时间。
  final String? billingIssueDetectedAt;

  /// Google base plan id（Google only）。
  final String? productPlanIdentifier;

  /// 验证结果；我方恒 [VerificationResult.notRequested]。
  final VerificationResult verification;

  const EntitlementInfo(
    this.identifier,
    this.isActive,
    this.willRenew,
    this.latestPurchaseDate,
    this.originalPurchaseDate,
    this.productIdentifier,
    this.isSandbox, {
    this.ownershipType = OwnershipType.unknown,
    this.store = Store.unknownStore,
    this.periodType = PeriodType.unknown,
    this.expirationDate,
    this.unsubscribeDetectedAt,
    this.billingIssueDetectedAt,
    this.productPlanIdentifier,
    this.verification = VerificationResult.notRequested,
  });

  /// 由通道 map 构造（wire 形状见设计 §5.2：时间为 epoch 毫秒、枚举为 lower_snake_case）。
  ///
  /// 偏离 RC：RC 的输入是 ISO 字符串 + 大写枚举；缺键 / 类型错抛码 12 的 `PlatformException`。
  factory EntitlementInfo.fromJson(Map<String, dynamic> json) =>
      decodeEntitlementInfo(WireMap.fromChannel(json));

  @override
  List<Object?> get props => [
        identifier,
        isActive,
        willRenew,
        latestPurchaseDate,
        originalPurchaseDate,
        productIdentifier,
        isSandbox,
        ownershipType,
        store,
        periodType,
        expirationDate,
        unsubscribeDetectedAt,
        billingIssueDetectedAt,
        productPlanIdentifier,
        verification,
      ];
}

/// wire → [EntitlementInfo]（不导出）。
EntitlementInfo decodeEntitlementInfo(WireMap w) => EntitlementInfo(
      w.requireString('identifier'),
      w.requireBool('isActive'),
      w.requireBool('willRenew'),
      w.requireDate('latestPurchaseDate'),
      w.requireDate('originalPurchaseDate'),
      w.requireString('productIdentifier'),
      w.requireBool('isSandbox'),
      ownershipType: w.requireEnum('ownershipType', ownershipTypeByWire, OwnershipType.unknown),
      store: w.requireEnum('store', storeByWire, Store.unknownStore),
      periodType: w.requireEnum('periodType', periodTypeByWire, PeriodType.unknown),
      expirationDate: w.optionalDate('expirationDate'),
      unsubscribeDetectedAt: w.optionalDate('unsubscribeDetectedAt'),
      billingIssueDetectedAt: w.optionalDate('billingIssueDetectedAt'),
      productPlanIdentifier: w.optionalString('productPlanIdentifier'),
      verification: w.requireEnum('verification', verificationResultByWire, VerificationResult.notRequested),
    );
