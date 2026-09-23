import 'package:equatable/equatable.dart';

import '../wire.dart';
import 'offering.dart';

/// 全部 offering。对照 RC：字段集、构造签名、`getOffering` 逐字照 RC 10.13.1 `Offerings`；填充规则见设计 §5.3。
///
/// 通道形状：`{all: {id: Offering}, current: Offering?}`，`current` 键恒在。
/// 剔除规则（原生插件执行，裁定 5）：查不到商品的 package 剔除、剔空的 offering 从 [all] 去掉；
/// [current] 因此被剔掉时为 `null`；原生 offerings 非空但**全部** package 查不到商品 → `getOfferings` 抛码 2。
class Offerings extends Equatable {
  /// offering 标识 → offering。
  final Map<String, Offering> all;

  /// 当前 offering。
  final Offering? current;

  const Offerings(this.all, {this.current});

  /// 按标识取 offering。
  Offering? getOffering(String identifier) => all[identifier];

  /// 由通道 map 构造（设计 §5.3）。缺键 / 类型错 / `current` 不在 `all` 中抛码 12。
  factory Offerings.fromJson(Map<String, dynamic> json) => decodeOfferings(WireMap.fromChannel(json));

  @override
  List<Object?> get props => [all, current];
}

/// wire → [Offerings]（不导出）。`current` 必须等于 `all[current.identifier]`（否则码 12）。
Offerings decodeOfferings(WireMap w) {
  final all = w.requireMapOfMaps('all').map((k, v) => MapEntry(k, decodeOffering(v)));
  all.forEach((key, offering) {
    if (offering.identifier != key) {
      throwWireError(w.keyPath('all.$key.identifier'), 'does not match map key $key');
    }
  });
  w.requirePresent('current');
  final currentMap = w.optionalMap('current');
  final current = currentMap == null ? null : decodeOffering(currentMap);
  if (current != null && all[current.identifier] != current) {
    throwWireError(w.keyPath('current'), 'current offering ${current.identifier} is not in all');
  }
  return Offerings(all, current: current);
}
