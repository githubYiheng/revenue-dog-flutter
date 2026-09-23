import 'package:equatable/equatable.dart';

import '../wire.dart';
import 'entitlement_info.dart';
import 'store.dart';

/// 单条订阅明细（`CustomerInfo.subscriptionsByProductIdentifier` 的值）。
/// 对照 RC：字段集（19 字段）、构造签名、默认值逐字照 RC `SubscriptionInfo`；填充规则见设计 §5.1b。
class SubscriptionInfo extends Equatable {
  /// 商品标识。
  final String productIdentifier;

  /// 本周期开始时间。
  final String purchaseDate;

  /// 是否沙盒。
  final bool isSandbox;

  /// 当前是否有效。
  final bool isActive;

  /// 是否会续订。
  final bool willRenew;

  /// 首次订阅时间。
  final String? originalPurchaseDate;

  /// 到期时间。
  final String? expiresDate;

  /// 来源商店。
  final Store store;

  /// 检测到关闭自动续订的时间。
  final String? unsubscribeDetectedAt;

  /// 检测到扣款问题的时间（注意复数 `Issues`，与 `EntitlementInfo.billingIssueDetectedAt` 不同，同 RC）。
  final String? billingIssuesDetectedAt;

  /// 宽限期到期时间。
  final String? gracePeriodExpiresDate;

  /// 所有权类型。
  final OwnershipType ownershipType;

  /// 周期类型。
  final PeriodType periodType;

  /// 检测到退款的时间。
  final String? refundedAt;

  /// 商店侧交易标识。
  final String? storeTransactionId;

  /// 暂停后自动恢复时间（Google Play only）。
  final String? autoResumeDate;

  /// 后台配置的展示名。
  final String? displayName;

  /// 订阅管理页 URL。
  final String? managementURL;

  /// Google base plan id。
  final String? productPlanIdentifier;

  const SubscriptionInfo(
    this.productIdentifier,
    this.purchaseDate,
    this.isSandbox,
    this.isActive,
    this.willRenew, {
    this.originalPurchaseDate,
    this.expiresDate,
    this.store = Store.unknownStore,
    this.unsubscribeDetectedAt,
    this.billingIssuesDetectedAt,
    this.gracePeriodExpiresDate,
    this.ownershipType = OwnershipType.unknown,
    this.periodType = PeriodType.unknown,
    this.refundedAt,
    this.storeTransactionId,
    this.autoResumeDate,
    this.displayName,
    this.managementURL,
    this.productPlanIdentifier,
  });

  /// 由通道 map 构造（设计 §5.1b）。缺键 / 类型错抛码 12。
  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) =>
      decodeSubscriptionInfo(WireMap.fromChannel(json));

  @override
  List<Object?> get props => [
        productIdentifier,
        purchaseDate,
        isSandbox,
        isActive,
        willRenew,
        originalPurchaseDate,
        expiresDate,
        store,
        unsubscribeDetectedAt,
        billingIssuesDetectedAt,
        gracePeriodExpiresDate,
        ownershipType,
        periodType,
        refundedAt,
        storeTransactionId,
        autoResumeDate,
        displayName,
        managementURL,
        productPlanIdentifier,
      ];
}

/// wire → [SubscriptionInfo]（不导出）。
SubscriptionInfo decodeSubscriptionInfo(WireMap w) => SubscriptionInfo(
      w.requireString('productIdentifier'),
      w.requireDate('purchaseDate'),
      w.requireBool('isSandbox'),
      w.requireBool('isActive'),
      w.requireBool('willRenew'),
      originalPurchaseDate: w.optionalDate('originalPurchaseDate'),
      expiresDate: w.optionalDate('expiresDate'),
      store: w.requireEnum('store', storeByWire, Store.unknownStore),
      unsubscribeDetectedAt: w.optionalDate('unsubscribeDetectedAt'),
      billingIssuesDetectedAt: w.optionalDate('billingIssuesDetectedAt'),
      gracePeriodExpiresDate: w.optionalDate('gracePeriodExpiresDate'),
      ownershipType: w.requireEnum('ownershipType', ownershipTypeByWire, OwnershipType.unknown),
      periodType: w.requireEnum('periodType', periodTypeByWire, PeriodType.unknown),
      refundedAt: w.optionalDate('refundedAt'),
      storeTransactionId: w.optionalString('storeTransactionId'),
      autoResumeDate: w.optionalDate('autoResumeDate'),
      displayName: w.optionalString('displayName'),
      managementURL: w.optionalString('managementURL'),
      productPlanIdentifier: w.optionalString('productPlanIdentifier'),
    );
