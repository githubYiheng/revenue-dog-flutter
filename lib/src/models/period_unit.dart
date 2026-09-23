/// 周期单位。对照 RC：值集与顺序逐字照 RC 10.13.1 `PeriodUnit`。通道值 `day|week|month|year|unknown`。
///
/// 偏离 RC：Android 上按 Play 原始单位报（配成 1 周的试用报「1 周」），RC Android 改写成「7 天」（设计 §5.4）。
enum PeriodUnit {
  /// 天。
  day,

  /// 周。
  week,

  /// 月。
  month,

  /// 年。
  year,

  /// 无法识别。
  unknown,
}

/// 通道值 → [PeriodUnit]（不导出）。未知值 → [PeriodUnit.unknown]。
const Map<String, PeriodUnit> periodUnitByWire = {
  'day': PeriodUnit.day,
  'week': PeriodUnit.week,
  'month': PeriodUnit.month,
  'year': PeriodUnit.year,
  'unknown': PeriodUnit.unknown,
};
