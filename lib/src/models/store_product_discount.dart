import 'package:equatable/equatable.dart';

/// iOS 促销优惠。对照 RC：字段集、构造签名逐字照 RC 10.13.1 `StoreProductDiscount`。
///
/// 我方不支持 iOS 促销优惠：`StoreProduct.discounts` 为文档化常量 `null`（同 RC Android），通道不发（设计 §5.4）。
/// 偏离 RC：只声明类型，不提供 `fromJson`（本类型从不经过通道）。
class StoreProductDiscount extends Equatable {
  /// 优惠标识。
  final String identifier;

  /// 优惠价。
  final double price;

  /// 本地化价串。
  final String priceString;

  /// 周期重复次数。
  final int cycles;

  /// ISO 8601 周期。
  final String period;

  /// 周期单位（RC 为字符串）。
  final String periodUnit;

  /// 每个周期的单位数量。
  final int periodNumberOfUnits;

  const StoreProductDiscount(
    this.identifier,
    this.price,
    this.priceString,
    this.cycles,
    this.period,
    this.periodUnit,
    this.periodNumberOfUnits,
  );

  @override
  List<Object?> get props => [identifier, price, priceString, cycles, period, periodUnit, periodNumberOfUnits];
}
