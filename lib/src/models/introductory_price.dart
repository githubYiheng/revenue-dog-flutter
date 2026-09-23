import 'package:equatable/equatable.dart';

import '../wire.dart';
import 'period_unit.dart';

/// 介绍性优惠（免费试用 / 优惠价）。对照 RC：字段集、构造签名逐字照 RC 10.13.1 `IntroductoryPrice`。
///
/// 通道形状（设计 §5.4）：`{priceAmountMicros, priceString, period, periodUnit, periodNumberOfUnits, cycles}`；
/// [price] 由 Dart 从 micros 派生。iOS 来源 `introductoryOffer`（0.4.0 数值价，免费试用 = 0）；
/// Android 来源 `defaultOption.freePhase ?? introPhase`。
/// 偏离 RC Android：周期按 Play 原始单位（不把 WEEK 改写成 DAY×7），价串取商店串（不是设备 locale 的零价串）。
class IntroductoryPrice extends Equatable {
  /// 优惠价（免费试用 = 0）。
  final double price;

  /// 商店本地化价串。
  final String priceString;

  /// ISO 8601 周期（如 `P1W`）。
  final String period;

  /// 优惠周期重复次数。
  final int cycles;

  /// 周期单位。
  final PeriodUnit periodUnit;

  /// 每个周期的单位数量。
  final int periodNumberOfUnits;

  const IntroductoryPrice(
    this.price,
    this.priceString,
    this.period,
    this.cycles,
    this.periodUnit,
    this.periodNumberOfUnits,
  );

  /// 由通道 map 构造。缺键 / 类型错抛码 12。
  factory IntroductoryPrice.fromJson(Map<String, dynamic> json) =>
      decodeIntroductoryPrice(WireMap.fromChannel(json));

  @override
  List<Object?> get props => [price, priceString, period, cycles, periodUnit, periodNumberOfUnits];
}

/// wire → [IntroductoryPrice]（不导出）。
IntroductoryPrice decodeIntroductoryPrice(WireMap w) => IntroductoryPrice(
      priceFromMicros(w.requireInt('priceAmountMicros')),
      w.requireString('priceString'),
      w.requireString('period'),
      w.requireInt('cycles'),
      w.requireEnum('periodUnit', periodUnitByWire, PeriodUnit.unknown),
      w.requireInt('periodNumberOfUnits'),
    );
