import 'package:equatable/equatable.dart';

import '../wire.dart';

/// 一笔商店交易。对照 RC：字段集与构造签名逐字照 RC `StoreTransaction`（3 字段）。
///
/// M1 只用于 `CustomerInfo.nonSubscriptionTransactions`（`transactionIdentifier` = 后端交易 `id`）；
/// M2 的 `PurchaseResult.storeTransaction` 复用本类（设计 §5.5）。
/// 偏离 RC：RC 把缺失的 `transactionIdentifier` 吞成 `''`；我方缺失 / 空串一律抛码 12（裁定 3）。
class StoreTransaction extends Equatable {
  /// 交易标识。
  final String transactionIdentifier;

  /// 商品标识。
  final String productIdentifier;

  /// 购买时间（UTC ISO 8601）。
  final String purchaseDate;

  const StoreTransaction(
    this.transactionIdentifier,
    this.productIdentifier,
    this.purchaseDate,
  );

  /// 由通道 map 构造（设计 §5.5）。缺键 / 类型错 / 交易 id 为空抛码 12。
  factory StoreTransaction.fromJson(Map<String, dynamic> json) =>
      decodeStoreTransaction(WireMap.fromChannel(json));

  @override
  List<Object> get props => [transactionIdentifier, productIdentifier, purchaseDate];
}

/// wire → [StoreTransaction]（不导出）。
StoreTransaction decodeStoreTransaction(WireMap w) {
  final id = w.requireString('transactionIdentifier');
  if (id.isEmpty) throwWireError(w.keyPath('transactionIdentifier'), 'empty transaction identifier');
  return StoreTransaction(id, w.requireString('productIdentifier'), w.requireDate('purchaseDate'));
}
