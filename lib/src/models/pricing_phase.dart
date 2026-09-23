import 'package:equatable/equatable.dart';

import '../wire.dart';
import 'period.dart';
import 'price.dart';

/// 定价阶段的续订模式。对照 RC：值集与顺序逐字照 RC 10.13.1 `RecurrenceMode`。
///
/// 偏离 RC：RC 通道发 Google 整数（1 / 2 / 3）；我方发 `infinite_recurring|finite_recurring|non_recurring|unknown`（设计 §5.4b）。
enum RecurrenceMode {
  /// 无限续订（全价阶段）。
  infiniteRecurring,

  /// 有限次续订（优惠阶段）。
  finiteRecurring,

  /// 不续订（预付费）。
  nonRecurring,

  /// 无法识别。
  unknown,
}

/// 优惠阶段的付费模式。对照 RC：值集与顺序逐字照 RC 10.13.1 `OfferPaymentMode`。
/// 通道值 `free_trial|single_payment|discounted_recurring_payment`，未知 → `null`（照 RC）。
enum OfferPaymentMode {
  /// 免费试用。
  freeTrial,

  /// 一次性预付一段时间。
  singlePayment,

  /// 按折扣价连续扣若干周期。
  discountedRecurringPayment,
}

/// 通道值 → [RecurrenceMode]（不导出）。未知值 → [RecurrenceMode.unknown]。
const Map<String, RecurrenceMode> recurrenceModeByWire = {
  'infinite_recurring': RecurrenceMode.infiniteRecurring,
  'finite_recurring': RecurrenceMode.finiteRecurring,
  'non_recurring': RecurrenceMode.nonRecurring,
  'unknown': RecurrenceMode.unknown,
};

/// 通道值 → [OfferPaymentMode]（不导出）。
const Map<String, OfferPaymentMode> offerPaymentModeByWire = {
  'free_trial': OfferPaymentMode.freeTrial,
  'single_payment': OfferPaymentMode.singlePayment,
  'discounted_recurring_payment': OfferPaymentMode.discountedRecurringPayment,
};

/// 订阅选项里的一个定价阶段（Android only）。对照 RC：字段集、构造签名逐字照 RC 10.13.1 `PricingPhase`。
///
/// 通道形状（设计 §5.4b）：`{billingPeriod, recurrenceMode, billingCycleCount, price, offerPaymentMode}`；
/// `billingPeriod` / `price` 契约非空（RC 类型上 `billingPeriod` 可空，照 RC 保留可空类型）。
class PricingPhase extends Equatable {
  /// 本阶段计费周期。
  final Period? billingPeriod;

  /// 续订模式。
  final RecurrenceMode? recurrenceMode;

  /// 本阶段计费次数（无限续订 / 预付费为 null）。
  final int? billingCycleCount;

  /// 本阶段价格。
  final Price price;

  /// 付费模式（非优惠阶段为 null）。
  final OfferPaymentMode? offerPaymentMode;

  const PricingPhase(
    this.billingPeriod,
    this.recurrenceMode,
    this.billingCycleCount,
    this.price,
    this.offerPaymentMode,
  );

  /// 由通道 map 构造。缺键 / 类型错抛码 12。
  factory PricingPhase.fromJson(Map<String, dynamic> json) => decodePricingPhase(WireMap.fromChannel(json));

  @override
  List<Object?> get props => [billingPeriod, recurrenceMode, billingCycleCount, price, offerPaymentMode];
}

/// wire → [PricingPhase]（不导出）。
PricingPhase decodePricingPhase(WireMap w) => PricingPhase(
      decodePeriod(w.requireMap('billingPeriod')),
      w.requireEnum('recurrenceMode', recurrenceModeByWire, RecurrenceMode.unknown),
      w.optionalInt('billingCycleCount'),
      decodePrice(w.requireMap('price')),
      w.optionalEnum('offerPaymentMode', offerPaymentModeByWire, null),
    );
