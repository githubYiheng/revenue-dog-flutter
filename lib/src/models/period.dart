import 'package:equatable/equatable.dart';

import '../wire.dart';
import 'period_unit.dart';

/// 计费周期（Android only）。对照 RC：字段集、构造签名逐字照 RC 10.13.1 `Period`。
/// 通道形状（设计 §5.4b）：`{unit, value, iso8601}`，`unit` 为 `day|week|month|year|unknown`，按 Play 原始单位。
class Period extends Equatable {
  /// 单位。
  final PeriodUnit unit;

  /// 单位数量。
  final int value;

  /// ISO 8601 原文（Play 原样）。
  final String iso8601;

  const Period(this.unit, this.value, this.iso8601);

  /// 由通道 map 构造。缺键 / 类型错抛码 12。
  factory Period.fromJson(Map<String, dynamic> json) => decodePeriod(WireMap.fromChannel(json));

  @override
  List<Object> get props => [unit, value, iso8601];
}

/// wire → [Period]（不导出）。
Period decodePeriod(WireMap w) => Period(
      w.requireEnum('unit', periodUnitByWire, PeriodUnit.unknown),
      w.requireInt('value'),
      w.requireString('iso8601'),
    );
