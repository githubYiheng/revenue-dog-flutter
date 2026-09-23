import 'package:equatable/equatable.dart';

import '../wire.dart';
import 'customer_info.dart';
import 'store_transaction.dart';

/// 购买结果。对照 RC：字段集、构造签名逐字照 RC 10.13.1 `PurchaseResult`。
///
/// 通道形状（设计 §5.5）：`{customerInfo, storeTransaction: {transactionIdentifier, productIdentifier, purchaseDate(ms)}}`。
/// 偏离 RC：交易键为 `storeTransaction`（RC 通道为 `transaction`）；交易 id 为空抛码 12（不吞成 `''`）。
class PurchaseResult extends Equatable {
  /// 购买后的用户快照。
  final CustomerInfo customerInfo;

  /// 本次交易。
  final StoreTransaction storeTransaction;

  const PurchaseResult(this.customerInfo, this.storeTransaction);

  /// 由通道 map 构造。缺键 / 类型错抛码 12。
  factory PurchaseResult.fromJson(Map<String, dynamic> json) => decodePurchaseResult(WireMap.fromChannel(json));

  @override
  List<Object> get props => [customerInfo, storeTransaction];
}

/// wire → [PurchaseResult]（不导出）。
PurchaseResult decodePurchaseResult(WireMap w) => PurchaseResult(
      decodeCustomerInfo(w.requireMap('customerInfo')),
      decodeStoreTransaction(w.requireMap('storeTransaction')),
    );
