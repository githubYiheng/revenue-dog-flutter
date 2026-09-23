import 'package:equatable/equatable.dart';

import '../wire.dart';

/// 定价阶段的价格（Android only）。对照 RC：字段集、构造签名逐字照 RC 10.13.1 `Price`。
/// 通道形状（设计 §5.4b）：`{formatted, amountMicros, currencyCode}`（RC Dart 本就是 micros）。
class Price extends Equatable {
  /// 商店本地化价串。
  final String formatted;

  /// 金额 micros。
  final int amountMicros;

  /// ISO 4217 币种码。
  final String currencyCode;

  const Price(this.formatted, this.amountMicros, this.currencyCode);

  /// 由通道 map 构造。缺键 / 类型错抛码 12。
  factory Price.fromJson(Map<String, dynamic> json) => decodePrice(WireMap.fromChannel(json));

  @override
  List<Object?> get props => [formatted, amountMicros, currencyCode];
}

/// wire → [Price]（不导出）。
Price decodePrice(WireMap w) =>
    Price(w.requireString('formatted'), w.requireInt('amountMicros'), w.requireString('currencyCode'));
