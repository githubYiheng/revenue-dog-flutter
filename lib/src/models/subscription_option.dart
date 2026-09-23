import 'package:equatable/equatable.dart';

import '../wire.dart';
import 'installments_info.dart';
import 'period.dart';
import 'presented_offering_context.dart';
import 'pricing_phase.dart';

/// Play 订阅选项（base plan 或 offer；Android only，iOS 为 null，同 RC iOS）。
/// 对照 RC：字段集（13 字段）、构造签名逐字照 RC 10.13.1 `SubscriptionOption`。
///
/// 通道形状（设计 §5.4b）：`{id, storeProductId, productId, pricingPhases, tags, isBasePlan, billingPeriod, isPrepaid,
/// fullPricePhase, freePhase, introPhase, presentedOfferingContext}`；
/// `id` = `basePlanId` 或 `basePlanId:offerId`，`storeProductId` = `productId:basePlanId`。
/// [installmentsInfo] 为文档化常量 `null`（通道不发）。
class SubscriptionOption extends Equatable {
  /// 选项标识（`basePlanId` 或 `basePlanId:offerId`）。
  final String id;

  /// `productId:basePlanId`。
  final String storeProductId;

  /// Play subscriptionId。
  final String productId;

  /// 定价阶段（按时间顺序，最后一个为全价阶段）。
  final List<PricingPhase> pricingPhases;

  /// Play 后台配置的 offer tag。
  final List<String> tags;

  /// 是否为 base plan（只有一个定价阶段）。
  final bool isBasePlan;

  /// 全价阶段的计费周期。
  final Period? billingPeriod;

  /// 是否预付费。
  final bool isPrepaid;

  /// 全价阶段。
  final PricingPhase? fullPricePhase;

  /// 免费试用阶段。
  final PricingPhase? freePhase;

  /// 优惠价阶段。
  final PricingPhase? introPhase;

  /// 所属 offering 上下文。
  final PresentedOfferingContext? presentedOfferingContext;

  /// Play 分期信息（我方恒 null）。
  final InstallmentsInfo? installmentsInfo;

  const SubscriptionOption(
    this.id,
    this.storeProductId,
    this.productId,
    this.pricingPhases,
    this.tags,
    this.isBasePlan,
    this.billingPeriod,
    this.isPrepaid,
    this.fullPricePhase,
    this.freePhase,
    this.introPhase,
    this.presentedOfferingContext,
    this.installmentsInfo,
  );

  /// 由通道 map 构造。缺键 / 类型错抛码 12。
  factory SubscriptionOption.fromJson(Map<String, dynamic> json) =>
      decodeSubscriptionOption(WireMap.fromChannel(json));

  @override
  List<Object?> get props => [
        id,
        storeProductId,
        productId,
        pricingPhases,
        tags,
        isBasePlan,
        billingPeriod,
        isPrepaid,
        fullPricePhase,
        freePhase,
        introPhase,
        presentedOfferingContext,
        installmentsInfo,
      ];
}

/// 对照 RC：`ExtendedSubscriptionOption`（弃用的 offering 标识 getter）逐字照抄。
extension ExtendedSubscriptionOption on SubscriptionOption {
  /// 所属 offering 标识。
  @Deprecated('use presentedOfferingContext')
  String? get presentedOfferingIdentifier => presentedOfferingContext?.offeringIdentifier;
}

/// wire → [SubscriptionOption]（不导出）。
SubscriptionOption decodeSubscriptionOption(WireMap w) {
  final billingPeriod = w.optionalMap('billingPeriod');
  final fullPricePhase = w.optionalMap('fullPricePhase');
  final freePhase = w.optionalMap('freePhase');
  final introPhase = w.optionalMap('introPhase');
  final context = w.optionalMap('presentedOfferingContext');
  return SubscriptionOption(
    w.requireString('id'),
    w.requireString('storeProductId'),
    w.requireString('productId'),
    w.requireMapList('pricingPhases').map(decodePricingPhase).toList(),
    w.requireStringList('tags'),
    w.requireBool('isBasePlan'),
    billingPeriod == null ? null : decodePeriod(billingPeriod),
    w.requireBool('isPrepaid'),
    fullPricePhase == null ? null : decodePricingPhase(fullPricePhase),
    freePhase == null ? null : decodePricingPhase(freePhase),
    introPhase == null ? null : decodePricingPhase(introPhase),
    context == null ? null : decodePresentedOfferingContext(context),
    null,
  );
}
